import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercom_app/widgets/signal_bars.dart';

List<Color?> _barColors(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(SignalBars),
        matching: find.byType(Container),
      ),
    )
    .map((c) => (c.decoration as BoxDecoration).color)
    .toList();

Future<void> _pump(WidgetTester tester, int quality) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SignalBars(quality: quality)),
  ),
);

void main() {
  group('SignalBars', () {
    for (final q in [0, 1, 2, 3]) {
      testWidgets('calidad $q pinta $q barras activas de 3', (tester) async {
        await _pump(tester, q);
        final colors = _barColors(tester);
        expect(colors.length, 3);
        expect(colors.where((c) => c == signalColor(q)).length, q);
      });
    }

    testWidgets('acota valores fuera de rango', (tester) async {
      await _pump(tester, 9);
      expect(
        _barColors(tester).where((c) => c == signalColor(3)).length,
        3,
      );
      await _pump(tester, -4);
      expect(
        _barColors(tester).where((c) => c == signalColor(0)).length,
        0,
      );
    });
  });

  test('cada nivel tiene un color distinto', () {
    final colors = {for (final q in [0, 1, 2, 3]) signalColor(q)};
    expect(colors.length, 4);
  });
}
