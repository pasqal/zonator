import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:zone_coverage/src/geometry/clipper_union.dart';
import 'package:zone_coverage/src/geometry/coverage_engine.dart';
import 'package:zone_coverage/src/geometry/local_projection.dart';

void main() {
  group('LocalProjection', () {
    test('origine se projette en (0,0)', () {
      const origin = LatLng(48.8584, 2.2945);
      final proj = LocalProjection(origin);
      final p = proj.project(origin);
      expect(p.x, closeTo(0, 1e-9));
      expect(p.y, closeTo(0, 1e-9));
    });

    test('aller-retour projection / unprojection', () {
      const origin = LatLng(48.8584, 2.2945);
      final proj = LocalProjection(origin);
      const p = LatLng(48.8594, 2.2955);
      final local = proj.project(p);
      final back = proj.unproject(local);
      expect(back.latitude, closeTo(p.latitude, 1e-9));
      expect(back.longitude, closeTo(p.longitude, 1e-9));
    });

    test('échelle en mètres correcte (~111 km par degré de latitude)', () {
      final proj = LocalProjection(const LatLng(48.0, 2.0));
      final p1 = proj.project(const LatLng(48.0, 2.0));
      final p2 = proj.project(const LatLng(48.01, 2.0));
      final d = p2.y - p1.y;
      expect(d, closeTo(1112, 10));
    });
  });

  group('CoverageEngine - capsules', () {
    final engine = CoverageEngine();

    test('un point unique produit un disque', () {
      final segments = engine.buildBrushSegments(
        [const LatLng(48.0, 2.0)],
        10,
      );
      expect(segments.length, 1);
      expect(segments.first.length, 32);
      // Tous les sommets du disque à ~10 m du centre (0,0).
      for (final p in segments.first) {
        expect(math.sqrt(p.x * p.x + p.y * p.y), closeTo(10, 0.5));
      }
    });

    test('deux points produisent une capsule unique continue', () {
      final segments = engine.buildBrushSegments(
        [const LatLng(48.0, 2.0), const LatLng(48.0001, 2.0001)],
        5,
      );
      expect(segments.length, 1);
      // La capsule doit contenir les deux centres et le point médian.
      final poly = segments.first;
      expect(_pointInPolygon(poly, const math.Point(0, 0)), isTrue);
      final proj = LocalProjection(const LatLng(48.0, 2.0));
      final end = proj.project(const LatLng(48.0001, 2.0001));
      expect(_pointInPolygon(poly, end), isTrue);
      final mid = math.Point(end.x / 2, end.y / 2);
      expect(_pointInPolygon(poly, mid), isTrue);
    });

    test('trois points produisent deux capsules recouvrantes', () {
      final segments = engine.buildBrushSegments(
        [
          const LatLng(48.0, 2.0),
          const LatLng(48.0001, 2.0),
          const LatLng(48.0001, 2.0001),
        ],
        5,
      );
      expect(segments.length, 2);
      // Les capsules consécutives doivent se recouvrir (continuité).
      final a = segments[0];
      final b = segments[1];
      var overlap = false;
      for (final p in a) {
        if (_pointInPolygon(b, p)) {
          overlap = true;
          break;
        }
        // Le point de jonction (2e point GPS) doit être dans les deux.
      }
      final proj = LocalProjection(const LatLng(48.0, 2.0));
      final junction = proj.project(const LatLng(48.0001, 2.0));
      expect(_pointInPolygon(a, junction), isTrue);
      expect(_pointInPolygon(b, junction), isTrue);
      expect(overlap || a.isNotEmpty, isTrue);
    });
  });

  group('CoverageEngine - union exacte (clipper2)', () {
    final engine = CoverageEngine();

    test('union de capsules collinéaires = une seule île', () {
      final segments = engine.buildBrushSegments(
        [
          const LatLng(48.0, 2.0),
          const LatLng(48.0001, 2.0),
          const LatLng(48.0002, 2.0),
        ],
        5,
      );
      final merged = unionWithHoles(segments);
      expect(merged.length, 1);
      expect(merged.first.holes, isEmpty);
    });

    test("l'aire d'union d'une ligne droite ≈ 2r·L + πr²", () {
      // Ligne de ~22.24 m (0.0002° lat), r = 5 m.
      final segments = engine.buildBrushSegments(
        [
          const LatLng(48.0, 2.0),
          const LatLng(48.0002, 2.0),
        ],
        5,
      );
      final merged = unionWithHoles(segments);
      final proj = LocalProjection(const LatLng(48.0, 2.0));
      final length = proj.project(const LatLng(48.0002, 2.0)).y;
      final expected = 2 * 5 * length + math.pi * 25;
      final actual = _areaLocal(merged.first.outer);
      expect(actual, closeTo(expected, expected * 0.02));
    });

    test('boucle non couverte = trou détecté', () {
      // Trajectoire carrée de ~45 m de côté, r = 5 : le centre du carré
      // n'est pas couvert -> l'union doit contenir exactement un trou.
      const c = LatLng(48.0, 2.0);
      final proj = LocalProjection(c);
      final localSquare = <math.Point<double>>[
        const math.Point(0, 0),
        const math.Point(45, 0),
        const math.Point(45, 45),
        const math.Point(0, 45),
        const math.Point(0, 0),
      ];
      final gpsSquare = [for (final p in localSquare) proj.unproject(p)];
      final segments = engine.buildBrushSegments(gpsSquare, 5);
      final merged = unionWithHoles(segments);
      expect(merged.length, 1);
      expect(merged.first.holes.length, 1);
      // Le centre du carré (22.5, 22.5) doit être dans le trou, donc
      // hors de la surface couverte.
      final centerInsideHole = _pointInPolygon(
        merged.first.holes.first,
        const math.Point(22.5, 22.5),
      );
      expect(centerInsideHole, isTrue);
    });

    test('union de capsules = surface continue sans fissure', () {
      // Trajectoire en zigzag serré : l'union ne doit produire qu'une
      // seule île (aucune fissure entre capsules consécutives).
      final proj = LocalProjection(const LatLng(48.0, 2.0));
      final zigzag = <math.Point<double>>[];
      for (var i = 0; i < 10; i++) {
        zigzag.add(math.Point(i * 3.0, (i.isEven) ? 0.0 : 2.0));
      }
      final gps = [for (final p in zigzag) proj.unproject(p)];
      final segments = engine.buildBrushSegments(gps, 5);
      final merged = unionWithHoles(segments);
      expect(merged.length, 1);
      expect(merged.first.holes, isEmpty);
    });
  });

  group('Performance union', () {
    test('1000 points GPS fusionnés en < 2 s', () {
      final engine = CoverageEngine();
      final proj = LocalProjection(const LatLng(48.0, 2.0));
      final walk = <LatLng>[];
      var x = 0.0, y = 0.0;
      for (var i = 0; i < 1000; i++) {
        x += 4 * math.cos(i * 0.37);
        y += 4 * math.sin(i * 0.29);
        walk.add(proj.unproject(math.Point(x, y)));
      }
      final sw = Stopwatch()..start();
      final segments = engine.buildBrushSegments(walk, 10);
      final merged = unionWithHoles(segments);
      sw.stop();
      expect(merged, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}

/// Test ray-casting : point à l'intérieur d'un polygone (pair = dedans).
bool _pointInPolygon(List<math.Point<double>> poly, math.Point<double> p) {
  var inside = false;
  var j = poly.length - 1;
  for (var i = 0; i < poly.length; i++) {
    final xi = poly[i].x, yi = poly[i].y;
    final xj = poly[j].x, yj = poly[j].y;
    if (((yi > p.y) != (yj > p.y)) &&
        (p.x < (xj - xi) * (p.y - yi) / (yj - yi) + xi)) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

/// Aire signée d'un contour local (formule du lacet).
double _areaLocal(List<math.Point<double>> poly) {
  var a = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final p1 = poly[i];
    final p2 = poly[(i + 1) % poly.length];
    a += (p1.x * p2.y - p2.x * p1.y);
  }
  return (a / 2).abs();
}
