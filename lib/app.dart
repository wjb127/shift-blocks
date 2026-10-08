import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import 'roster.dart';
import 'ads.dart';
import 'strings.dart';

Future<void> start() async {
  WidgetsFlutterBinding.ensureInitialized();
  data.initializeTimeZones();
  final r = Roster();
  String? error;
  try {
    await r.load();
  } catch (_) {
    error = S.loadError;
  }
  runApp(
    MaterialApp(
      title: S.title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff137c72)),
        useMaterial3: true,
      ),
      home: Home(roster: r, error: error),
    ),
  );
}

class Home extends StatefulWidget {
  final Roster roster;
  final String? error;
  final bool initializeAds;
  const Home({
    super.key,
    required this.roster,
    this.error,
    this.initializeAds = true,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Roster get r => widget.roster;
  final ads = AdsController();
  int tab = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool busy = false;
  bool readOnly = false;
  @override
  void initState() {
    super.initState();
    readOnly = widget.error != null;
    r.addListener(refresh);
    if (widget.initializeAds) {
      ads.initialize();
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    r.removeListener(refresh);
    ads.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> action(
    Future<void> Function() fn, {
    bool recovery = false,
  }) async {
    if (busy) return false;
    if (readOnly && !recovery) {
      message(S.loadError);
      return false;
    }
    final previous = r.export(), previousUndo = r.undoData;
    setState(() => busy = true);
    try {
      await fn();
      if (recovery) readOnly = false;
      return true;
    } catch (_) {
      r.restore(previous);
      r.undoData = previousUndo;
      refresh();
      message(S.saveError);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String time(int n) =>
      TimeOfDay(hour: n ~/ 60, minute: n % 60).format(context);
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text(S.title),
      actions: [
        IconButton(
          tooltip: S.undo,
          onPressed: r.undoData == null || busy ? null : () => action(r.undo),
          icon: const Icon(Icons.undo),
        ),
      ],
    ),
    body: Column(
      children: [
        if (readOnly)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.error!),
          ),
        Expanded(
          child: tab == 0
              ? calendar()
              : tab == 1
              ? drafts()
              : settings(),
        ),
        SetupBanner(ads: ads),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (i) => setState(() => tab = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.calendar_month),
          label: S.calendar,
        ),
        NavigationDestination(icon: Icon(Icons.auto_awesome), label: S.drafts),
        NavigationDestination(icon: Icon(Icons.settings), label: S.settings),
      ],
    ),
  );
  Widget calendar() {
    final today = dayOnly(tz.TZDateTime.now(r.zone));
    final upcoming =
        r.entries.entries
            .where(
              (e) =>
                  e.key.compareTo(dateKey(today)) >= 0 &&
                  !r.shift(e.value.shift).off,
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final end = DateTime.utc(month.year, month.month + 1, 0);
    int count = 0, total = 0;
    for (var day = 1; day <= end.day; day++) {
      final d = DateTime.utc(month.year, month.month, day),
          e = r.entries[dateKey(d)];
      if (e != null) {
        final s = r.shift(e.shift);
        if (!s.off) count++;
        total += s.minutes(d, r.zone);
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: S.previous,
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(month),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: S.next,
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Text(
          '$count ${S.shifts} · ${(total / 60).toStringAsFixed(1)} ${S.hours}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (upcoming.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text(S.nextShift),
            subtitle: Text(
              '${upcoming.first.key} · ${r.shift(upcoming.first.value.shift).name} · ${time(r.shift(upcoming.first.value.shift).start)}',
            ),
          ),
        Row(
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map(
                (day) =>
                    Expanded(child: Text(day, textAlign: TextAlign.center)),
              )
              .toList(),
        ),
        LayoutBuilder(
          builder: (c, size) => Wrap(
            children: List.generate(
              end.day + DateTime.utc(month.year, month.month).weekday - 1,
              (i) {
                final day =
                    i - DateTime.utc(month.year, month.month).weekday + 2;
                if (day < 1) {
                  return SizedBox(width: size.maxWidth / 7, height: 64);
                }
                final d = DateTime.utc(month.year, month.month, day),
                    e = r.entries[dateKey(d)],
                    s = e == null ? null : r.shift(e.shift);
                return SizedBox(
                  width: size.maxWidth / 7,
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Material(
                      color: s == null
                          ? Theme.of(c).colorScheme.surfaceContainer
                          : Color(s.color).withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => editDay(d),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$day'),
                            Text(
                              s?.name ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            if (e?.locked == true)
                              const Icon(Icons.lock, size: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(r.zoneName),
        const Text(S.calendarHint),
        ...List.generate(end.day, (i) {
          final d = DateTime.utc(month.year, month.month, i + 1),
              e = r.entries[dateKey(d)];
          if (e == null) return const SizedBox.shrink();
          final s = r.shift(e.shift);
          return ListTile(
            onTap: () => editDay(d),
            leading: CircleAvatar(
              backgroundColor: Color(s.color),
              child: Text(
                '${i + 1}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(s.name),
            subtitle: Text(
              s.off
                  ? S.off
                  : '${time(s.start)} → ${time(s.end)}${s.overnight ? ' (+1)' : ''} · ${(s.minutes(d, r.zone) / 60).toStringAsFixed(1)} ${S.hours}',
            ),
            trailing: e.locked ? const Icon(Icons.lock) : null,
          );
        }),
      ],
    );
  }

  Future<bool> dialog(
    String title,
    Widget body, {
    String confirm = S.save,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text(S.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(confirm),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> editDay(DateTime d) async {
    var id = r.entries[dateKey(d)]?.shift ?? r.shifts.first.id;
    bool lock = r.entries[dateKey(d)]?.locked ?? true;
    final yes = await dialog(
      DateFormat.yMMMd().format(d),
      StatefulBuilder(
        builder: (c, change) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              isExpanded: true,
              value: id,
              items: r.shifts
                  .map(
                    (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                  )
                  .toList(),
              onChanged: (v) => change(() => id = v!),
            ),
            SwitchListTile(
              title: const Text(S.lock),
              value: lock,
              onChanged: (v) => change(() => lock = v),
            ),
          ],
        ),
      ),
    );
    if (yes) {
      await action(() async {
        r.undoData = r.export();
        r.entries[dateKey(d)] = Entry(id, locked: lock);
        await r.save();
      });
    }
  }

  Widget drafts() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(S.draftTitle, style: Theme.of(context).textTheme.headlineSmall),
      const Text(S.draftHint),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: busy ? null : rotation,
        icon: const Icon(Icons.repeat),
        label: const Text(S.rotation),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : random,
        icon: const Icon(Icons.shuffle),
        label: const Text(S.random),
      ),
      const SizedBox(height: 20),
      Text('${S.anchor}: ${r.anchor}'),
      Text(
        '${S.pattern}: ${r.pattern.map((id) => r.shift(id).name).join(' → ')}',
      ),
      Text('${S.position}: ${r.position + 1}'),
      if (r.lastSeed != null) Text('${S.seed}: ${r.lastSeed}'),
    ],
  );
  Future<DateTimeRange?> range() => showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime(2040),
    initialDateRange: DateTimeRange(
      start: DateTime.now(),
      end: DateTime.now().add(const Duration(days: 13)),
    ),
  );
  Widget input(TextEditingController c, String label) => TextField(
    controller: c,
    decoration: InputDecoration(labelText: label),
  );
  Future<bool> preview(Draft d) async {
    if (d.error != null) {
      await dialog(S.noDraft, Text(d.error!), confirm: S.close);
      return false;
    }
    if (d.days.isEmpty) {
      message(S.noChanges);
      return false;
    }
    final yes = await dialog(
      '${S.preview} · ${d.days.length} ${S.days}',
      SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(S.preserve),
            ...d.days.entries.map(
              (e) => ListTile(
                title: Text(e.key),
                subtitle: Text(r.shift(e.value.shift).name),
              ),
            ),
          ],
        ),
      ),
      confirm: S.apply,
    );
    return yes ? await action(() => r.apply(d)) : false;
  }

  Future<void> rotation() async {
    final p = TextEditingController(
          text: r.pattern
              .map((id) => r.shifts.indexWhere((s) => s.id == id) + 1)
              .join(','),
        ),
        a = TextEditingController(text: r.anchor),
        pos = TextEditingController(text: '${r.position + 1}');
    final yes = await dialog(
      S.rotation,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            r.shifts
                .asMap()
                .entries
                .map((e) => '${e.key + 1}: ${e.value.name}')
                .join('\n'),
          ),
          input(p, S.patternInput),
          input(a, S.anchorInput),
          input(pos, S.position),
        ],
      ),
      confirm: S.preview,
    );
    if (yes) {
      try {
        final ids = p.text
                .split(',')
                .map((s) => int.parse(s.trim()) - 1)
                .toList(),
            position = int.parse(pos.text) - 1;
        final date = DateTime.parse(a.text);
        if (ids.isEmpty ||
            ids.length > 100 ||
            ids.any((x) => x < 0 || x >= r.shifts.length) ||
            position < 0 ||
            position >= ids.length ||
            dateKey(date) != a.text) {
          throw const FormatException();
        }
        final picked = await range();
        if (picked != null) {
          final old = r.export();
          r.pattern = ids.map((i) => r.shifts[i].id).toList();
          r.anchor = a.text;
          r.position = position;
          final applied = await preview(
            r.rotate(picked.start, picked.end, DateTime.now()),
          );
          if (!applied) {
            r.restore(old);
          } else {
            r.undoData = old;
          }
        }
      } catch (_) {
        message(S.patternError);
      }
    }
    p.dispose();
    a.dispose();
    pos.dispose();
  }

  Future<void> random() async {
    final period = await range();
    if (period == null) return;
    final n = dayOnly(period.end).difference(dayOnly(period.start)).inDays + 1;
    final counts = {
      for (final s in r.shifts)
        s.id: TextEditingController(text: s.off ? '$n' : '0'),
    };
    final run = TextEditingController(text: '4'),
        rest = TextEditingController(text: '11'),
        seed = TextEditingController(
          text: '${Random.secure().nextInt(2147483647)}',
        );
    final yes = await dialog(
      S.random,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$n ${S.days}'),
          ...r.shifts.map(
            (s) => input(counts[s.id]!, '${s.name} ${S.targetCount}'),
          ),
          input(run, S.maxRun),
          input(rest, S.rest),
          input(seed, S.seed),
        ],
      ),
      confirm: S.preview,
    );
    if (yes) {
      try {
        await preview(
          r.randomDraft(
            period.start,
            period.end,
            DateTime.now(),
            counts.map((k, v) => MapEntry(k, int.parse(v.text))),
            int.parse(run.text),
            (double.parse(rest.text) * 60).round(),
            int.parse(seed.text),
          ),
        );
      } catch (_) {
        message(S.numericError);
      }
    }
    for (final c in [...counts.values, run, rest, seed]) {
      c.dispose();
    }
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(S.presets, style: Theme.of(context).textTheme.titleLarge),
      ...r.shifts.map(
        (s) => ListTile(
          leading: CircleAvatar(backgroundColor: Color(s.color)),
          title: Text(s.name),
          subtitle: Text(
            s.off
                ? S.off
                : '${time(s.start)} → ${time(s.end)} · ${s.pause} ${S.breakMinutes}',
          ),
          onTap: () => preset(s),
        ),
      ),
      OutlinedButton(
        onPressed: () => preset(null),
        child: const Text(S.addPreset),
      ),
      ListTile(
        title: const Text(S.timezone),
        subtitle: Text(r.zoneName),
        onTap: zone,
      ),
      const Text(S.localOnly),
      FilledButton.icon(
        onPressed: busy
            ? null
            : () => action(() async {
                await SharePlus.instance.share(
                  ShareParams(
                    files: [
                      XFile.fromData(
                        utf8.encode(r.export()),
                        mimeType: 'application/json',
                        name: 'shift-blocks-backup.json',
                      ),
                    ],
                    fileNameOverrides: ['shift-blocks-backup.json'],
                    sharePositionOrigin: const Rect.fromLTWH(20, 100, 100, 50),
                  ),
                );
              }),
        icon: const Icon(Icons.save_alt),
        label: const Text(S.backup),
      ),
      OutlinedButton(
        onPressed: busy ? null : restore,
        child: const Text(S.restore),
      ),
      if (ads.privacyRequired)
        TextButton(
          onPressed: ads.privacyOptions,
          child: const Text(S.adPrivacy),
        ),
      const Text(S.privacy),
    ],
  );
  Future<void> restore() async {
    try {
      final f = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'JSON',
            extensions: ['json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (f == null) return;
      if (await f.length() > 4000000) throw const FormatException();
      final raw = await f.readAsString();
      final check = Roster();
      check.restore(raw);
      if (await dialog(
        S.restore,
        Text('${S.restoreConfirm}\n${check.entries.length} ${S.days}'),
        confirm: S.restore,
      )) {
        await action(() async {
          r.undoData = r.export();
          r.restore(raw);
          await r.save();
        }, recovery: true);
      }
    } catch (_) {
      message(S.backupError);
    }
  }

  Future<void> zone() async {
    final c = TextEditingController(text: r.zoneName);
    if (await dialog(
      S.timezone,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Text(S.zoneHint), input(c, S.timezone)],
      ),
    )) {
      try {
        if (c.text.trim() != 'Etc/UTC') {
          tz.getLocation(c.text.trim());
        }
        await action(() async {
          r.undoData = r.export();
          r.zoneName = c.text.trim();
          await r.save();
        });
      } catch (_) {
        message(S.zoneError);
      }
    }
    c.dispose();
  }

  Future<void> preset(Shift? old) async {
    final name = TextEditingController(text: old?.name ?? ''),
        pause = TextEditingController(text: '${old?.pause ?? 0}');
    int start = old?.start ?? 480,
        end = old?.end ?? 1020,
        color = old?.color ?? 0xffb45309;
    bool off = old?.off ?? false;
    final yes = await dialog(
      S.presets,
      StatefulBuilder(
        builder: (c, change) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            input(name, S.name),
            SwitchListTile(
              title: const Text(S.off),
              value: off,
              onChanged: (v) => change(() => off = v),
            ),
            if (!off) ...[
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: c,
                    initialTime: TimeOfDay(
                      hour: start ~/ 60,
                      minute: start % 60,
                    ),
                  );
                  if (t != null) change(() => start = t.hour * 60 + t.minute);
                },
                child: Text('${S.start}: ${time(start)}'),
              ),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: c,
                    initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60),
                  );
                  if (t != null) change(() => end = t.hour * 60 + t.minute);
                },
                child: Text('${S.end}: ${time(end)}'),
              ),
              input(pause, S.breakMinutes),
            ],
            Wrap(
              children:
                  [0xff137c72, 0xff5b50ac, 0xff64748b, 0xffb45309, 0xffbe185d]
                      .map(
                        (v) => IconButton(
                          tooltip: S.color,
                          onPressed: () => change(() => color = v),
                          icon: Icon(
                            color == v ? Icons.check_circle : Icons.circle,
                            color: Color(v),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
        ),
      ),
    );
    if (yes) {
      try {
        final s = Shift.read(
          Shift(
            old?.id ?? 'custom-${DateTime.now().microsecondsSinceEpoch}',
            name.text.trim(),
            color,
            start,
            end,
            int.parse(pause.text),
            off: off,
          ).json(),
        );
        if (!off && s.pause >= ((end - start + 1439) % 1440) + 1) {
          throw const FormatException();
        }
        await action(() async {
          r.undoData = r.export();
          if (old == null) {
            r.shifts.add(s);
          } else {
            r.shifts[r.shifts.indexWhere((x) => x.id == old.id)] = s;
          }
          await r.save();
        });
      } catch (_) {
        message(S.presetError);
      }
    }
    name.dispose();
    pause.dispose();
  }
}
