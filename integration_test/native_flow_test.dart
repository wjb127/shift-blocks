import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:shift_blocks/app.dart';
import 'package:shift_blocks/roster.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native rotation, protected dates, persistence and English screens',
    (t) async {
      data.initializeTimeZones();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('shiftBlocks');
      final r = Roster();
      final today = dayOnly(DateTime.now());
      r.zoneName = 'Europe/London';
      r.anchor = dateKey(today);
      r.entries[dateKey(nextDay(today, 2))] = const Entry('off', locked: true);
      await r.apply(r.rotate(today, nextDay(today, 30), today));
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff137c72),
            ),
            useMaterial3: true,
          ),
          home: Home(roster: r, initializeAds: false),
        ),
      );
      await t.pumpAndSettle();
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      await t.pumpAndSettle();
      expect(find.text('Next scheduled work'), findsOneWidget);
      await binding.takeScreenshot('01-calendar-en');
      await t.tap(find.text('Drafts'));
      await t.pumpAndSettle();
      await binding.takeScreenshot('02-drafts-en');
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await binding.takeScreenshot('03-settings-en');
      final restored = Roster();
      await restored.load();
      expect(restored.anchor, r.anchor);
      expect(restored.entries[dateKey(nextDay(today, 2))]!.locked, isTrue);
      expect(restored.export(), r.export());
      expect(t.takeException(), isNull);
    },
  );
}
