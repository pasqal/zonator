/// Paramètres utilisateur de l'application, persistés localement
/// (via `shared_preferences`) et éditables dans l'écran « Paramètres ».
class AppSettings {
  /// Rayon du « pinceau géant » en mètres (ex. 5, 10, 25).
  final double brushRadiusMeters;

  /// Liste des états possibles pour un signalement.
  ///
  /// Valeur par défaut : `['Suspicion de défaut']`.
  final List<String> states;

  /// Adresse email de destination des exports KML.
  final String email;

  const AppSettings({
    this.brushRadiusMeters = 10,
    this.states = const ['Suspicion de défaut'],
    this.email = '',
  });

  /// Retourne une copie avec les champs modifiés.
  AppSettings copyWith({
    double? brushRadiusMeters,
    List<String>? states,
    String? email,
  }) =>
      AppSettings(
        brushRadiusMeters: brushRadiusMeters ?? this.brushRadiusMeters,
        states: states ?? this.states,
        email: email ?? this.email,
      );
}
