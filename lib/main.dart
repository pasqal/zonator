import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/controllers/tracking_controller.dart';
import 'src/models/app_settings.dart';
import 'src/services/offline_map_service.dart';
import 'src/services/permissions_service.dart';
import 'src/services/settings_service.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/map_screen.dart';
import 'src/ui/offline_download_screen.dart';

/// Point d'entrée de l'application.
///
/// Initialise la persistance (paramètres), le fond de plan offline et
/// le contrôleur de tracking, puis affiche l'écran principal.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settingsService = SettingsService(prefs);
  final settings = settingsService.load();

  final offlineMap = OfflineMapService();
  final offlineStatus = await offlineMap.status();

  runApp(ZoneCoverageApp(
    settings: settings,
    settingsService: settingsService,
    offlineMap: offlineMap,
    offlineReady: offlineStatus == OfflineMapStatus.ready,
  ));
}

/// Application : état racine (paramètres, contrôleurs, services).
class ZoneCoverageApp extends StatefulWidget {
  final AppSettings settings;
  final SettingsService settingsService;
  final OfflineMapService offlineMap;
  final bool offlineReady;

  const ZoneCoverageApp({
    super.key,
    required this.settings,
    required this.settingsService,
    required this.offlineMap,
    required this.offlineReady,
  });

  @override
  State<ZoneCoverageApp> createState() => _ZoneCoverageAppState();
}

class _ZoneCoverageAppState extends State<ZoneCoverageApp> {
  late AppSettings _settings;
  late TrackingController _controller;
  late bool _offlineReady;

  final _permissions = PermissionsService();

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _offlineReady = widget.offlineReady;
    _controller = TrackingController(
      brushRadiusMeters: _settings.brushRadiusMeters,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSettingsChanged(AppSettings newSettings) {
    widget.settingsService.save(newSettings);
    setState(() {
      _settings = newSettings;
      if (!_controller.isRecording) {
        // Le rayon ne s'applique qu'à la prochaine session : recréer le
        // contrôleur hors enregistrement.
        _controller.dispose();
        _controller = TrackingController(
          brushRadiusMeters: newSettings.brushRadiusMeters,
        );
      }
    });
  }

  Future<void> _openOfflineDownload() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            OfflineMapDownloadScreen(service: widget.offlineMap),
      ),
    );
    final status = await widget.offlineMap.status();
    if (mounted) {
      setState(() => _offlineReady = status == OfflineMapStatus.ready);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zone Coverage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2196F3)),
      home: HomeScreen(
        settings: _settings,
        controller: _controller,
        permissions: _permissions,
        offlineReady: _offlineReady,
        onDownloadMap: _openOfflineDownload,
        onSettingsChanged: _onSettingsChanged,
        mapBuilder: (context, controller) => MapScreen(
          controller: controller,
          offlineMap: widget.offlineMap,
        ),
      ),
    );
  }
}
