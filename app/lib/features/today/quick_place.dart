import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/text_search.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import 'day_plan.dart';
import 'quick_entry.dart';

/// Saisie express (plans/13-ux-moderne.md, lot 3) : de la ligne analysée à l'entrée enregistrée. Sert à la page
/// « Aujourd'hui » et à la barre de menus du Mac.
class QuickSlot {
  const QuickSlot(this.day, this.span, {this.inGap = false});
  final DateTime day;
  final Span span;

  /// Rangée dans un créneau vide (sinon : plage dite, à la place d'une proposition, ou après la dernière entrée).
  final bool inGap;
}

/// Analyse [text] avec le référentiel : projets, tâches et tags actifs.
QuickEntry? parseQuick(String text, CatalogController catalog, DateTime now) {
  final projects = catalog.activeProjects;
  final open = {for (final p in projects) p.id};
  return parseQuickEntry(
    text,
    weekday: now.weekday,
    projects: [for (final p in projects) QuickProject(p.id, p.name, client: catalog.client(p.clientId)?.name)],
    // Tâches des projets actifs seulement : celle d'un projet archivé donnerait une entrée sans projet.
    tasks: [
      for (final t in catalog.tasks)
        if (t.status == 'active' && open.contains(t.projectId)) QuickTask(t.id, t.name, t.projectId),
    ],
    tags: [for (final t in catalog.activeTags) QuickTag(t.id, t.name)],
  );
}

/// Où ranger [q] : sa plage, sinon le premier créneau vide assez grand de son jour, en laissant d'abord en place les
/// propositions affichées ce jour-là ([proposedOn]), puis à leur place, sinon après la dernière entrée du jour.
/// [entries] : celles de la personne, ce jour-là et les semaines d'avant (journée type).
/// [typical] : la journée type du profil, si elle est réglée.
QuickSlot? placeQuick(QuickEntry q,
    {required DateTime now, required List<TimeEntry> entries, TypicalDay? typical, List<Span> Function(DateTime day)? proposedOn}) {
  final day = addDays(now, q.dayOffset);
  if (q.hasRange) return QuickSlot(day, Span(q.startMinute!, q.endMinute!));
  final d = q.minutes;
  if (d == null || d <= 0) return null;
  final end = addDays(day, 1);
  final plan = planDay(
    day: day,
    now: now,
    mine: [
      for (final e in entries)
        if (!e.startAt.toLocal().isBefore(day) && e.startAt.toLocal().isBefore(end)) e,
    ],
    history: [
      for (final e in entries)
        if (e.startAt.toLocal().isBefore(day)) e,
    ],
    typical: typical,
  );
  Span? fit(List<Span> taken) => subtract(plan.windows, taken, min: 5).where((g) => g.length >= d).firstOrNull;
  if (fit([...plan.busy, ...?proposedOn?.call(day)]) case final g?) return QuickSlot(day, Span(g.start, g.start + d), inGap: true);
  if (fit(plan.busy) case final g?) return QuickSlot(day, Span(g.start, g.start + d));
  final from = plan.busy.isEmpty ? plan.typical.start : plan.busy.map((s) => s.end).reduce(math.max);
  return QuickSlot(day, Span(from, math.min(1440, from + d)));
}

/// Enregistre [q] à [slot] (facturation et taux du projet, sauf « facturable » ou « non facturable » dans la ligne) ;
/// renvoie l'id de l'entrée.
Future<String> saveQuick(QuickEntry q, QuickSlot slot,
        {required CatalogController catalog, required String workspaceId, required String userId}) =>
    entriesRepo.createManual(
      workspaceId: workspaceId,
      userId: userId,
      start: atMinute(slot.day, slot.span.start),
      end: atMinute(slot.day, slot.span.end),
      createdBy: userId,
      draft: EntryDraft(
        description: q.description,
        projectId: q.projectId,
        taskId: q.taskId,
        billable: q.billable ?? catalog.billableFor(projectId: q.projectId, userId: userId),
        hourlyRateCents: catalog.rateFor(projectId: q.projectId, userId: userId),
        tagIds: q.tagIds,
      ),
    );

/// « Ajouté : Réunion · Aujourd'hui, 10:30 → 11:50 ».
String quickAddedMessage(BuildContext context, QuickEntry q, QuickSlot slot, CatalogController catalog, DateTime now) {
  final l = context.l10n;
  return l.quickAdded(q.description.isEmpty ? (catalog.project(q.projectId)?.name ?? '') : q.description,
      dayLabel(context, slot.day, today: l.today, yesterday: l.yesterday, now: now), '${hm(slot.span.start)} → ${hm(slot.span.end)}');
}

/// Ce que la ligne a donné, en morceaux courts (aperçu de la barre de menus).
List<String> quickSummary(BuildContext context, QuickEntry q, QuickSlot? slot, CatalogController catalog, String userId, DateTime now) {
  final l = context.l10n;
  final project = catalog.project(q.projectId);
  final task = catalog.task(q.taskId);
  return [
    q.duration == null ? l.quickDurationMissing : formatHm(q.duration! * 60),
    if (project != null) [project.name, ?catalog.taskPath(q.taskId)].join(' — ') else if (q.description.isEmpty) l.quickProjectMissing,
    if (q.description.isNotEmpty && fold(q.description) != fold(task?.name ?? '')) '« ${q.description} »',
    for (final id in q.tagIds) '#${catalog.tag(id)?.name ?? ''}',
    if (slot != null)
      '${dayLabel(context, slot.day, today: l.today, yesterday: l.yesterday, now: now)} ${hm(slot.span.start)} → ${hm(slot.span.end)}',
    if (!(q.billable ?? catalog.billableFor(projectId: q.projectId, userId: userId))) l.nonBillable,
  ];
}
