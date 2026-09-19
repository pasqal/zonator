import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Projection plane locale autour d'un point d'origine.
///
/// Pour dessiner une surface continue (union de disques) et exporter un
/// polygone géométriquement exact, on ne peut pas travailler directement
/// en lat/long (degrés) : un « cercle » y serait une ellipse déformée et
/// l'union de polygones produirait des artefacts. On projette donc les
/// points GPS dans un plan euclidien local (en mètres) via une
/// approximation équirectangulaire corrigée par le cosinus de la
/// latitude d'origine — précision très largement suffisante pour des
/// rayons de 5 à 50 m sur quelques kilomètres (erreur relative
/// < 10⁻⁸ à latitude 45° pour 1 km de extension).
///
/// L'origine est le premier point GPS de la session : il se projette en
/// (0, 0). Tous les calculs (capsules, union clipper2, aire) se font
/// ensuite en mètres dans ce plan, puis les sommets du polygone final
/// sont re-projetés en lat/long pour l'affichage et l'export KML.
class LocalProjection {
  /// Point GPS d'origine de la projection (premier point de la session).
  final LatLng origin;

  /// Rayon terrestre moyen, en mètres (WGS84).
  static const double _earthRadius = 6378137;

  /// Facteur de conversion degrés -> radians.
  static const double _deg2rad = math.pi / 180;

  /// Mètres par degré de latitude (constant au voisinage de l'origine).
  late final double _metersPerDegLat = _deg2rad * _earthRadius;

  /// Mètres par degré de longitude (dépend de la latitude d'origine).
  late final double _metersPerDegLng =
      _deg2rad * _earthRadius * math.cos(origin.latitude * _deg2rad);

  LocalProjection(this.origin);

  /// Projette une position GPS en coordonnées locales (mètres).
  ///
  /// `x` croît vers l'Est, `y` croît vers le Nord ; l'origine (premier
  /// point de session) se projette en (0, 0).
  math.Point<double> project(LatLng p) => math.Point(
        (p.longitude - origin.longitude) * _metersPerDegLng,
        (p.latitude - origin.latitude) * _metersPerDegLat,
      );

  /// Projection inverse : coordonnées locales (mètres) vers GPS.
  LatLng unproject(math.Point<double> p) => LatLng(
        origin.latitude + p.y / _metersPerDegLat,
        origin.longitude + p.x / _metersPerDegLng,
      );
}
