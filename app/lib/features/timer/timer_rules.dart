import '../../core/l10n.dart';
import '../../data/drift/database.dart';

/// Règles de saisie du workspace pour démarrer ou arrêter un chronomètre :
/// message à afficher, ou null si rien ne bloque.
/// Partagées par la barre du chronomètre et la barre de menus macOS.
String? timerRuleViolation(AppLocalizations l, Workspace ws, {required String description, required String? projectId}) {
  if (ws.requireProject && projectId == null) return l.projectRequired;
  if (ws.requireDescription && description.trim().isEmpty) return l.descriptionRequired;
  return null;
}
