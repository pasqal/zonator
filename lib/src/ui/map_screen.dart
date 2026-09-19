import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/tracking_controller.dart';
import '../services/offline_map_service.dart';

/// Couleurs du pinceau (zone couverte temps réel).
const _coverageColor = Color(0x662196F3);
const _coverageBorder = Color(0xFF2196F3);

/// Carte plein écran : fond de plan offline + pinceau géant temps réel.
///
/// Le fond de plan utilise `FileTileProvider` branché sur le cache
/// local si une région a été téléchargée (offline-first) ; sinon, en
/// attendant le premier téléchargement, l'URL réseau est utilisée.
///
/// La zone couverte est rendue par un `PolygonLayer` : une `Polygon`
/// par capsule temps réel. Les capsules étant opaques et chevauchantes,
/// leur union visuelle est identique à l'union géométrique — sans
/// jamais recalculer l'union pendant l'enregistrement.
class MapScreen extends StatefulWidget {
  final TrackingController controller;
  final OfflineMapService offlineMap;

  const MapScreen({
    super.key,
    required this.controller,
    required this.offlineMap,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  /// État offline : null = en cours de vérification.
  bool? _offlineReady;

  /// Chemin des tuiles offline (rempli après la vérification).
  String? _offlineUrl;

  @override
  void initState() {
    super.initState();
    _initTileSource();
  }

  Future<void> _initTileSource() async {
    final status = await widget.offlineMap.status();
    if (status == OfflineMapStatus.ready) {
      final url = await widget.offlineMap.offlineUrlTemplate();
      setState(() {
        _offlineReady = true;
        _offlineUrl = url;
      });
    } else {
      setState(() => _offlineReady = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final offline = _offlineReady == true;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter(controller),
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: offline
              ? _offlineUrl!
              : widget.offlineMap.networkUrlTemplate,
          tileProvider: offline ? FileTileProvider() : null,
          maxNativeZoom: widget.offlineMap.maxZoom,
          userAgentPackageName: 'dev.vibe.zone_coverage',
          // Pas de fallback réseau en mode offline : si la tuile manque
          // (hors région téléchargée), elle n'est simplement pas affichée.
        ),
        PolygonLayer(
          polygons: [
            for (final capsule in controller.brushSegments)
              Polygon(
                points: capsule,
                color: _coverageColor,
                borderColor: _coverageBorder,
                borderStrokeWidth: 1,
              ),
          ],
        ),
        CircleLayer(
          circles: [
            if (controller.currentPosition case final pos?)
              CircleMarker(
                point: pos.position,
                radius: 6,
                useRadiusInMeter: false,
                color: Colors.blue,
                borderStrokeWidth: 2,
                borderColor: Colors.white,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final poi in controller.pois)
              Marker(
                point: poi.position,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40,
                ),
              ),
          ],
        ),
      ],
    );
  }

  LatLng _initialCenter(TrackingController controller) {
    final pos = controller.currentPosition;
    if (pos != null) return pos.position;
    return const LatLng(48.8566, 2.3522);
  }
}
