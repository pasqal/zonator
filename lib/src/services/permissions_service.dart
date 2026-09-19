import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Gestion centralisée des permissions (localisation, stockage).
///
/// - **Localisation** : demandée au démarrage du tracking via geolocator
///   (Android/iOS) et permission_handler (vérification croisée,
///   redirection vers les réglages si refus définitif).
/// - **Stockage** : utile sur Windows uniquement pour écrire le KML
///   hors du sandbox applicatif ; sur Android 10+ et iOS, l'écriture
///   dans les répertoires applicatifs ne requiert aucune permission.
///
/// Windows : `geolocator_windows` gère la localisation (service
/// Windows.Devices.Geolocation) ; `permission_handler_windows` n'expose
/// pas de permission de localisation — la première demande de position
/// déclenche l'invite système Windows.
class PermissionsService {
  /// Vérifie puis demande la permission de localisation.
  ///
  /// Retourne `null` si accordée, sinon un message d'erreur explicatif
  /// (pour affichage UI). Tente d'ouvrir les réglages si refus permanent.
  Future<String?> ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Le service de localisation est désactivé. '
          'Activez le GPS dans les réglages du système.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        return 'Permission de localisation refusée.';
      case LocationPermission.deniedForever:
        await Geolocator.openAppSettings();
        return 'Permission de localisation refusée définitivement. '
            'Les réglages de l\u2019application ont été ouverts.';
      case LocationPermission.unableToDetermine:
        return 'État de la permission de localisation indéterminé.';
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return null;
    }
  }

  /// Vérifie/demande la permission de stockage pertinente selon la
  /// plateforme. Retourne `null` si OK, sinon un message d'erreur.
  ///
  /// - Android < 10 : `Permission.storage` (legacy).
  /// - Android 10+ : rien (scoped storage, répertoires applicatifs).
  /// - iOS : rien.
  /// - Windows : rien (écriture dans les répertoires utilisateur).
  Future<String?> ensureStoragePermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final sdk = await _androidSdkLevel();
      if (sdk != null && sdk < 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          return 'Permission de stockage refusée : l\u2019export KML '
              'impossible.';
        }
      }
    }
    return null;
  }

  /// Niveau SDK Android (méthode best-effort ; null si indéterminé).
  Future<int?> _androidSdkLevel() async {
    try {
      final build = await Process.run('getprop', ['ro.build.version.sdk']);
      final v = int.tryParse((build.stdout as String).trim());
      return v;
    } catch (_) {
      return null;
    }
  }
}
