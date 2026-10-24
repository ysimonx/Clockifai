import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/drift/database.dart';
import 'catalog.dart';
import 'session.dart';

/// Droits « équipe » de l'utilisateur connecté dans le workspace courant.
///
/// Reproduit les règles serveur (migration 0009 : `manages`, `can_edit_others_time`,
/// `can_decide_time_off`) pour l'affichage uniquement : la RLS reste la seule vraie barrière.
class TeamRights {
  TeamRights({
    required this.me,
    required this.role,
    required this.timeForOthers,
    required this.members,
    required this.managed,
    this.agentsSeen = const {},
  });

  /// Dans `build` : se reconstruit quand la session ou le référentiel change.
  factory TeamRights.of(BuildContext context) =>
      TeamRights.from(context.watch<SessionController>(), context.watch<CatalogController>());

  /// Hors `build` (gestionnaires d'événements).
  factory TeamRights.read(BuildContext context) =>
      TeamRights.from(context.read<SessionController>(), context.read<CatalogController>());

  factory TeamRights.from(SessionController session, CatalogController catalog) => TeamRights(
        me: session.userId ?? '',
        role: session.role,
        timeForOthers: session.workspace?.timeForOthers,
        members: catalog.members,
        managed: catalog.managedBy(session.userId),
        agentsSeen: catalog.agentsSeenBy(session.userId),
      );

  final String me;
  final String role;

  /// Paramètre du workspace : 'admins' (défaut) ou 'admins_and_team_managers'.
  final String? timeForOthers;
  final List<WorkspaceMember> members;

  /// Collaborateurs encadrés en tant que chef d'équipe (jamais soi-même, jamais un agent).
  final Set<String> managed;

  /// Agents Claude visibles hors rôle de manager : le sien, ceux des personnes encadrées (plan 10, D15).
  final Set<String> agentsSeen;

  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get isManager => isAdmin || role == 'manager';

  /// Encadre au moins une personne via un groupe ou une affectation directe.
  bool get isTeamManager => managed.isNotEmpty;

  /// Voit le temps d'autres personnes (manager+ : tout le workspace ; chef d'équipe : son périmètre).
  bool get seesTeam => isManager || isTeamManager;

  /// Voit au moins une autre personne : l'équipe, ou seulement son agent Claude (pilote).
  bool get seesOthers => seesTeam || agentsSeen.isNotEmpty;

  /// Lecture du temps de [userId] (serveur : `manages()`, dont les agents du périmètre).
  bool manages(String userId) => isManager || managed.contains(userId) || agentsSeen.contains(userId);

  bool _active(String userId) => members.any((m) => m.userId == userId && m.status == 'active');

  bool isAgent(String userId) => members.any((m) => m.userId == userId && m.kind == 'agent');

  /// Pilote de l'agent [userId] (serveur : `pilots_agent`).
  bool pilots(String userId) => members.any((m) => m.userId == userId && m.kind == 'agent' && m.agentOwnerId == me);

  /// Modifier ou supprimer les entrées de [userId]. Le pilote corrige celles de son agent (D15).
  bool canEditTimeOf(String userId) =>
      userId == me ||
      isAdmin ||
      pilots(userId) ||
      (timeForOthers == 'admins_and_team_managers' && manages(userId) && _active(userId));

  /// Créer du temps pour [userId] : jamais pour un agent, dont seul le serveur écrit les entrées (D15).
  bool canCreateTimeFor(String userId) => !isAgent(userId) && canEditTimeOf(userId);

  /// Personnes dont on consulte le temps : soi d'abord, puis l'équipe encadrée et les agents visibles.
  List<WorkspaceMember> get visibleMembers => _sorted(members.where((m) => m.userId == me || manages(m.userId)));

  /// Personnes pour qui on peut saisir du temps (soi compris, jamais un agent).
  List<WorkspaceMember> get editableMembers =>
      _sorted(members.where((m) => m.status == 'active' && canCreateTimeFor(m.userId)));

  bool get canEditOthers => editableMembers.any((m) => m.userId != me);

  /// Feuilles de temps : manager+ pour tout le monde, chef d'équipe pour son périmètre (jamais la sienne).
  /// Un agent n'en soumet pas.
  bool canApproveTimesheetOf(String userId) => !isAgent(userId) && manages(userId);

  /// Absences : manager+, ou chef d'équipe si la politique l'autorise.
  bool canDecideTimeOff(String userId, TimeOffPolicy? policy) =>
      isManager || (policy?.approvers == 'managers_and_team_managers' && managed.contains(userId));

  List<WorkspaceMember> _sorted(Iterable<WorkspaceMember> list) => list.toList()
    ..sort((a, b) {
      if (a.userId == me) return -1;
      if (b.userId == me) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
}
