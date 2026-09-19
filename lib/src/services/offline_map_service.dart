import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// État du fond de plan offline.
enum OfflineMapStatus {
  /// Aucune carte téléchargée : l'app fonctionne mais sans fond de plan.
  none,

  /// Une carte offline est présente et utilisable.
  ready,
}

/// Résultat d'un téléchargement de région offline.
class OfflineDownloadResult {
  final bool ok;
  final int tilesDownloaded;
  final String? error;

  const OfflineDownloadResult({
    required this.ok,
    required this.tilesDownloaded,
    this.error,
  });
}

/// Gestionnaire du fond de plan offline (tiles raster stockées localement).
///
/// ## Principe offline-first
///
/// Au premier lancement, l'utilisateur sélectionne (ou saisit) une zone
/// et lance le téléchargement : les tuiles OSM sont récupérées sur le
/// réseau et stockées dans le répertoire documents de l'app
/// (`<docs>/map_tiles/<z>/<x>/<y>.png`). Ensuite, l'application
/// fonctionne **entièrement hors ligne** : le `FileTileProvider` lit
/// directement les tuiles sur disque, sans aucune requête réseau.
///
/// ## Pré-requis de licence
///
/// Les tuiles OSM sont soumises à la politique d'utilisation d'OSM :
/// usage léger, attribution obligatoire. Pour un usage intensif ou
/// professionnel, brancher un fournisseur de tuiles adapté (IGN, MapTiler,
/// etc.) en changeant simplement le modèle d'URL (`networkUrlTemplate`).
class OfflineMapService {
  /// Modèle d'URL des tuiles raster (OSM par défaut).
  static const _tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// User-Agent requis par la politique d'OSM.
  static const _userAgent = 'zone_coverage/1.0 (offline-first GPS app)';

  /// Répertoire racine des tuiles offline.
  static const _tilesDir = 'map_tiles';

  /// Zooms téléchargés pour la région.
  final int minZoom;
  final int maxZoom;

  OfflineMapService({this.minZoom = 12, this.maxZoom = 16});

  /// Statut du fond de plan : au moins une tuile stockée ?
  Future<OfflineMapStatus> status() async {
    final dir = await _tilesRoot();
    if (!await dir.exists()) return OfflineMapStatus.none;
    await for (final _ in dir.list()) {
      return OfflineMapStatus.ready;
    }
    return OfflineMapStatus.none;
  }

  /// Chemin local du fond de plan pour le [TileLayer] (mode offline pur).
  ///
  /// `FileTileProvider` lit les tuiles directement sur disque via le
  /// `urlTemplate` branché sur ce chemin. Si aucune tuile n'existe
  /// (premier lancement), `urlTemplate` réseau classiq
  /// [_networkUrlTemplate] est utilisé pour que la carte reste visible
  /// tant que la région n'a pas été téléchargée.
  Future<String> offlineUrlTemplate() async {
    final root = await _tilesRoot();
    return '${root.path}/$zxyTemplate';
  }

  /// URL réseau du fond de plan (pré-téléchargement uniquement).
  static const _networkUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Modèle de sous-chemin z/x/y.
  static const zxyTemplate = '{z}/{x}/{y}.png';

  /// Modèle d'URL réseau complet (exposé pour le premier lancement).
  String get networkUrlTemplate => _networkUrlTemplate;

  /// Télécharge et stocke toutes les tuiles de [bounds] aux zooms
  /// [minZoom]..[maxZoom].
  ///
  /// Envoie une progression via [onProgress] (0..1). Retourne le nombre
  /// de tuiles écrites.
  Future<OfflineDownloadResult> downloadRegion({
    required LatLngBounds bounds,
    void Function(double progress)? onProgress,
  }) async {
    final root = await _tilesRoot();
    await root.create(recursive: true);

    var total = 0;
    var done = 0;
    final errors = <String>[];

    // Comptage d'abord (pour la progression).
    for (var z = minZoom; z <= maxZoom; z++) {
      total += _tileCount(bounds, z);
    }
    if (total == 0) {
      return const OfflineDownloadResult(ok: false, tilesDownloaded: 0);
    }

    final client = HttpClient();
    try {
      for (var z = minZoom; z <= maxZoom; z++) {
        final range = _tileRange(bounds, z);
        for (var x = range.$1; x <= range.$2; x++) {
          for (var y = range.$3; y <= range.$4; y++) {
            final file = await _tileFile(root, z, x, y);
            if (await file.exists()) {
              done++;
              continue;
            }
            try {
              final bytes = await _fetchTile(client, z, x, y);
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes);
              done++;
            } catch (e) {
              errors.add('z$z/$x/$y: $e');
            }
            onProgress?.call(done / total);
          }
        }
      }
    } finally {
      client.close();
    }

    return OfflineDownloadResult(
      ok: errors.isEmpty,
      tilesDownloaded: done,
      error: errors.isEmpty ? null : errors.take(3).join('; '),
    );
  }

  /// Nombre total de tuiles couvrant [bounds] au zoom [z].
  int _tileCount(LatLngBounds bounds, int z) {
    final r = _tileRange(bounds, z);
    return (r.$2 - r.$1 + 1) * (r.$4 - r.$3 + 1);
  }

  /// Range de tuiles couvrant [bounds] au zoom [z] : (xMin, xMax, yMin, yMax).
  (int, int, int, int) _tileRange(LatLngBounds bounds, int z) {
    final n = 1 << z;
    final west = _lngToTileX(bounds.west, n);
    final east = _lngToTileX(bounds.east, n);
    final north = _latToTileY(bounds.north, n);
    final south = _latToTileY(bounds.south, n);
    return (west, east, north, south);
  }

  int _lngToTileX(double lng, int n) =>
      ((lng + 180) / 360 * n).floor().clamp(0, n - 1);

  int _latToTileY(double lat, int n) {
    final latR = lat * math.pi / 180;
    final y = (1 -
            (math.log(math.tan(latR) + 1 / math.cos(latR)) + math.pi) /
                (2 * math.pi)) *
        n;
    return y.floor().clamp(0, n - 1);
  }

  Future<File> _tileFile(Directory root, int z, int x, int y) async {
    final dir = Directory('${root.path}/$z/$x');
    return File('${dir.path}/$y.png');
  }

  Future<Directory> _tilesRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$_tilesDir');
  }

  Future<List<int>> _fetchTile(HttpClient client, int z, int x, int y) async {
    final url = Uri.parse(_tileUrlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y'));
    final req = await client.getUrl(url);
    req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} for $url');
    }
    final bytes = await res.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    return bytes;
  }
}


