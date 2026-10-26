/// Saisie express (plans/13-ux-moderne.md, lot 3) : une ligne en français courant (ou en anglais) devient une entrée.
/// « 1h20 point hebdo interne », « 9h-10h30 maquettes boulangerie hier », « 45min appel dupuis #urgent ».
/// Analyse pure, sans base ni widget : la page « Aujourd'hui » place ensuite l'entrée dans un créneau vide.
library;

class QuickProject {
  const QuickProject(this.id, this.name, {this.client});
  final String id;
  final String name;
  final String? client;
}

class QuickTask {
  const QuickTask(this.id, this.name, this.projectId);
  final String id;
  final String name;
  final String projectId;
}

class QuickTag {
  const QuickTag(this.id, this.name);
  final String id;
  final String name;
}

/// Ce que la ligne dit. [startMinute] et [endMinute] : plage explicite (minutes depuis minuit) ; sinon [minutes].
class QuickEntry {
  const QuickEntry({
    required this.dayOffset,
    required this.description,
    this.minutes,
    this.startMinute,
    this.endMinute,
    this.projectId,
    this.taskId,
    this.tagIds = const [],
    this.billable,
  });

  /// 0 aujourd'hui, -1 hier…
  final int dayOffset;
  final String description;
  final int? minutes;
  final int? startMinute;
  final int? endMinute;
  final String? projectId;
  final String? taskId;
  final List<String> tagIds;

  /// null : le réglage du projet.
  final bool? billable;

  bool get hasRange => startMinute != null && endMinute != null;
  int? get duration => hasRange ? endMinute! - startMinute! : minutes;

  /// De quoi enregistrer : une durée, et un projet ou une description.
  bool get isComplete => (duration ?? 0) > 0 && (projectId != null || description.isNotEmpty);
}

String fold(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    b.write(i < 0 ? c : to[i]);
  }
  return b.toString();
}

const _weekdays = {
  'lundi': 1, 'mardi': 2, 'mercredi': 3, 'jeudi': 4, 'vendredi': 5, 'samedi': 6, 'dimanche': 7,
  'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
};

final _range = RegExp(r'(?<![\d:])(\d{1,2})(?:[h:](\d{2}))?h?\s*(?:-|–|à|a|to|→)\s*(\d{1,2})(?:[h:](\d{2}))?h?(?![\d:])');
final _hours = RegExp(r'(?<![\d:])(\d{1,2}(?:[.,]\d{1,2})?)\s*h(?:\s*(\d{1,2}))?(?![\da-z])');
final _clock = RegExp(r'(?<![\d:])(\d{1,2}):(\d{2})(?![\d:])');
final _mins = RegExp(r'(?<![\d:])(\d{1,3})\s*(?:min|mn|m)(?![a-z])');

/// Analyse [text] ; [weekday] : jour de la semaine d'aujourd'hui (1 = lundi), pour « lundi », « mardi »…
QuickEntry? parseQuickEntry(
  String text, {
  required int weekday,
  List<QuickProject> projects = const [],
  List<QuickTask> tasks = const [],
  List<QuickTag> tags = const [],
}) {
  var rest = text.trim();
  if (rest.isEmpty) return null;
  // Les motifs se cherchent dans le texte replié (sans accents ni majuscules), de même longueur que l'original.
  String low() => fold(rest);
  void cut(Match m) => rest = '${rest.substring(0, m.start)} ${rest.substring(m.end)}';

  int? start, end, minutes;
  final r = _range.firstMatch(low());
  final rangeOk = r != null && (r.group(0)!.contains(RegExp('[h:]')) || int.parse(r.group(3)!) <= 24);
  if (r != null && rangeOk) {
    final s = int.parse(r.group(1)!) * 60 + int.parse(r.group(2) ?? '0');
    final e = int.parse(r.group(3)!) * 60 + int.parse(r.group(4) ?? '0');
    if (s < 1440 && e <= 1440 && e > s) {
      start = s;
      end = e;
      cut(r);
    }
  }
  if (start == null) {
    final h = _hours.firstMatch(low());
    final c = _clock.firstMatch(low());
    final m = _mins.firstMatch(low());
    if (h != null) {
      final value = double.parse(h.group(1)!.replaceAll(',', '.'));
      minutes = (value * 60).round() + int.parse(h.group(2) ?? '0');
      cut(h);
    } else if (c != null) {
      minutes = int.parse(c.group(1)!) * 60 + int.parse(c.group(2)!);
      cut(c);
    } else if (m != null) {
      minutes = int.parse(m.group(1)!);
      cut(m);
    }
  }

  var dayOffset = 0;
  final words = rest.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final kept = <String>[];
  final tagIds = <String>[];
  bool? billable;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final f = fold(w).replaceAll(RegExp(r'[.,;!?]+$'), '');
    if (f == 'aujourd\'hui' || f == 'aujourd’hui' || f == 'auj' || f == 'today') {
      dayOffset = 0;
    } else if (f == 'hier' || f == 'yesterday') {
      dayOffset = -1;
    } else if (f == 'avant-hier') {
      dayOffset = -2;
    } else if (_weekdays.containsKey(f)) {
      final back = (weekday - _weekdays[f]!) % 7;
      dayOffset = -back;
    } else if (f == '#nf' || f == 'nonfacturable' || (f == 'non' && i + 1 < words.length && fold(words[i + 1]).startsWith('factur'))) {
      billable = false;
      if (f == 'non') i++;
    } else if (f == 'facturable' || f == '#f') {
      billable = true;
    } else if (f.startsWith('#') && f.length > 1) {
      final tag = tags.where((t) => fold(t.name) == f.substring(1)).firstOrNull;
      if (tag != null) tagIds.add(tag.id);
    } else {
      kept.add(w);
    }
  }

  // Projet et tâche : les mots (au moins 3 lettres) qui commencent un mot du nom ; pas au milieu (« appel » ≠ « Rappels »).
  final keys = [for (final w in kept) fold(w).replaceAll(RegExp(r'[^a-z0-9-]'), '')].where((w) => w.length >= 3).toList();
  int score(String name) {
    final parts = fold(name).split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty).toList();
    return keys.where((k) => parts.any((p) => p.startsWith(k))).fold(0, (a, k) => a + k.length);
  }

  QuickProject? project;
  var best = 0;
  for (final p in projects) {
    final s = [score(p.name), if (p.client != null) score(p.client!)].reduce((a, b) => a > b ? a : b);
    if (s > best) {
      best = s;
      project = p;
    }
  }
  QuickTask? task;
  var bestTask = 0;
  for (final t in tasks) {
    if (project != null && t.projectId != project.id) continue;
    final s = score(t.name);
    if (s > bestTask) {
      bestTask = s;
      task = t;
    }
  }
  if (project == null && task != null) project = projects.where((p) => p.id == task!.projectId).firstOrNull;

  // Les mots qui ne servaient qu'à désigner le projet ou le client sortent de la description ; ceux de la tâche restent.
  bool namesProject(String w) {
    if (project == null) return false;
    final k = fold(w).replaceAll(RegExp(r'[^a-z0-9-]'), '');
    if (k.length < 3) return false;
    final taskParts = task == null ? const <String>[] : fold(task.name).split(RegExp(r'[^a-z0-9]+'));
    if (taskParts.any((p) => p.startsWith(k))) return false;
    final parts = [
      ...fold(project.name).split(RegExp(r'[^a-z0-9]+')),
      if (project.client != null) ...fold(project.client!).split(RegExp(r'[^a-z0-9]+')),
    ];
    return parts.any((p) => p.isNotEmpty && p.startsWith(k));
  }

  var description = [for (final w in kept) if (!namesProject(w)) w].join(' ').trim();
  description = description.replaceAll(RegExp(r'^[,;:\-–]+|[,;:\-–]+$'), '').trim();
  if (description.isEmpty && task != null) description = task.name;
  if (description.isNotEmpty) description = description[0].toUpperCase() + description.substring(1);

  return QuickEntry(
    dayOffset: dayOffset,
    description: description,
    minutes: minutes,
    startMinute: start,
    endMinute: end,
    projectId: project?.id,
    taskId: task?.id,
    tagIds: tagIds,
    billable: billable,
  );
}
