import 'package:flutter/material.dart';

import '../models/app_settings.dart';

/// Écran « Paramètres » : rayon du pinceau, états possibles, email.
///
/// Retourne les nouveaux paramètres via `Navigator.pop(context, settings)`
/// ou `null` si annulé.
class SettingsScreen extends StatefulWidget {
  final AppSettings initial;

  const SettingsScreen({super.key, required this.initial});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _radius;
  late List<String> _states;
  late TextEditingController _email;

  /// Choix de rayons prédéfinis (m).
  static const _radiusChoices = [5.0, 10.0, 25.0, 50.0];

  @override
  void initState() {
    super.initState();
    _radius = widget.initial.brushRadiusMeters;
    _states = [...widget.initial.states];
    _email = TextEditingController(text: widget.initial.email);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _save() {
    final settings = AppSettings(
      brushRadiusMeters: _radius,
      states: _states,
      email: _email.text.trim(),
    );
    Navigator.pop(context, settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Rayon du pinceau',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final r in _radiusChoices)
                ChoiceChip(
                  label: Text('${r.toInt()} m'),
                  selected: _radius == r,
                  onSelected: (_) => setState(() => _radius = r),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'États possibles (signalements)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _states.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _states[i],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _states[i] = v,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _states.length > 1
                        ? () => setState(() => _states.removeAt(i))
                        : null,
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un état'),
              onPressed: () => setState(() => _states.add('Nouvel état')),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Email de destination',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'adresse@example.com',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
