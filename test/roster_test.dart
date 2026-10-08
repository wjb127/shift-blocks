import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'package:shift_blocks/roster.dart';

void main() {
  setUp(() {
    data.initializeTimeZones();
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'anchored rotations survive backup and restart; dates before anchor wrap',
    () async {
      final r = Roster()..anchor = '2026-10-08';
      r.entries['2026-10-09'] = const Entry('off', locked: true);
      final draft = r.rotate(
        DateTime.utc(2026, 10, 6),
        DateTime.utc(2026, 10, 12),
        DateTime.utc(2026, 10, 7),
      );
      expect(draft.days.containsKey('2026-10-06'), false);
      expect(draft.days.containsKey('2026-10-09'), false);
      expect(draft.days['2026-10-07']!.shift, 'off');
      await r.apply(draft);
      final loaded = Roster();
      await loaded.load();
      expect(loaded.export(), r.export());
      await r.undo();
      expect(r.entries.keys, ['2026-10-09']);
    },
  );
  test('night shifts are one start-date with DST elapsed hours', () {
    final s = const Shift('night', 'Night', 0, 1200, 480, 60);
    expect(s.overnight, true);
    expect(
      s.minutes(DateTime.utc(2026, 10, 24), tz.getLocation('Europe/London')),
      720,
    );
    expect(
      s.minutes(DateTime.utc(2026, 3, 28), tz.getLocation('Europe/London')),
      600,
    );
  });
  test('invalid import does not replace live data', () {
    final r = Roster();
    final before = r.export();
    expect(() => r.restore('{"schema":5}'), throwsA(anything));
    expect(r.export(), before);
  });
  test('seed reproducible and exact counts with bounded constraints', () {
    final r = Roster(),
        start = DateTime.utc(2026, 10, 8),
        end = DateTime.utc(2026, 10, 21);
    final a = r.randomDraft(
      start,
      end,
      start,
      {'day': 6, 'night': 2, 'off': 6},
      3,
      660,
      42,
    );
    final b = r.randomDraft(
      start,
      end,
      start,
      {'day': 6, 'night': 2, 'off': 6},
      3,
      660,
      42,
    );
    expect(a.error, null);
    expect(
      a.days.map((k, v) => MapEntry(k, v.shift)),
      b.days.map((k, v) => MapEntry(k, v.shift)),
    );
    expect(a.days.values.where((e) => e.shift == 'day').length, 6);
    expect(r.constraints(a.days, start, end, 3, 660), true);
  });
  test('impossible counts and locked excess return no valid draft', () {
    final r = Roster(), start = DateTime.utc(2026, 10, 8);
    expect(
      r.randomDraft(start, start, start, {'day': 2}, 4, 660, 1).error,
      isNotNull,
    );
    r.entries[dateKey(start)] = const Entry('night', locked: true);
    expect(
      r.randomDraft(start, start, start, {'off': 1}, 4, 660, 1).error,
      isNotNull,
    );
  });
  test('day after night boundary fails minimum rest', () {
    final r = Roster(), start = DateTime.utc(2026, 10, 8);
    r.entries['2026-10-07'] = const Entry('night', locked: true);
    expect(
      r
          .randomDraft(start, start, start, {'day': 1}, 4, 660, 1, attempts: 10)
          .error,
      isNotNull,
    );
  });
  test('no solution search capped; live entries unchanged', () {
    final r = Roster(),
        start = DateTime.utc(2026, 10, 8),
        end = DateTime.utc(2026, 10, 14);
    final before = r.export();
    expect(
      r
          .randomDraft(start, end, start, {'day': 7}, 2, 660, 7, attempts: 20)
          .error,
      isNotNull,
    );
    expect(r.export(), before);
  });
}
