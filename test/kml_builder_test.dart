import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'package:zone_coverage/src/export/kml_builder.dart';
import 'package:zone_coverage/src/models/session.dart';

void main() {
  group('KmlBuilder', () {
    final builder = const KmlBuilder();

    final islands = <(List<LatLng>, List<List<LatLng>>)>[
      (
        [
          const LatLng(48.0, 2.0),
          const LatLng(48.0001, 2.0),
          const LatLng(48.0001, 2.0001),
          const LatLng(48.0, 2.0001),
        ],
        [
          // Un trou (boucle non couverte).
          [
            const LatLng(48.00002, 2.00002),
            const LatLng(48.00008, 2.00002),
            const LatLng(48.00005, 2.00007),
          ],
        ],
      ),
    ];

    final pois = [
      Poi(
        id: 'poi-1',
        position: const LatLng(48.00005, 2.00005),
        state: 'Suspicion de défaut',
        comment: 'Fissure visible sur la canalisation',
        timestamp: DateTime.utc(2026, 1, 15, 10, 30),
      ),
    ];

    late String kml;
    late XmlDocument doc;

    setUpAll(() {
      kml = builder.build(coverageIslands: islands, pois: pois);
      doc = XmlDocument.parse(kml);
    });

    test('le document XML est bien formé et parsable', () {
      expect(doc.rootElement.name.toString(), 'kml');
      expect(
        doc.rootElement.getAttribute('xmlns'),
        'http://www.opengis.net/kml/2.2',
      );
    });

    test('contient exactement un placemark zone + un placemark POI', () {
      final placemarks = doc.findAllElements('Placemark').toList();
      expect(placemarks.length, 2);
      expect(
        placemarks.first.findElements('name').first.innerText,
        'Zone couverte',
      );
      expect(
        placemarks.last.findElements('name').first.innerText,
        'Suspicion de défaut',
      );
    });

    test('le polygon de zone contient outer + inner boundaries', () {
      final polygon = doc.findAllElements('Polygon').first;
      expect(polygon.findElements('outerBoundaryIs'), isNotEmpty);
      expect(polygon.findElements('innerBoundaryIs').length, 1);
      final coords =
          polygon.findAllElements('coordinates').map((e) => e.innerText).toList();
      expect(coords.length, 2);
      // Format lon,lat,alt — chaque ligne contient 3 composantes.
      final firstLine = coords.first.split('\n').first;
      expect(firstLine.split(',').length, 3);
    });

    test('les couleurs KML sont au format aabbggrr', () {
      final polyStyle = doc
          .findAllElements('Style')
          .firstWhere((e) => e.getAttribute('id') == 'coverageStyle')
          .findElements('PolyStyle')
          .first;
      final color = polyStyle.findElements('color').first.innerText;
      expect(color.length, 8);
      expect(RegExp(r'^[0-9A-F]{8}$').hasMatch(color), isTrue);
      // 0x662196F3 ARGB → aabbggrr = 66F39621.
      expect(color, '66F39621');
    });

    test('le POI contient les métadonnées structurées', () {
      final data = doc.findAllElements('Data').toList();
      final names = data.map((e) => e.getAttribute('name')).toList();
      expect(names, containsAll(['etat', 'commentaire', 'horodatage']));
      final etat = data.firstWhere((e) => e.getAttribute('name') == 'etat');
      expect(etat.findElements('value').first.innerText,
          'Suspicion de défaut');
    });

    test('le POI exporte ses coordonnées au format Point', () {
      final point = doc.findAllElements('Point').first;
      final coords = point.findElements('coordinates').first.innerText;
      expect(coords, startsWith('2.00005'));
      expect(coords.split(',').length, 3);
    });
  });
}
