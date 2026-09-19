import 'package:flutter_test/flutter_test.dart';
import 'package:zone_coverage/src/models/app_settings.dart';

void main() {
  test('AppSettings - valeurs par défaut', () {
    const settings = AppSettings();
    expect(settings.brushRadiusMeters, 10);
    expect(settings.states, ['Suspicion de défaut']);
    expect(settings.email, '');
  });

  test('AppSettings - copyWith', () {
    const settings = AppSettings();
    final updated = settings.copyWith(
      brushRadiusMeters: 25,
      states: ['Fissure', 'Corrosion'],
      email: 'ops@example.com',
    );
    expect(updated.brushRadiusMeters, 25);
    expect(updated.states, ['Fissure', 'Corrosion']);
    expect(updated.email, 'ops@example.com');
  });
}
