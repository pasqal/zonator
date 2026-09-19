import 'package:latlong2/latlong.dart';

/// Point d'intérêt géolocalisé créé via le bouton « Signaler ».
///
/// Chaque POI est associé à la session de tracé en cours et possède un
/// état (ex. « Suspicion de défaut ») et un commentaire optionnel.
class Poi {
  /// Identifiant unique du POI.
  final String id;

  /// Position GPS du POI.
  final LatLng position;

  /// État sélectionné par l'utilisateur (ex. « Suspicion de défaut »).
  final String state;

  /// Commentaire libre saisi par l'utilisateur.
  final String comment;

  /// Date et heure de création du POI (UTC).
  final DateTime timestamp;

  const Poi({
    required this.id,
    required this.position,
    required this.state,
    required this.comment,
    required this.timestamp,
  });
}

/// Session de collecte figée au moment du « Stop ».
///
/// `samples` contient les positions GPS brutes échantillonnées pendant
/// l'enregistrement : elles servent à reconstruire la surface couverte
/// et à l'export KML. Les listes sont figées (non modifiables) ; la
/// construction progressive est gérée par le contrôleur de session
/// (voir `RecordingSession`), qui assemble cet objet en fin de tracé.
class TrackingSession {
  /// Identifiant unique de la session.
  final String id;

  /// Date et heure de début de la session (UTC).
  final DateTime startedAt;

  /// Rayon du « pinceau géant » en mètres utilisé pendant la session.
  final double brushRadiusMeters;

  /// Positions GPS enregistrées pendant la session.
  final List<LatLng> samples;

  /// Points d'intérêt signalés pendant la session.
  final List<Poi> pois;

  const TrackingSession({
    required this.id,
    required this.startedAt,
    required this.brushRadiusMeters,
    this.samples = const [],
    this.pois = const [],
  });
}

/// Session en cours d'enregistrement, à usage interne du contrôleur.
///
/// Contrairement à [TrackingSession], les listes sont mutables et
/// l'ajout d'un échantillon se fait en O(1) (ajout en fin de liste),
/// ce qui est indispensable pour absorber un flux GPS à 1 Hz pendant
/// plusieurs heures sans dégrader l'interface.
class RecordingSession {
  /// Identifiant unique de la session.
  final String id;

  /// Date et heure de début de la session (UTC).
  final DateTime startedAt;

  /// Rayon du « pinceau géant » en mètres choisi au démarrage.
  final double brushRadiusMeters;

  /// Positions GPS enregistrées (mutable, ajout en O(1)).
  final List<LatLng> samples = [];

  /// Points d'intérêt signalés (mutable).
  final List<Poi> pois = [];

  RecordingSession({
    required this.id,
    required this.startedAt,
    required this.brushRadiusMeters,
  });

  /// Ajoute un échantillon de position en fin de liste (O(1)).
  void addSample(LatLng position) => samples.add(position);

  /// Ajoute un POI signalé.
  void addPoi(Poi poi) => pois.add(poi);

  /// Fige la session en un [TrackingSession] immuable (au « Stop »).
  TrackingSession freeze() => TrackingSession(
        id: id,
        startedAt: startedAt,
        brushRadiusMeters: brushRadiusMeters,
        samples: List.unmodifiable(samples),
        pois: List.unmodifiable(pois),
      );
}
