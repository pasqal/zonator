import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Service de persistance des paramètres (shared_preferences).
///
/// Les états personnalisés sont stockés en JSON dans une seule clé.
class SettingsService {
  static const _keyRadius = 'settings.brushRadius';
  static const _keyStates = 'settings.states';
  static const _keyEmail = 'settings.email';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  /// Charge les paramètres ; valeurs par défaut si absents.
  AppSettings load() {
    final radius = _prefs.getDouble(_keyRadius) ?? 10;
    final email = _prefs.getString(_keyEmail) ?? '';
    List<String> states = const ['Suspicion de défaut'];
    final raw = _prefs.getString(_keyStates);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        if (list.isNotEmpty) states = list;
      } catch (_) {
        // JSON corrompu : garder la valeur par défaut.
      }
    }
    return AppSettings(
      brushRadiusMeters: radius,
      states: states,
      email: email,
    );
  }

  /// Sauvegarde les paramètres.
  Future<void> save(AppSettings settings) async {
    await _prefs.setDouble(_keyRadius, settings.brushRadiusMeters);
    await _prefs.setString(_keyStates, jsonEncode(settings.states));
    await _prefs.setString(_keyEmail, settings.email);
  }
}
