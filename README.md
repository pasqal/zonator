# zone_coverage

Application Flutter de collecte de données GPS et de visualisation de
zone couverte (« pinceau géant »), fonctionnant hors ligne sur
**Android, iOS et Windows**.

## Fonctionnalités

- **Offline-first** : fond de plan téléchargeable au premier lancement
  (tuiles stockées localement), puis fonctionnement entièrement hors
  ligne.
- **Pinceau géant** : pendant l'enregistrement, une surface circulaire
  (rayon configurable : 5/10/25/50 m) est dessinée en temps réel autour
  de la position. Le rendu est une union de **capsules** (disques +
  rectangles tangents) : surface continue, sans trous, même à basse
  vitesse et dans les virages serrés.
- **Signalements (POI)** : pendant l'enregistrement, bouton « Signaler »
  pour attacher un état (ex. « Suspicion de défaut ») et un commentaire
  à la position courante.
- **Export KML** : au « Stop », la zone couverte est fusionnée en un
  polygone unique (union booléenne exacte, trous détectés) et exportée
  en KML (Google Earth / SIG) avec les POI en Placemarks, puis partagée
  nativement (email).

## Performance

- Rendu temps réel **incrémental** : une capsule par point GPS accepté
  (O(k) par fix, aucun recalcul global) ; notifications UI throttlées.
- Union exacte **en isolate** au moment de l'export : l'UI n'est jamais
  bloquée, même sur de longues trajectoires (test : 1000 points en < 2 s).
- Précision géométrique : projection locale métrique (erreur relative
  < 10⁻⁸ à latitude 45° pour 1 km), grille clipper2 au millimètre.

## Structure du projet

```
lib/
  main.dart                          # Point d'entrée, injection des services
  src/
    models/
      app_settings.dart              # Paramètres (rayon, états, email)
      session.dart                   # Session de tracking, POI
    geometry/
      local_projection.dart          # Projection locale métrique (lat/long ↔ m)
      coverage_engine.dart           # Capsules du pinceau géant (cœur du rendu)
      clipper_union.dart              # Union booléenne exacte (clipper2)
    controllers/
      tracking_controller.dart       # Flux GPS, échantillonnage, rendu incrémental
    services/
      offline_map_service.dart       # Téléchargement/lecture des tuiles offline
      permissions_service.dart        # Permissions location / stockage
      settings_service.dart          # Persistance des paramètres
    export/
      kml_builder.dart               # Génération KML (styles, polygon, POI)
    ui/
      home_screen.dart               # Écran principal (Commencer/Stop, Signaler)
      map_screen.dart                # Carte flutter_map + pinceau temps réel
      settings_screen.dart           # Paramètres
      offline_download_screen.dart   # Téléchargement du fond de plan
test/
  coverage_engine_test.dart          # Géométrie, union, trous, performance
  kml_builder_test.dart               # Validité XML/KML, styles, POI
  widget_test.dart                   # Modèles
```

## Lancer

```bash
flutter pub get
flutter run                    # device connecté
flutter test                   # tests unitaires
```

## Permissions

- **Android** : `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
  `FOREGROUND_SERVICE_LOCATION` (manifest configuré), `INTERNET`
  (téléchargement initial uniquement).
- **iOS** : `NSLocationWhenInUseUsageDescription` (Info.plist configuré).
- **Windows** : invite système de localisation au premier accès.

## Notes licence

Les tuiles OpenStreetMap sont soumises à la politique d'utilisation
d'OSM (attribution requise, usage léger). Pour un usage professionnel,
remplacer l'URL du fond de plan par un fournisseur adapté (IGN,
MapTiler…) dans `offline_map_service.dart`.
