import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../geometry/clipper_union.dart';
import '../geometry/coverage_engine.dart';
import '../geometry/local_projection.dart';
import '../models/session.dart';

/// État exposé à l'UI par le [TrackingController].
enum TrackingState { idle, recording, stopped }

/// Point GPS brut enrichi pour le rendu.
class TrackingPosition {
  final LatLng position;
  final double accuracy;
  final double speed;
  final DateTime timestamp;

  const TrackingPosition({
    required this.position,
    required this.accuracy,
    required this.speed,
    required this.timestamp,
  });
}

/// Contrôleur central du « pinceau géant ».
///
/// Responsabilités :
/// - consommer le flux GPS (geolocator) ;
/// - échantillonner la trajectoire (distance minimale [minSampleDistance]) ;
/// - générer **incrémentalement** les capsules temps réel (une par fix
///   accepté) — c'est ce qui garantit l'absence de lag : aucun recalcul
///   global n'est fait pendant l'enregistrement ;
/// - au « Stop », préparer l'union exacte (clipper2) **en isolate** pour
///   ne jamais bloquer l'UI, puis produire le KML.
///
/// Le contrôleur étend [ChangeNotifier] : l'UI écoute et reconstruit
/// les couches de carte à chaque notification (throttlée).
class TrackingController extends ChangeNotifier {
  /// Rayon du pinceau (m), issu des paramètres.
  final double brushRadiusMeters;

  /// Distance minimale entre deux échantillons GPS (m).
  ///
  /// Évite la prolifération de capsules quasi identiques quand l'app
  /// est immobile (le GPS dérive naturellement de quelques mètres).
  static const double minSampleDistance = 1.0;

  /// Durée minimale entre deux notifications UI.
  static const _uiThrottle = Duration(milliseconds: 100);

  final CoverageEngine _engine = CoverageEngine();

  /// Session en cours (créée au « Commencer »).
  RecordingSession? _session;

  /// Souscription au flux GPS.
  StreamSubscription<Position>? _positionSubscription;

  /// Positions GPS reçues (pour la position courante à l'écran).
  final List<TrackingPosition> _positions = [];

  /// Capsules temps réel, en lat/long, prêtes pour le rendu carte.
  ///
  /// Une capsule = un polygone flutter_map (`List<LatLng>`).
  final List<List<LatLng>> _brushSegments = [];

  /// Date de la dernière notification (throttle).
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// État courant du tracking.
  TrackingState _state = TrackingState.idle;

  TrackingController({required this.brushRadiusMeters});

  /// État du tracking.
  TrackingState get state => _state;

  /// Vrai pendant l'enregistrement.
  bool get isRecording => _state == TrackingState.recording;

  /// Position GPS courante (null avant le premier fix).
  TrackingPosition? get currentPosition =>
      _positions.isEmpty ? null : _positions.last;

  /// Nombre de points GPS enregistrés.
  int get sampleCount => _session?.samples.length ?? 0;

  /// POI de la session en cours.
  List<Poi> get pois => _session?.pois ?? const [];

  /// Capsules temps réel pour la carte (lat/long).
  List<List<LatLng>> get brushSegments => List.unmodifiable(_brushSegments);

  /// Trajectoire GPS échantillonnée (pour la polyline éventuelle).
  List<LatLng> get trajectory =>
      _session == null ? const [] : List.unmodifiable(_session!.samples);

  /// Démarre l'enregistrement : crée la session et souscrit au flux GPS.
  Future<void> start() async {
    if (_state == TrackingState.recording) return;
    _session = RecordingSession(
      id: DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
      startedAt: DateTime.now().toUtc(),
      brushRadiusMeters: brushRadiusMeters,
    );
    _positions.clear();
    _brushSegments.clear();
    _state = TrackingState.recording;
    notifyListeners();

    final positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    );
    _positionSubscription = positionStream.listen(_onPosition);
  }

  /// Arrête l'enregistrement et fige la session.
  Future<TrackingSession> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _state = TrackingState.stopped;
    notifyListeners();
    return _session?.freeze() ?? TrackingSession(
      id: 'empty',
      startedAt: DateTime.now().toUtc(),
      brushRadiusMeters: brushRadiusMeters,
    );
  }

  /// Ajoute un signalement (POI) à la session courante.
  void addReport({required String state, required String comment}) {
    final session = _session;
    final pos = currentPosition;
    if (session == null || pos == null) return;
    session.addPoi(Poi(
      id: 'poi-${session.pois.length + 1}',
      position: pos.position,
      state: state,
      comment: comment,
      timestamp: DateTime.now().toUtc(),
    ));
    notifyListeners();
  }

  /// Remet le contrôleur à l'état initial (nouvelle session).
  void reset() {
    _state = TrackingState.idle;
    _session = null;
    _brushSegments.clear();
    _positions.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// Traite un fix GPS : échantillonnage, capsule incrémentale, throttle.
  void _onPosition(Position p) {
    if (_state != TrackingState.recording) return;
    final latLng = LatLng(p.latitude, p.longitude);
    final tracking = TrackingPosition(
      position: latLng,
      accuracy: p.accuracy,
      speed: p.speed,
      timestamp: p.timestamp,
    );
    _positions.add(tracking);

    final session = _session!;
    final samples = session.samples;
    final last = samples.isEmpty ? null : samples.last;
    final moved = last == null ||
        _distanceMeters(last, latLng) >= minSampleDistance;
    if (!moved) return;

    session.addSample(latLng);

    // Capsule incrémentale : uniquement entre le dernier point accepté et
    // le nouveau — O(k) par fix, aucun recalcul global.
    if (last != null) {
      final proj = LocalProjection(samples.first);
      final a = proj.project(last);
      final b = proj.project(latLng);
      final capsule = _engine.buildBrushSegmentsLocal([a, b], brushRadiusMeters);
      for (final poly in capsule) {
        _brushSegments.add([for (final pt in poly) proj.unproject(pt)]);
      }
    } else {
      // Premier point : disque seul.
      final proj = LocalProjection(latLng);
      final disk = _engine.buildBrushSegmentsLocal(
        [proj.project(latLng)],
        brushRadiusMeters,
      );
      for (final poly in disk) {
        _brushSegments.add([for (final pt in poly) proj.unproject(pt)]);
      }
    }

    _throttledNotify();
  }

  /// Notification UI throttlée : limite les rebuilds à ~10 Hz.
  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < _uiThrottle) return;
    _lastNotify = now;
    notifyListeners();
  }

  /// Distance approximative entre deux points GPS (m).
  double _distanceMeters(LatLng a, LatLng b) {
    final dLat = (b.latitude - a.latitude) * 111320;
    final dLng = (b.longitude - a.longitude) *
        111320 *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt(dLat * dLat + dLng * dLng);
  }
}

/// Prépare l'union exacte de la session pour l'export KML, en isolate.
///
/// Exécuté dans un isolate séparé (`Isolate.run`) pour ne jamais
/// bloquer l'UI pendant l'union clipper2 (sweep de Vatti) sur de
/// longues trajectoires.
Future<List<(List<LatLng>, List<List<LatLng>>)>> computeCoverageIslands(
  TrackingSession session,
) {
  return Isolate.run(() => _coverageIslandsSync(session));
}

/// Union synchrone (exécutée dans l'isolate) : capsules → îles + trous.
List<(List<LatLng>, List<List<LatLng>>)> _coverageIslandsSync(
  TrackingSession session,
) {
  if (session.samples.isEmpty) return const [];
  final engine = CoverageEngine();
  final proj = LocalProjection(session.samples.first);
  final local = [for (final p in session.samples) proj.project(p)];
  final capsules =
      engine.buildBrushSegmentsLocal(local, session.brushRadiusMeters);
  final islands = unionWithHoles(capsules);
  return [
    for (final island in islands)
      (
        [for (final p in island.outer) proj.unproject(p)],
        [
          for (final hole in island.holes)
            [for (final p in hole) proj.unproject(p)]
        ]
      ),
  ];
}
