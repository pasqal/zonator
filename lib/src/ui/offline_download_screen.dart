import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/offline_map_service.dart';

/// Écran de téléchargement de la carte de base (premier lancement).
///
/// L'utilisateur navigue/zoome sur la zone souhaitée puis appuie sur
/// « Télécharger cette zone » : toutes les tuiles visibles (aux zooms
/// minZoom..maxZoom du service) sont stockées localement. Ensuite,
/// l'application fonctionne entièrement hors ligne.
class OfflineMapDownloadScreen extends StatefulWidget {
  final OfflineMapService service;

  const OfflineMapDownloadScreen({super.key, required this.service});

  @override
  State<OfflineMapDownloadScreen> createState() =>
      _OfflineMapDownloadScreenState();
}

class _OfflineMapDownloadScreenState extends State<OfflineMapDownloadScreen> {
  final MapController _mapController = MapController();
  double _progress = 0;
  bool _downloading = false;
  String? _result;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _result = null;
    });
    final camera = _mapController.camera;
    final bounds = camera.visibleBounds;
    final result = await widget.service.downloadRegion(
      bounds: bounds,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _result = result.ok
          ? '${result.tilesDownloaded} tuiles enregistrées. '
              'La carte est maintenant disponible hors ligne.'
          : 'Terminé avec des erreurs : ${result.error}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carte hors ligne')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(48.8566, 2.3522),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: widget.service.networkUrlTemplate,
                  userAgentPackageName: 'dev.vibe.zone_coverage',
                  maxNativeZoom: widget.service.maxZoom,
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_downloading)
                    LinearProgressIndicator(value: _progress)
                  else ...[
                    Text(
                      _result ??
                          'Naviguez jusqu\u2019à la zone à couvrir, puis '
                              'téléchargez les tuiles pour un usage hors ligne.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Télécharger cette zone'),
                      onPressed: _download,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
