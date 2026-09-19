import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/tracking_controller.dart';
import '../export/kml_builder.dart';
import '../models/app_settings.dart';
import '../models/session.dart';
import '../services/permissions_service.dart';
import 'settings_screen.dart';

/// Écran principal : carte plein écran, bouton Commencer/Stop, Signaler.
///
/// La carte est fournie par [mapBuilder] (voir `map_screen.dart`) pour
/// garder cet écran centré sur la logique : tracking, signalement,
/// export KML et partage natif.
class HomeScreen extends StatefulWidget {
  final AppSettings settings;
  final TrackingController controller;
  final PermissionsService permissions;
  final bool offlineReady;
  final Future<void> Function() onDownloadMap;
  final void Function(AppSettings) onSettingsChanged;
  final Widget Function(BuildContext, TrackingController) mapBuilder;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.controller,
    required this.permissions,
    required this.offlineReady,
    required this.onDownloadMap,
    required this.onSettingsChanged,
    required this.mapBuilder,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TrackingController get _controller => widget.controller;

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _onMainAction() async {
    if (_controller.isRecording) {
      await _stopAndExport();
    } else {
      final error = await widget.permissions.ensureLocationPermission();
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
        return;
      }
      await _controller.start();
    }
  }

  /// « Stop » : fige la session, calcule l'union exacte en isolate,
  /// génère le KML et ouvre le partage natif.
  Future<void> _stopAndExport() async {
    setState(() => _exporting = true);
    try {
      final session = await _controller.stop();
      if (session.samples.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun point GPS enregistré : export ignoré.'),
          ),
        );
        return;
      }
      // Union exacte (clipper2) hors du thread UI.
      final islands = await computeCoverageIslands(session);
      final kml = KmlBuilder().build(
        coverageIslands: islands,
        pois: session.pois,
      );
      await _shareKml(kml, session);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareKml(String kml, TrackingSession session) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = 'zone_${session.id}.kml';
      final file = File('${dir.path}/$name');
      await file.writeAsString(kml, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Zone couverte — export KML',
          title: 'Zone couverte',
          text: widget.settings.email.isEmpty
              ? null
              : 'Destinataire : ${widget.settings.email}',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\u2019export : $e')),
      );
    }
  }

  Future<void> _onReport() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _ReportDialog(states: widget.settings.states),
    );
    if (result == null) return;
    _controller.addReport(state: result.$1, comment: result.$2);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signalement enregistré.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recording = _controller.isRecording;
    return Scaffold(
      body: widget.mapBuilder(context, _controller),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        height: 64,
        width: 64,
        child: FloatingActionButton(
          heroTag: 'main-action',
          onPressed: _exporting ? null : _onMainAction,
          backgroundColor:
              recording ? Colors.red : Theme.of(context).colorScheme.primary,
          child: _exporting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(recording ? Icons.stop : Icons.play_arrow, size: 32),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        child: Row(
          children: [
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Paramètres',
              onPressed: _openSettings,
            ),
            const SizedBox(width: 8),
            // Fond de plan : indicateur offline + accès au téléchargement.
            IconButton(
              icon: Icon(
                widget.offlineReady
                    ? Icons.map_outlined
                    : Icons.map,
                color: widget.offlineReady
                    ? Colors.green
                    : Colors.orange,
              ),
              tooltip: widget.offlineReady
                  ? 'Carte hors ligne prête'
                  : 'Télécharger la carte hors ligne',
              onPressed: widget.onDownloadMap,
            ),
            const Spacer(),
            Text(_controller.sampleCount > 0
                ? '${_controller.sampleCount} pts'
                : ''),
            const Spacer(),
            // « Signaler » : accessible uniquement pendant l'enregistrement.
            IconButton(
              icon: const Icon(Icons.flag),
              tooltip: 'Signaler',
              color: recording
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).disabledColor,
              onPressed: recording ? _onReport : null,
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final newSettings = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(initial: widget.settings),
      ),
    );
    if (newSettings != null) {
      widget.onSettingsChanged(newSettings);
    }
  }
}

/// Modale de signalement : sélection d'état + commentaire.
class _ReportDialog extends StatefulWidget {
  final List<String> states;

  const _ReportDialog({required this.states});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late String _selected;
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = widget.states.first;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Signaler'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selected,
            items: [
              for (final s in widget.states)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _selected = v ?? _selected),
            decoration: const InputDecoration(labelText: 'État'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Commentaire',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_selected, _comment.text)),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
