import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../models/session.dart';

/// Générateur de fichier KML (Keyhole Markup Language) pour Google Earth
/// et les SIG.
///
/// Structure produite :
///
/// ```xml
/// <Document>
///   <name>…</name>
///   <Style id="coverageStyle">…</Style>      <!-- zone couverte -->
///   <Style id="poiStyle">…</Style>           <!-- marqueurs POI -->
///   <Placemark>                               <!-- zone couverte -->
///     <name>Zone couverte</name>
///     <styleUrl>#coverageStyle</styleUrl>
///     <MultiGeometry>
///       <Polygon><outerBoundaryIs>…</outerBoundaryIs>
///         <innerBoundaryIs>…</innerBoundaryIs></Polygon>…
///     </MultiGeometry>
///   </Placemark>
///   <Placemark>…</Placemark>                  <!-- un par POI -->
/// </Document>
/// ```
///
/// La zone couverte est exportée en `MultiGeometry` de `Polygon` : un
/// `Polygon` par île de couverture, chaque île pouvant contenir des
/// `innerBoundaryIs` (trous = boucles non couvertes). Les couleurs KML
/// sont en `aabbggrr` (alpha-bleu-vert-rouge, l'ordre du format est
/// inversé par rapport à Flutter).
class KmlBuilder {
  /// Nom du document KML.
  final String documentName;

  /// Couleur de remplissage de la zone couverte (ARGB Flutter).
  final int coverageFillColor;

  /// Couleur de contour de la zone couverte (ARGB Flutter).
  final int coverageBorderColor;

  /// Couleur de remplissage des marqueurs POI (ARGB Flutter).
  final int poiColor;

  const KmlBuilder({
    this.documentName = 'Zone couverte',
    this.coverageFillColor = 0x662196F3,
    this.coverageBorderColor = 0xFF2196F3,
    this.poiColor = 0xFFF44336,
  });

  /// Génère le KML complet de la session.
  ///
  /// [coverageIslands] : îles de couverture ; chaque île est une paire
  /// (extérieur, trous) en lat/long. [pois] : signalements à exporter.
  String build({
    required List<(List<LatLng>, List<List<LatLng>>)> coverageIslands,
    required List<Poi> pois,
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('kml', nest: () {
      builder.attribute('xmlns', 'http://www.opengis.net/kml/2.2');
      builder.element('Document', nest: () {
        builder.element('name', nest: documentName);

        // ── Styles ──────────────────────────────────────────────
        _writeStyle(
          builder,
          id: 'coverageStyle',
          fillColor: coverageFillColor,
          lineColor: coverageBorderColor,
          lineWidth: 2,
        );
        _writeStyle(
          builder,
          id: 'poiStyle',
          fillColor: poiColor,
          lineColor: poiColor,
          lineWidth: 1,
          iconScale: 1.2,
        );

        // ── Placemark : zone couverte ───────────────────────────
        if (coverageIslands.isNotEmpty) {
          builder.element('Placemark', nest: () {
            builder.element('name', nest: 'Zone couverte');
            builder.element('styleUrl', nest: '#coverageStyle');
            builder.element('MultiGeometry', nest: () {
              for (final (outer, holes) in coverageIslands) {
                _writePolygon(builder, outer: outer, holes: holes);
              }
            });
          });
        }

        // ── Placemarks : POI ────────────────────────────────────
        for (final poi in pois) {
          builder.element('Placemark', nest: () {
            builder.element('name', nest: poi.state);
            builder.element('styleUrl', nest: '#poiStyle');
            builder.element('description', nest: () {
              builder.text(_poiDescription(poi));
            });
            builder.element('Point', nest: () {
              builder.element(
                'coordinates',
                nest: '${poi.position.longitude},${poi.position.latitude},0',
              );
            });
            // Données structurées (Data + ExtendedData) pour les SIG.
            builder.element('ExtendedData', nest: () {
              _writeData(builder, 'etat', poi.state);
              _writeData(builder, 'commentaire', poi.comment);
              _writeData(
                builder,
                'horodatage',
                poi.timestamp.toIso8601String(),
              );
            });
          });
        }
      });
    });
    // Pretty-print désactivé : le sérialiseur du paquet `xml` remplace
    // les sauts de ligne dans les textes par des espaces, ce qui rendrait
    // les `<coordinates>` peu lisibles. La lisibilité des coordonnées
    // (une par ligne) est plus utile que l'indentation du reste.
    return builder.buildDocument().toXmlString(pretty: false);
  }

  /// Écrit un `<Style>` KML avec PolyStyle + LineStyle (+ IconStyle).
  void _writeStyle(
    XmlBuilder builder, {
    required String id,
    required int fillColor,
    required int lineColor,
    required double lineWidth,
    double? iconScale,
  }) {
    builder.element('Style', nest: () {
      builder.attribute('id', id);
      builder.element('IconStyle', nest: () {
        if (iconScale != null) {
          builder.element('scale', nest: iconScale.toString());
        }
        builder.element('Icon', nest: () {
          builder.element(
            'href',
            nest: 'http://maps.google.com/mapfiles/kml/paddle/'
                'red-circle.png',
          );
        });
      });
      builder.element('LineStyle', nest: () {
        builder.element('color', nest: _kmlColor(lineColor));
        builder.element('width', nest: lineWidth.toString());
      });
      builder.element('PolyStyle', nest: () {
        builder.element('color', nest: _kmlColor(fillColor));
      });
    });
  }

  /// Écrit un `<Polygon>` avec boundaries extérieurs et trous.
  void _writePolygon(
    XmlBuilder builder, {
    required List<LatLng> outer,
    required List<List<LatLng>> holes,
  }) {
    builder.element('Polygon', nest: () {
      builder.element('tessellate', nest: '1');
      builder.element('outerBoundaryIs', nest: () {
        builder.element('LinearRing', nest: () {
          builder.element('coordinates', nest: _coordinates(outer));
        });
      });
      for (final hole in holes) {
        builder.element('innerBoundaryIs', nest: () {
          builder.element('LinearRing', nest: () {
            builder.element('coordinates', nest: _coordinates(hole));
          });
        });
      }
    });
  }

  /// Formate une liste de coordonnées KML (lon,lat[,alt] \n …).
  String _coordinates(List<LatLng> points) => [
        for (final p in points) '${p.longitude},${p.latitude},0',
      ].join('\n');

  /// Description lisible d'un POI (affichée dans Google Earth).
  String _poiDescription(Poi poi) =>
      'État : ${poi.state}\n'
      'Commentaire : ${poi.comment.isEmpty ? "—" : poi.comment}\n'
      'Heure : ${poi.timestamp.toLocal()}';

  /// Convertit une couleur ARGB Flutter (0xAARRGGBB) en KML aabbggrr.
  String _kmlColor(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${hex(a)}${hex(b)}${hex(g)}${hex(r)}';
  }

  /// Écrit une donnée structurée `<Data><value>…</value></Data>`.
  void _writeData(XmlBuilder builder, String name, String value) {
    builder.element('Data', nest: () {
      builder.attribute('name', name);
      builder.element('value', nest: value);
    });
  }
}
