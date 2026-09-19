import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'clipper_union.dart';
import 'local_projection.dart';

/// Génère les polygones de la « surface couverte » (pinceau géant).
///
/// ## Principe
///
/// Chaque segment de trajectoire est converti en **capsule** : deux
/// demi-cercles (aux extrémités du segment) reliés par deux segments
/// tangents. Une capsule est donc le lieu des points à distance <= r
/// du segment — c'est exactement l'union du disque de départ, du disque
/// d'arrivée et du rectangle de longueur d et largeur 2r entre les deux.
///
/// La surface couverte par la session est l'**union de toutes les
/// capsules**, enchaînées bout à bout : elle est continue par
/// construction, sans trous, même à basse vitesse et dans les virages
/// serrés (chaque capsule inclut les disques de jonction).
///
/// ## Deux rendus, deux budgets de performance
///
/// 1. **Rendu temps réel** (`buildBrushSegments`) : chaque capsule est
///    émise comme un polygone à part dans la liste retournée. Comme les
///    capsules se chevauchent fortement entre voisines, le rendu opaque
///    (sans transparence) de leur union visuelle est **identique** à
///    l'union géométrique — mais son coût est O(k) par point GPS (k =
///    nombre de sommets d'un demi-cercle), sans aucun recalcul global.
///    C'est la clé de la fluidité : pas de re-union du monde entier à
///    chaque fix GPS.
///
/// 2. **Union exacte à l'export** (`mergeSegments`) : les capsules sont
///    fusionnées par un booléen d'union (clipper2, algorithme Vatti de
///    balayage) en un ensemble de polygones disjoints avec trous, une
///    seule fois, au moment du « Stop » → export KML. Le résultat est un
///    (ou plusieurs) contour(s) propre(s) sans auto-intersections.
///
/// ## Résolution du cercle
///
/// Les demi-cercles sont discrétisés en [circleSegments] facettes — 32
/// par défaut. À 10 m de rayon, l'erreur de corde est
/// r·(1 − cos(π/32)) ≈ 4.8 cm : invisible à l'écran et négligeable
/// pour le calcul de surface. Réduire à 16 pour des cibles très lentes,
/// augmenter à 64 pour un export très fin.
class CoverageEngine {
  /// Nombre de facettes par cercle complet (demi-cercles : la moitié).
  final int circleSegments;

  /// Angle maximal entre deux sommets consécutifs du cercle (radians).
  late final double _step = 2 * math.pi / circleSegments;

  CoverageEngine({this.circleSegments = 32});

  /// Génère les capsules (une par segment de trajectoire) en local (mètres).
  ///
  /// [points] sont les positions GPS échantillonnées ; la projection
  /// locale est créée sur le premier point. Retourne une liste de
  /// polygones (chaque polygone = contour de capsule), où les capsules
  /// consécutives se recouvrent pour former une surface continue.
  ///
  /// Complexité : O(n·k) pour n points et k facettes — linéaire en le
  /// nombre de points GPS, sans allocation géométrique globale.
  List<List<math.Point<double>>> buildBrushSegments(
    List<LatLng> points,
    double radiusMeters,
  ) {
    if (points.isEmpty) return const [];
    final proj = LocalProjection(points.first);
    final local = [for (final p in points) proj.project(p)];
    return buildBrushSegmentsLocal(local, radiusMeters);
  }

  /// Variante purement locale : [points] déjà projetés en mètres.
  List<List<math.Point<double>>> buildBrushSegmentsLocal(
    List<math.Point<double>> points,
    double radiusMeters,
  ) {
    if (points.isEmpty) return const [];
    if (points.length == 1) {
      return [_disk(points.first, radiusMeters)];
    }
    final segments = <List<math.Point<double>>>[];
    for (var i = 0; i + 1 < points.length; i++) {
      segments.add(_capsule(points[i], points[i + 1], radiusMeters));
    }
    return segments;
  }

  /// Union exacte des capsules en un ensemble de polygones disjoints.
  ///
  /// Délègue à clipper2 (voir `clipper_union.dart`). Appelé une seule
  /// fois, au « Stop » → export KML ; le coût est amorti et ne se
  /// produit jamais pendant le tracé temps réel.
  ///
  /// Retourne une liste de polygones en coordonnées locales (mètres).
  List<List<math.Point<double>>> mergeSegments(
    List<List<math.Point<double>>> segments,
  ) {
    return unionPolygons(segments);
  }

  /// Contour complet d'un disque (approximation polygonale).
  List<math.Point<double>> _disk(
    math.Point<double> center,
    double radius,
  ) {
    final pts = <math.Point<double>>[];
    for (var i = 0; i < circleSegments; i++) {
      final a = i * _step;
      pts.add(math.Point(center.x + radius * math.cos(a),
          center.y + radius * math.sin(a)));
    }
    return pts;
  }

  /// Contour d'une capsule reliant [a] et [b] (local, mètres).
  ///
  /// La capsule est tracée comme un contour fermé unique : côté
  /// gauche du rectangle central, demi-cercle autour de `b` (de
  /// l'angle θ+π/2 vers θ-π/2 en passant par l'avant), côté droit,
  /// demi-cercle autour de `a`. θ est l'angle du segment a→b.
  List<math.Point<double>> _capsule(
    math.Point<double> a,
    math.Point<double> b,
    double radius,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-9) return _disk(a, radius);

    final theta = math.atan2(dy, dx);
    final half = circleSegments ~/ 2;

    final pts = <math.Point<double>>[];
    for (var i = 0; i <= half; i++) {
      // Demi-cercle arrière autour de a : angles [θ+π/2, θ+3π/2] en
      // passant par l'arrière du segment (θ+π).
      final ang = theta + math.pi / 2 + i * _step;
      pts.add(math.Point(
        a.x + radius * math.cos(ang),
        a.y + radius * math.sin(ang),
      ));
    }
    for (var i = 0; i <= half; i++) {
      // Demi-cercle avant autour de b : angles [θ-π/2, θ+π/2] en
      // passant par l'avant du segment (θ).
      final ang = theta - math.pi / 2 + i * _step;
      pts.add(math.Point(
        b.x + radius * math.cos(ang),
        b.y + radius * math.sin(ang),
      ));
    }
    return pts;
  }
}
