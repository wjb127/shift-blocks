import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dayOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);
DateTime nextDay(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

class Shift {
  final String id, name;
  final int color, start, end, pause;
  final bool off;
  const Shift(
    this.id,
    this.name,
    this.color,
    this.start,
    this.end,
    this.pause, {
    this.off = false,
  });
  bool get overnight => !off && end <= start;
  Map<String, dynamic> json() => {
    'id': id,
    'name': name,
    'color': color,
    'start': start,
    'end': end,
    'pause': pause,
    'off': off,
  };
  factory Shift.read(Map<String, dynamic> j) {
    final s = Shift(
      j['id'] as String,
      j['name'] as String,
      j['color'] as int,
      j['start'] as int,
      j['end'] as int,
      j['pause'] as int,
      off: j['off'] as bool,
    );
    if (s.id.isEmpty ||
        s.name.trim().isEmpty ||
        s.name.length > 80 ||
        s.start < 0 ||
        s.start >= 1440 ||
        s.end < 0 ||
        s.end >= 1440 ||
        s.pause < 0 ||
        s.pause > 1440 ||
        s.color < 0 ||
        s.color > 0xffffffff) {
      throw const FormatException('Invalid preset');
    }
    return s;
  }
  tz.TZDateTime begins(DateTime d, tz.Location zone) =>
      tz.TZDateTime(zone, d.year, d.month, d.day, start ~/ 60, start % 60);
  tz.TZDateTime finishes(DateTime d, tz.Location zone) => tz.TZDateTime(
    zone,
    d.year,
    d.month,
    d.day + (overnight ? 1 : 0),
    end ~/ 60,
    end % 60,
  );
  int minutes(DateTime d, tz.Location zone) => off
      ? 0
      : max(0, finishes(d, zone).difference(begins(d, zone)).inMinutes - pause);
}

class Entry {
  final String shift;
  final bool locked;
  const Entry(this.shift, {this.locked = false});
  Map<String, dynamic> json() => {'shift': shift, 'locked': locked};
}

class Draft {
  final Map<String, Entry> days;
  final String? error;
  final int? seed;
  Draft(this.days, {this.error, this.seed});
}

class Roster extends ChangeNotifier {
  List<Shift> shifts = [
    const Shift('day', 'Day', 0xff137c72, 480, 1020, 60),
    const Shift('night', 'Night', 0xff5b50ac, 1200, 480, 60),
    const Shift('off', 'Off', 0xff64748b, 0, 0, 0, off: true),
  ];
  Map<String, Entry> entries = {};
  List<String> pattern = ['day', 'day', 'night', 'night', 'off', 'off'];
  String anchor = dateKey(DateTime.now()), zoneName = 'Etc/UTC';
  int position = 0;
  String? undoData;
  int? lastSeed;
  tz.Location get zone =>
      zoneName == 'Etc/UTC' ? tz.UTC : tz.getLocation(zoneName);
  Shift shift(String id) => shifts.firstWhere((s) => s.id == id);
  Map<String, dynamic> json() => {
    'schema': 1,
    'presets': shifts.map((s) => s.json()).toList(),
    'days': entries.map((k, v) => MapEntry(k, v.json())),
    'pattern': pattern,
    'anchor': anchor,
    'position': position,
    'timezone': zoneName,
    'seed': lastSeed,
  };
  String export() => const JsonEncoder.withIndent('  ').convert(json());
  void restore(String data) {
    if (data.length > 4000000) throw const FormatException('Backup too large');
    final j = jsonDecode(data) as Map<String, dynamic>;
    if (j['schema'] != 1) throw const FormatException('Unsupported backup');
    final presets = (j['presets'] as List)
        .map((x) => Shift.read(Map<String, dynamic>.from(x)))
        .toList();
    final ids = presets.map((s) => s.id).toSet();
    if (presets.isEmpty ||
        presets.length > 50 ||
        ids.length != presets.length) {
      throw const FormatException('Invalid presets');
    }
    final days = <String, Entry>{};
    for (final x in (j['days'] as Map).entries) {
      final k = x.key as String;
      final d = DateTime.tryParse(k);
      if (d == null ||
          dateKey(d) != k ||
          !ids.contains(x.value['shift']) ||
          x.value['locked'] is! bool) {
        throw const FormatException('Invalid date or shift');
      }
      days[k] = Entry(x.value['shift'], locked: x.value['locked']);
    }
    if (days.length > 40000) throw const FormatException('Too many dates');
    final p = List<String>.from(j['pattern'] as List);
    final a = j['anchor'] as String,
        pos = j['position'] as int,
        z = j['timezone'] as String;
    if (p.isEmpty ||
        p.length > 100 ||
        p.any((x) => !ids.contains(x)) ||
        pos < 0 ||
        pos >= p.length ||
        DateTime.tryParse(a) == null ||
        dateKey(DateTime.parse(a)) != a) {
      throw const FormatException('Invalid pattern');
    }
    if (z != 'Etc/UTC') {
      tz.getLocation(z);
    }
    if (j['seed'] != null && j['seed'] is! int) {
      throw const FormatException('Invalid seed');
    }
    shifts = presets;
    entries = days;
    pattern = p;
    anchor = a;
    position = pos;
    zoneName = z;
    lastSeed = j['seed'];
  }

  Future<void> load() async {
    final data = (await SharedPreferences.getInstance()).getString(
      'shiftBlocks',
    );
    if (data != null) restore(data);
  }

  Future<void> save() async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      'shiftBlocks',
      export(),
    );
    if (!ok) throw StateError('Could not save schedule');
    notifyListeners();
  }

  Draft rotate(DateTime from, DateTime to, DateTime today) {
    final out = <String, Entry>{};
    final a = DateTime.parse(anchor);
    for (var d = dayOnly(from); !d.isAfter(dayOnly(to)); d = nextDay(d, 1)) {
      final key = dateKey(d);
      if (d.isBefore(dayOnly(today)) || entries[key]?.locked == true) continue;
      final i = (d.difference(dayOnly(a)).inDays + position) % pattern.length;
      out[key] = Entry(pattern[i]);
    }
    return Draft(out);
  }

  Future<void> apply(Draft draft) async {
    if (draft.error != null) throw StateError(draft.error!);
    undoData = export();
    entries = {...entries, ...draft.days};
    lastSeed = draft.seed ?? lastSeed;
    await save();
  }

  Future<void> undo() async {
    if (undoData == null) return;
    final value = undoData!;
    restore(value);
    undoData = null;
    await save();
  }

  bool constraints(
    Map<String, Entry> candidate,
    DateTime from,
    DateTime to,
    int maxRun,
    int restMinutes,
  ) {
    final all = {...entries, ...candidate};
    int run = 0;
    DateTime? lastDate;
    Shift? lastShift;
    // Include neighboring stored shifts so period boundaries cannot evade rest/run rules.
    final first = nextDay(from, -maxRun - 1), last = nextDay(to, maxRun + 1);
    for (var d = first; !d.isAfter(last); d = nextDay(d, 1)) {
      final e = all[dateKey(d)];
      if (e == null) {
        run = 0;
        continue;
      }
      final s = shift(e.shift);
      if (s.off) {
        run = 0;
        continue;
      }
      run++;
      if (run > maxRun) return false;
      if (lastDate != null &&
          s
                  .begins(d, zone)
                  .difference(lastShift!.finishes(lastDate, zone))
                  .inMinutes <
              restMinutes) {
        return false;
      }
      lastDate = d;
      lastShift = s;
    }
    return true;
  }

  Draft randomDraft(
    DateTime from,
    DateTime to,
    DateTime today,
    Map<String, int> targets,
    int maxRun,
    int restMinutes,
    int seed, {
    int attempts = 1200,
  }) {
    final n = dayOnly(to).difference(dayOnly(from)).inDays + 1;
    if (n < 1 ||
        n > 62 ||
        maxRun < 1 ||
        maxRun > 31 ||
        restMinutes < 0 ||
        restMinutes > 4320 ||
        targets.values.any((x) => x < 0) ||
        targets.keys.any((x) => !shifts.any((s) => s.id == x)) ||
        targets.values.fold(0, (a, b) => a + b) != n) {
      return Draft(
        {},
        error: 'Counts must equal the period length (up to 62 days); check rest and consecutive limits.',
      );
    }
    final fixed = <String, Entry>{},
        left = Map<String, int>.from(targets),
        editable = <String>[];
    for (var d = dayOnly(from); !d.isAfter(dayOnly(to)); d = nextDay(d, 1)) {
      final k = dateKey(d), old = entries[k];
      if (d.isBefore(dayOnly(today)) || old?.locked == true) {
        if (old == null) {
          return Draft(
            {},
            error: 'Past dates without a saved shift cannot be allocated.',
          );
        }
        fixed[k] = old;
        left[old.shift] = (left[old.shift] ?? 0) - 1;
      } else {
        editable.add(k);
      }
    }
    if (left.values.any((x) => x < 0)) {
      return Draft({}, error: 'Locked or past shifts exceed target counts.');
    }
    final choices = <String>[];
    left.forEach((k, v) {
      choices.addAll(List.filled(v, k));
    });
    final rng = Random(seed);
    for (var i = 0; i < attempts; i++) {
      choices.shuffle(rng);
      final all = Map<String, Entry>.from(fixed);
      for (var j = 0; j < editable.length; j++) {
        all[editable[j]] = Entry(choices[j]);
      }
      if (constraints(all, dayOnly(from), dayOnly(to), maxRun, restMinutes)) {
        all.removeWhere((k, _) => fixed.containsKey(k));
        return Draft(all, seed: seed);
      }
    }
    return Draft(
      {},
      seed: seed,
      error:
          'No valid draft found in $attempts attempts. Try more off days, a shorter rest limit or fewer consecutive constraints. Existing schedule is unchanged.',
    );
  }
}
