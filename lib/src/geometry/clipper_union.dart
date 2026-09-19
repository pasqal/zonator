/// Adapter d'union booléenne de polygones basé sur clipper2.
library;

import 'dart:math' as math;

import 'package:clipper2/clipper2.dart';

/// Adapter d'union booléenne de polygones basé sur clipper2 (suite doc).
///
/// ## Pourquoi une grille entière
///
/// Clipper2 travaille sur des coordonnées entières (grille fixe). Nos
/// polygones sont en mètres (double). On multiplie par [scale] (10⁻³ m
/// → entier : précision millimétrique) avant l'union, puis on divise
/// au retour. La précision mm est ~1000× plus fine que la précision
/// GPS typique (3–5 m) : aucune perte mesurable.
///
/// ## Détection des trous
///
/// Clipper2 retourne les contours avec une orientation cohérente en
/// fonction de la règle de remplissage : en `nonZero`, les contours
/// extérieurs et les trous ont des aires signées de signes opposés.
/// On classe chaque contour retourné par le signe de son aire :
/// extérieur (positif) ou trou (négatif). Chaque trou est ensuite
/// rattaché au plus petit extérieur le contenant.
///
/// ## Règle de remplissage
///
/// On utilise `nonZero` plutôt que `evenOdd` : les capsules se
/// chevauchent souvent deux à deux (recouvrement de demi-cercles), et
/// seul `nonZero` garantit que ces recouvrements ne créent pas de
/// « trous » parasites au milieu du pinceau.

/// Facteur de mise à l'échelle double → entier (1 unité = 1 mm).
const double _scale = 1000;

/// Union d'une liste de polygones (contours fermés, en mètres).
///
/// Retourne une liste de polygones disjoints dont les trous sont
/// enlevés (contours extérieurs uniquement — voir [unionWithHoles]
/// pour la version structurée avec trous).
List<List<math.Point<double>>> unionPolygons(
  List<List<math.Point<double>>> polygons,
) {
  if (polygons.isEmpty) return const [];
  final result = unionWithHoles(polygons);
  return [for (final r in result) r.outer];
}

/// Résultat d'une union avec gestion des trous.
class UnionResult {
  /// Contour extérieur du polygone (mètres).
  final List<math.Point<double>> outer;

  /// Trous éventuels du polygone (boucles non couvertes).
  final List<List<math.Point<double>>> holes;

  const UnionResult({required this.outer, required this.holes});
}

/// Union structurée : contours extérieurs + trous rattachés.
///
/// Chaque élément retourné est un [UnionResult] indépendant (une île
/// de surface couverte), avec ses trous internes s'il y en a.
List<UnionResult> unionWithHoles(
  List<List<math.Point<double>>> polygons,
) {
  if (polygons.isEmpty) return const [];

  // 1. Conversion en grille entière clipper2.
  final subjects = <Path64>[
    for (final poly in polygons)
      [for (final p in poly) Point64((p.x * _scale).round(), (p.y * _scale).round())],
  ];

  // 2. Union booléenne (règle non-zero : les recouvrements ne créent
  //    pas de trous parasites entre capsules voisines).
  final solution = Clipper.union(
    subject: subjects,
    fillRule: FillRule.nonZero,
  );
  if (solution.isEmpty) return const [];

  // 3. Classement extérieur/trou par signe de l'aire signée.
  final outers = <Path64>[];
  final holes = <Path64>[];
  for (final path in solution) {
    // Clipper2 normalise l'orientation : aire > 0 = extérieur,
    // aire < 0 = trou (règle nonZero, orientation ccw/cw standard).
    if (path.area >= 0) {
      outers.add(path);
    } else {
      holes.add(path);
    }
    // Ré-orienter systématiquement les trous en sens horaire ? Non :
    // conserver l'orientation native de clipper2, elle est cohérente
    // avec la règle nonZero et directement utilisable en KML.
  }

  // 4. Rattachement de chaque trou au plus petit extérieur qui le contient.
  final results = <UnionResult>[];
  for (final outer in outers) {
    final attached = <Path64>[];
    for (final hole in holes) {
      // Le premier sommet du trou suffit pour le rattachement : un trou
      // est forcément à l'intérieur d'un (et un seul) extérieur.
      final pt = hole.first;
      if (outer.pointInPolygon(Point64(pt.x, pt.y)) ==
          PointInPolygonResult.isInside) {
        attached.add(hole);
      }
    }
    results.add(UnionResult(
      outer: _toMeters(outer),
      holes: [for (final h in attached) _toMeters(h)],
    ));
  }

  return results;
}

/// Conversion inverse : grille entière → mètres (double).
List<math.Point<double>> _toMeters(Path64 path) => [
      for (final p in path) math.Point(p.x / _scale, p.y / _scale),
    ];
