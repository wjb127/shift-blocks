import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:shift_blocks/app.dart';
import 'package:shift_blocks/roster.dart';

void main() {
  testWidgets('compact calendar and protected date editor', (tester) async {
    data.initializeTimeZones();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: Home(roster: Roster(), initializeAds: false)),
    );
    await tester.pump();
    expect(find.text('Shift Blocks'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();
    expect(find.text('Repeat pattern'), findsOneWidget);
    expect(find.text('Random draft'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
