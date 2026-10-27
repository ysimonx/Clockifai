import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../timer/timer_rules.dart' show newEntryViolation;

/// Une entrée terminée de la personne connectée, avant enregistrement.
class OwnEntry {
  const OwnEntry({required this.start, required this.end, this.description = '', this.projectId, this.taskId});
  final DateTime start;
  final DateTime end;
  final String description;
  final String? projectId;
  final String? taskId;
}

/// Enregistre [entries] pour la personne connectée, facturables et au taux du projet comme toute saisie, après les
/// règles du workspace et les périodes verrouillées ou approuvées ([newEntryViolation]) : un blocage s'affiche et rien
/// n'est écrit. Renvoie les ids, ou null si une règle bloque. Partagé par « Aujourd'hui », la feuille « + » et le
/// récapitulatif de fin de journée.
Future<List<String>?> createOwnEntries(BuildContext context, List<OwnEntry> entries) async {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final me = session.userId!;
  for (final e in entries) {
    final blocked = await newEntryViolation(l, session,
        userId: me, day: e.start, description: e.description, projectId: e.projectId);
    if (blocked != null) {
      if (context.mounted) showSnack(context, blocked);
      return null;
    }
  }
  return [
    for (final e in entries)
      await entriesRepo.createManual(
        workspaceId: session.workspaceId!,
        userId: me,
        start: e.start,
        end: e.end,
        createdBy: me,
        draft: EntryDraft(
          description: e.description.trim(),
          projectId: e.projectId,
          taskId: e.taskId,
          billable: catalog.billableFor(projectId: e.projectId, userId: me),
          hourlyRateCents: catalog.rateFor(projectId: e.projectId, userId: me),
        ),
      ),
  ];
}
