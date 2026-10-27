import 'dart:math' as math;

import '../../core/format.dart' show addDays, dayKey;

import '../../data/drift/database.dart';
import '../presence/presence_log.dart' show SiteVisit;

export '../../core/format.dart' show addDays, dayKey;

/// Journal automatique (plans/13-ux-moderne.md, lot 11) : la journée se remplit à partir de ce que Clockifai sait
/// déjà, et la personne valide. Calcul pur, sans base ni widget : il reçoit les entrées et le planning, et rend la
/// journée type, les créneaux vides et les propositions.
///
/// Les minutes sont comptées depuis minuit, en heure locale.

/// Une plage de la journée, en minutes depuis minuit.
class Span {
  const Span(this.start, this.end);
  final int start;
  final int end;
  int get length => end - start;
  bool overlaps(Span o) => start < o.end && o.start < end;
  Span? intersect(Span o) {
    final s = start > o.start ? start : o.start;
    final e = end < o.end ? end : o.end;
    return e > s ? Span(s, e) : null;
  }

  @override
  bool operator ==(Object other) => other is Span && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
  @override
  String toString() => 'Span(${hm(start)}–${hm(end)})';
}

/// « 08:30 » → 510 ; null si vide ou mal formé.
int? parseHm(String? s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s?.trim() ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  return h < 24 && min < 60 ? h * 60 + min : null;
}

String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

enum DraftSource { presence, claude, calendar, commits, habit, planning }

/// Un événement de l'agenda de la personne (heure et titre seulement), lu par le serveur (plan 13, lot 4).
class CalendarEvent {
  const CalendarEvent({required this.id, required this.start, required this.end, required this.title});
  final String id;
  final DateTime start;
  final DateTime end;
  final String title;
}

/// Un de ses commits (code_commits), avec le dépôt et le projet du dépôt.
class CommitTrace {
  const CommitTrace({required this.sha, required this.subject, required this.at, required this.repository, this.projectId});
  final String sha;
  final String subject;
  final DateTime at;
  final String repository;
  final String? projectId;
}

/// Pourquoi une proposition existe, à traduire par l'interface.
enum ReasonKind {
  /// Sur le chantier, d'après le téléphone : arrivée [a], départ [b] (-1 : encore sur place).
  presence,
  /// Heures calées sur la journée type (règle de l'entreprise).
  presenceRounded,
  /// Claude travaillait sur ce projet : [a] début, [b] fin.
  claudeSession,
  /// Le temps de piloter la session : la suivre, la relire.
  claudePilot,
  /// Habitude sur un même jour de la semaine : [count] fois sur les [of] derniers, vers [a].
  habitWeekday,
  /// Habitude quotidienne : [count] jours sur les [of] derniers jours travaillés, vers [a].
  habitDaily,
  /// Dans l'agenda : de [a] à [b].
  calendar,
  /// [count] commits dans le dépôt [text], de [a] à [b].
  commits,
  /// Planning : [count] minutes prévues sur ce projet ce jour.
  planned,
  /// Déjà saisi sur ce projet aujourd'hui : [count] minutes.
  alreadyLogged,
}

class DraftReason {
  const DraftReason(this.kind, {this.a = 0, this.b = 0, this.count = 0, this.of = 0, this.text = ''});
  final ReasonKind kind;
  final int a;
  final int b;
  final int count;
  final int of;
  final String text;
}

/// Une entrée proposée, pas encore enregistrée.
class Draft {
  const Draft({
    required this.key,
    required this.source,
    required this.span,
    required this.description,
    this.projectId,
    this.taskId,
    this.reasons = const [],
  });

  /// Stable d'un calcul à l'autre (même jour, mêmes données) : sert à l'ignorer pour de bon.
  final String key;
  final DraftSource source;
  final Span span;
  final String description;
  final String? projectId;
  final String? taskId;
  final List<DraftReason> reasons;

  Draft withSpan(Span s) => Draft(key: key, source: source, span: s, description: description, projectId: projectId, taskId: taskId, reasons: reasons);
}

/// Journée type déduite de l'historique : arrivée, pause de midi, départ, durée visée.
class TypicalDay {
  const TypicalDay(
      {required this.start, required this.lunch, required this.end, required this.target, required this.fromHistory, this.fromProfile = false});
  final int start;
  final Span? lunch;
  final int end;
  final int target;
  final bool fromHistory;

  /// Réglée par la personne dans ses paramètres (« Ma journée type »).
  final bool fromProfile;

  static const fallback = TypicalDay(start: 510, lunch: Span(750, 840), end: 1050, target: 450, fromHistory: false);

  /// La journée réglée dans le profil (plan 13, lot 2), ou null si arrivée et départ ne sont pas réglés ; une pause
  /// incomplète ou hors de la journée est ignorée.
  static TypicalDay? ofProfile(Profile? p) {
    final start = parseHm(p?.dayStart), end = parseHm(p?.dayEnd);
    if (start == null || end == null || end <= start) return null;
    final ls = parseHm(p?.lunchStart), le = parseHm(p?.lunchEnd);
    final lunch = ls != null && le != null && start < ls && ls < le && le < end ? Span(ls, le) : null;
    return TypicalDay(
        start: start, lunch: lunch, end: end, target: end - start - (lunch?.length ?? 0), fromHistory: false, fromProfile: true);
  }

  /// Plages de travail (hors pause).
  List<Span> get windows => lunch == null
      ? [Span(start, end)]
      : [if (lunch!.start > start) Span(start, lunch!.start), if (end > lunch!.end) Span(lunch!.end, end)];
}

class DayPlan {
  const DayPlan({required this.typical, required this.windows, required this.busy, required this.drafts, required this.gaps});
  final TypicalDay typical;

  /// Plages de travail du jour (coupées à maintenant pour aujourd'hui).
  final List<Span> windows;

  /// Temps déjà saisi (entrées terminées et chronomètres en cours).
  final List<Span> busy;
  final List<Draft> drafts;

  /// Créneaux encore vides après les propositions.
  final List<Span> gaps;

  int get loggedMinutes => busy.fold(0, (a, s) => a + s.length);
  int get draftMinutes => drafts.fold(0, (a, d) => a + d.span.length);
}

const _minDraft = 10;
const _minGap = 15;

int _snap(int m) => (m / 5).round() * 5;

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// L'heure [minutes] (depuis minuit, à l'horloge) du jour [day].
DateTime atMinute(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, 0, minutes);

/// [t] en minutes depuis minuit le jour [day], à l'horloge : 10:00 vaut 600 même après une nuit de 23 ou 25 heures.
int minuteOf(DateTime t, DateTime day) {
  final l = t.toLocal();
  final days = DateTime.utc(l.year, l.month, l.day).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  return days * 1440 + l.hour * 60 + l.minute;
}

/// Le dernier jour travaillé avant [day] (entrées terminées), à minuit ; null sans historique (« Comme vendredi »).
DateTime? lastWorkedDay(Iterable<TimeEntry> history, DateTime day) {
  DateTime? last;
  for (final e in history) {
    if (e.endAt == null) continue;
    final l = e.startAt.toLocal();
    final d = DateTime(l.year, l.month, l.day);
    if (d.isBefore(day) && (last == null || d.isAfter(last))) last = d;
  }
  return last;
}

/// Plage d'une entrée dans la journée [day] (minuit local), en minutes ; une entrée en cours s'arrête à [now].
Span? spanOf(TimeEntry e, DateTime day, DateTime now) {
  final s = minuteOf(e.startAt, day);
  final end = minuteOf(e.endAt ?? now, day);
  final clipped = Span(s < 0 ? 0 : s, end > 1440 ? 1440 : end);
  return clipped.length > 0 ? clipped : null;
}

int _median(List<int> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

bool _workday(DateTime d) => d.weekday <= DateTime.friday;

/// Journée type sur les jours travaillés de [history] (au moins trois), sinon [TypicalDay.fallback].
TypicalDay typicalDay(List<TimeEntry> history, DateTime now) {
  final byDay = <String, List<Span>>{};
  for (final e in history) {
    if (e.endAt == null) continue;
    final local = e.startAt.toLocal();
    final day = _midnight(local);
    if (!_workday(day)) continue;
    final sp = spanOf(e, day, now);
    if (sp != null) (byDay[dayKey(day)] ??= []).add(sp);
  }
  if (byDay.length < 3) return TypicalDay.fallback;
  final starts = <int>[], ends = <int>[], totals = <int>[], lunchStarts = <int>[], lunchEnds = <int>[];
  for (final spans in byDay.values) {
    spans.sort((a, b) => a.start.compareTo(b.start));
    starts.add(spans.first.start);
    ends.add(spans.map((s) => s.end).reduce((a, b) => a > b ? a : b));
    totals.add(spans.fold(0, (a, s) => a + s.length));
    // Pause de midi : le plus long creux qui commence entre 11:00 et 14:30.
    Span? best;
    for (var i = 1; i < spans.length; i++) {
      final gap = Span(spans[i - 1].end, spans[i].start);
      if (gap.length >= 20 && gap.start >= 660 && gap.start <= 870 && (best == null || gap.length > best.length)) best = gap;
    }
    if (best != null) {
      lunchStarts.add(best.start);
      lunchEnds.add(best.end);
    }
  }
  final lunch = lunchStarts.length * 2 >= byDay.length ? Span(_snap(_median(lunchStarts)), _snap(_median(lunchEnds))) : null;
  final target = ((_median(totals) / 15).round() * 15).clamp(60, 720);
  return TypicalDay(start: _snap(_median(starts)), lunch: lunch, end: _snap(_median(ends)), target: target, fromHistory: true);
}

/// Retire [taken] des plages [free] ; ne garde que les morceaux d'au moins [min] minutes.
List<Span> subtract(List<Span> free, List<Span> taken, {int min = 1}) {
  var out = [...free];
  for (final t in taken) {
    final next = <Span>[];
    for (final f in out) {
      if (!f.overlaps(t)) {
        next.add(f);
        continue;
      }
      if (t.start > f.start) next.add(Span(f.start, t.start));
      if (t.end < f.end) next.add(Span(t.end, f.end));
    }
    out = next;
  }
  return out.where((s) => s.length >= min).toList()..sort((a, b) => a.start.compareTo(b.start));
}

String _habitKey(TimeEntry e) => '${e.description.trim().toLowerCase()}\u0000${e.projectId ?? ''}\u0000${e.taskId ?? ''}';

/// Empreinte stable d'une chaîne (FNV-1a 32 bits) : la clé d'une habitude ignorée survit au redémarrage.
String _fnv(String text) {
  var h = 0x811c9dc5;
  for (final c in text.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(36);
}

/// Calcule la journée [day] : propositions tirées de la présence sur un chantier ([presence], détectée par le
/// téléphone), des sessions de Claude ([agentEntries], celles des agents du pilote), de l'agenda, des commits, des
/// habitudes ([history] : ses entrées des semaines précédentes) et du [planning], dans cet ordre de priorité, sur
/// les créneaux que [mine] (ses entrées du jour) laisse vides. [dismissed] : clés ignorées.
DayPlan planDay({
  required DateTime day,
  required DateTime now,
  required List<TimeEntry> mine,
  required List<TimeEntry> history,
  List<TimeEntry> agentEntries = const [],
  List<ScheduleAssignment> planning = const [],
  Set<String> dismissed = const {},
  TypicalDay? typical,
  List<CalendarEvent> calendar = const [],
  List<CommitTrace> commits = const [],
  List<SiteVisit> presence = const [],
  String? presenceRounding,
  ({String? projectId, String? taskId})? Function(String text)? guessProject,
}) {
  final d0 = _midnight(day);
  final isToday = d0 == _midnight(now);
  final isFuture = d0.isAfter(_midnight(now));
  final nowMin = minuteOf(now, d0);
  typical ??= typicalDay(history.where((e) => e.startAt.toLocal().isBefore(d0)).toList(), now);
  final busy = [for (final e in mine) ?spanOf(e, d0, now)]..sort((a, b) => a.start.compareTo(b.start));

  // Un week-end sans habitude de travail ne se remplit pas ; un jour à venir non plus.
  var windows = _workday(d0) && !isFuture ? typical.windows : <Span>[];
  if (isToday) windows = [for (final w in windows) if (w.start < nowMin) Span(w.start, w.end < nowMin ? w.end : nowMin)];

  var free = subtract(windows, busy, min: _minDraft);
  final drafts = <Draft>[];
  void place(Draft d) {
    if (dismissed.contains(d.key)) return;
    drafts.add(d);
    free = subtract(free, [d.span], min: _minDraft);
  }

  // 0. Présence chantier : de l'arrivée au départ, hors pause de midi et hors temps déjà saisi, même en dehors de la
  // journée type ; à 5 minutes près, ou calé sur la journée type à moins de 30 minutes (règle de l'entreprise).
  // Description et tâche : celles de sa dernière entrée sur ce projet.
  final snapToTypical = presenceRounding == 'planning';
  for (final v in presence) {
    if (_midnight(v.arrived) != d0 || isFuture) continue;
    final arrived = minuteOf(v.arrived, d0), left = v.left == null ? null : minuteOf(v.left!, d0);
    var a = _snap(arrived), b = _snap(left ?? minuteOf(isToday ? now : v.lastSeen, d0));
    if (snapToTypical && (a - typical.start).abs() <= 30) a = typical.start;
    if (snapToTypical && (b - typical.end).abs() <= 30) b = typical.end;
    if (isToday && b > nowMin) b = nowMin;
    if (b - a < _minDraft) continue;
    TimeEntry? sample;
    for (final e in history) {
      if (e.projectId == v.projectId && (sample == null || e.startAt.isAfter(sample.startAt))) sample = e;
    }
    final rounded = snapToTypical && (a == typical.start || b == typical.end);
    for (final piece in subtract([Span(a, b)], [?typical.lunch, ...busy], min: _minDraft)) {
      place(Draft(
        key: 'site:${v.projectId}:${piece.start}',
        source: DraftSource.presence,
        span: piece,
        description: sample?.description ?? '',
        projectId: v.projectId,
        taskId: sample?.taskId,
        reasons: [
          DraftReason(ReasonKind.presence, a: arrived, b: left ?? -1),
          if (rounded) const DraftReason(ReasonKind.presenceRounded),
        ],
      ));
    }
  }

  // 1. Claude travaillait : le pilote suivait la session (prompts, relecture).
  for (final a in [...agentEntries]..sort((x, y) => x.startAt.compareTo(y.startAt))) {
    final sp = spanOf(a, d0, now);
    if (sp == null) continue;
    for (final f in [...free]) {
      final piece = f.intersect(sp);
      if (piece == null || piece.length < _minDraft) continue;
      place(Draft(
        key: 'claude:${a.id}:${piece.start}',
        source: DraftSource.claude,
        span: piece,
        description: a.description,
        projectId: a.projectId,
        taskId: a.taskId,
        reasons: [DraftReason(ReasonKind.claudeSession, a: sp.start, b: sp.end), const DraftReason(ReasonKind.claudePilot)],
      ));
    }
  }

  // 2. Agenda : réunions et rendez-vous, sur les créneaux de travail encore libres ; projet deviné d'après le titre.
  for (final ev in calendar) {
    final sp = Span(math.max(0, minuteOf(ev.start, d0)), math.min(1440, minuteOf(ev.end, d0)));
    if (sp.length <= 0 || sp.length > 600) continue;
    final guess = guessProject?.call(ev.title);
    for (final f in [...free]) {
      final piece = f.intersect(sp);
      if (piece == null || piece.length < _minDraft) continue;
      place(Draft(
        key: 'cal:${ev.id}:${piece.start}',
        source: DraftSource.calendar,
        span: piece,
        description: ev.title,
        projectId: guess?.projectId,
        taskId: guess?.taskId,
        reasons: [DraftReason(ReasonKind.calendar, a: sp.start, b: sp.end)],
      ));
    }
  }

  // 3. Commits : par dépôt, les commits à moins de 90 minutes les uns des autres forment une séance de travail,
  // de 30 minutes avant le premier jusqu'au dernier ; description : le message du dernier, projet : celui du dépôt.
  final byRepo = <String, List<CommitTrace>>{};
  for (final c in [...commits]..sort((x, y) => x.at.compareTo(y.at))) {
    (byRepo[c.repository] ??= []).add(c);
  }
  byRepo.forEach((repo, list) {
    final clusters = <List<CommitTrace>>[];
    for (final c in list) {
      if (clusters.isNotEmpty && c.at.difference(clusters.last.last.at).inMinutes <= 90) {
        clusters.last.add(c);
      } else {
        clusters.add([c]);
      }
    }
    for (final cl in clusters) {
      final first = minuteOf(cl.first.at, d0), last = minuteOf(cl.last.at, d0);
      final sp = Span(math.max(0, first - 30), math.min(1440, math.max(last, first - 30 + _minDraft)));
      final subject = cl.lastWhere((c) => c.subject.trim().isNotEmpty, orElse: () => cl.last).subject.trim();
      for (final f in [...free]) {
        final piece = f.intersect(sp);
        if (piece == null || piece.length < _minDraft) continue;
        place(Draft(
          key: 'git:${cl.first.sha.length > 12 ? cl.first.sha.substring(0, 12) : cl.first.sha}:${piece.start}',
          source: DraftSource.commits,
          span: piece,
          description: subject.isEmpty ? repo : subject,
          projectId: cl.first.projectId,
          reasons: [DraftReason(ReasonKind.commits, count: cl.length, a: first, b: last, text: repo)],
        ));
      }
    }
  });

  // 4. Habitudes : même activité, à la même heure, la plupart des jours (ou le même jour de la semaine).
  final loggedKeys = {for (final e in mine) _habitKey(e)};
  final past = history.where((e) => e.endAt != null && e.startAt.toLocal().isBefore(d0)).toList();
  final workdays = {for (final e in past) if (_workday(_midnight(e.startAt.toLocal()))) dayKey(e.startAt.toLocal())}.toList()..sort();
  final lastWorkdays = workdays.reversed.take(10).toSet();
  final sameWeekdays = [for (var i = 1; i <= 4; i++) dayKey(addDays(d0, -7 * i))];
  final groups = <String, List<TimeEntry>>{};
  for (final e in past) {
    if (e.projectId == null && e.description.trim().isEmpty) continue;
    (groups[_habitKey(e)] ??= []).add(e);
  }
  final habits = <({String key, TimeEntry sample, int start, int length, DraftReason reason})>[];
  groups.forEach((k, list) {
    if (loggedKeys.contains(k)) return;
    final days = {for (final e in list) dayKey(e.startAt.toLocal())};
    final weekdayHits = sameWeekdays.where(days.contains).length;
    final dailyHits = lastWorkdays.where(days.contains).length;
    DraftReason? reason;
    List<TimeEntry> basis;
    if (weekdayHits >= 3) {
      basis = list.where((e) => sameWeekdays.contains(dayKey(e.startAt.toLocal()))).toList();
      reason = DraftReason(ReasonKind.habitWeekday, count: weekdayHits, of: 4);
    } else if (lastWorkdays.length >= 5 && dailyHits * 10 >= lastWorkdays.length * 6) {
      basis = list.where((e) => lastWorkdays.contains(dayKey(e.startAt.toLocal()))).toList();
      reason = DraftReason(ReasonKind.habitDaily, count: dailyHits, of: lastWorkdays.length);
    } else {
      return;
    }
    final starts = [for (final e in basis) minuteOf(e.startAt, e.startAt.toLocal())];
    final lengths = [for (final e in basis) e.endAt!.difference(e.startAt).inMinutes];
    final start = _snap(_median(starts));
    habits.add((key: k, sample: basis.last, start: start, length: _median(lengths),
        reason: DraftReason(reason.kind, count: reason.count, of: reason.of, a: start)));
  });
  habits.sort((a, b) => a.start.compareTo(b.start));
  for (final h in habits) {
    final want = Span(h.start, h.start + h.length);
    Span? best;
    for (final f in free) {
      final piece = f.intersect(want);
      if (piece != null && (best == null || piece.length > best.length)) best = piece;
    }
    if (best == null || best.length * 2 < h.length || best.length < _minDraft) continue;
    place(Draft(
      key: 'habit:${_fnv(h.key)}:${dayKey(d0)}',
      source: DraftSource.habit,
      span: best,
      description: h.sample.description,
      projectId: h.sample.projectId,
      taskId: h.sample.taskId,
      reasons: [h.reason],
    ));
  }

  // 5. Planning : le reste des heures prévues sur le projet, dans les créneaux libres restants.
  final dateKey = dayKey(d0);
  for (final a in planning) {
    if (a.projectId == null || a.startDate.compareTo(dateKey) > 0 || a.endDate.compareTo(dateKey) < 0) continue;
    final planned = (a.hoursPerDay * 60).round();
    final already = [for (final e in mine) if (e.projectId == a.projectId) ?spanOf(e, d0, now)].fold(0, (s, x) => s + x.length);
    final proposed = drafts.where((x) => x.projectId == a.projectId).fold(0, (s, x) => s + x.span.length);
    var left = planned - already - proposed;
    for (final f in [...free]) {
      if (left < _minDraft) break;
      final piece = Span(f.start, f.start + (f.length < left ? f.length : left));
      if (piece.length < _minDraft) continue;
      place(Draft(
        key: 'plan:${a.id}:$dateKey:${piece.start}',
        source: DraftSource.planning,
        span: piece,
        description: a.note ?? '',
        projectId: a.projectId,
        reasons: [
          DraftReason(ReasonKind.planned, count: planned),
          if (already > 0) DraftReason(ReasonKind.alreadyLogged, count: already),
        ],
      ));
      left -= piece.length;
    }
  }

  drafts.sort((a, b) => a.span.start.compareTo(b.span.start));
  return DayPlan(
    typical: typical,
    windows: windows,
    busy: busy,
    drafts: drafts,
    gaps: subtract(free, const [], min: _minGap),
  );
}
