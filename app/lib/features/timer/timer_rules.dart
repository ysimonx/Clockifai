import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/di.dart';
import '../../core/format.dart' show startOfDay;
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';

/// Règles de saisie du workspace pour démarrer ou arrêter un chronomètre :
/// message à afficher, ou null si rien ne bloque.
/// Partagées par la barre du chronomètre, la liste des entrées et la barre de menus macOS.
String? timerRuleViolation(AppLocalizations l, Workspace ws, {required String description, required String? projectId}) {
  if (ws.requireProject && projectId == null) return l.projectRequired;
  if (ws.requireDescription && description.trim().isEmpty) return l.descriptionRequired;
  return null;
}

/// Ce qui empêche d'ajouter une entrée de [userId] le jour [day] : règles du workspace, puis, hors admins, période
/// verrouillée ou déjà approuvée (le serveur refuserait). Message, ou null si rien ne bloque. Partagé par
/// « Aujourd'hui », la saisie express et le récapitulatif de fin de journée.
Future<String?> newEntryViolation(AppLocalizations l, SessionController session,
    {required String userId, required DateTime day, required String description, required String? projectId}) async {
  final ws = session.workspace!;
  final rule = timerRuleViolation(l, ws, description: description, projectId: projectId);
  if (rule != null || session.isAdmin) return rule;
  if (inLockedPeriod(session, startOfDay(day))) return l.periodLocked;
  if (await modulesRepo.isDayApproved(ws.id, userId, day)) return l.periodApproved;
  return null;
}

/// Un seul chronomètre en cours par tâche ([sameTimerTarget]) : message, ou null si rien ne tourne déjà.
String? alreadyRunningViolation(AppLocalizations l, Iterable<TimeEntry> running,
    {required String description, required String? projectId, required String? taskId}) {
  final same = running.any((r) => sameTimerTarget(r, description: description, projectId: projectId, taskId: taskId));
  return same ? l.timerAlreadyRunningOnTask : null;
}

/// Relance [row] en nouveau chronomètre (« Continuer ») : description, projet, tâche, tags, facturation et taux
/// repris. Message si un chronomètre tourne déjà sur cette tâche, sinon null. Partagé par la liste des entrées et la
/// barre de menus du Mac.
Future<String?> restartEntry(AppLocalizations l, EntryRow row, {required int maxRunning}) async {
  final e = row.entry;
  final running = await entriesRepo.watchRunningAll(e.workspaceId, e.userId).first;
  final blocked = alreadyRunningViolation(l, running, description: e.description, projectId: e.projectId, taskId: e.taskId);
  if (blocked != null) return blocked;
  await entriesRepo.start(
    workspaceId: e.workspaceId,
    userId: e.userId,
    draft: EntryDraft(
      description: e.description,
      projectId: e.projectId,
      taskId: e.taskId,
      billable: e.billable,
      hourlyRateCents: e.hourlyRateCents,
      tagIds: row.tagIds,
    ),
    maxRunning: maxRunning,
  );
  return null;
}

/// Arrête un chronomètre en cours après les règles du workspace (message sinon).
Future<void> stopTimer(BuildContext context, TimeEntry entry) async {
  final ws = context.read<SessionController>().workspace!;
  final blocked = timerRuleViolation(context.l10n, ws, description: entry.description, projectId: entry.projectId);
  if (blocked != null) return showSnack(context, blocked);
  await entriesRepo.stop(entry.id);
}
