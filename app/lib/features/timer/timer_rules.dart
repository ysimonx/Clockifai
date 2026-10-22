import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/di.dart';
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

/// Un seul chronomètre en cours par tâche ([sameTimerTarget]) : message, ou null si rien ne tourne déjà.
String? alreadyRunningViolation(AppLocalizations l, Iterable<TimeEntry> running,
    {required String description, required String? projectId, required String? taskId}) {
  final same = running.any((r) => sameTimerTarget(r, description: description, projectId: projectId, taskId: taskId));
  return same ? l.timerAlreadyRunningOnTask : null;
}

/// Arrête un chronomètre en cours après les règles du workspace (message sinon).
Future<void> stopTimer(BuildContext context, TimeEntry entry) async {
  final ws = context.read<SessionController>().workspace!;
  final blocked = timerRuleViolation(context.l10n, ws, description: entry.description, projectId: entry.projectId);
  if (blocked != null) return showSnack(context, blocked);
  await entriesRepo.stop(entry.id);
}
