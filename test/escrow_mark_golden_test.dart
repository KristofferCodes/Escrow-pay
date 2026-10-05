import 'package:escrow_pay/widgets/escrow_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the monogram paints and fits its box', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0A0A12),
          body: Center(child: EscrowMark(size: 96)),
        ),
      ),
    );

    expect(find.byType(EscrowMark), findsOneWidget);
    expect(tester.getSize(find.byType(EscrowMark)), const Size(96, 96));
  });

  testWidgets('matches the launcher icon geometry', (tester) async {
    // Rendered rather than asserted numerically: the point is that the app's
    // own mark and its launcher icon are the same shape, and only looking at
    // it proves that.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0A0A12),
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: EscrowMark(size: 160),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(EscrowMark),
      matchesGoldenFile('goldens/escrow_mark.png'),
    );
  });

  testWidgets('scales without overflowing at toolbar size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: EscrowMark(size: 18))),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(EscrowMark)), const Size(18, 18));
  });
}
