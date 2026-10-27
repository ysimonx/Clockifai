import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/rate_change.dart';
import '../../core/widgets/teammates.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../settings/settings_page.dart' show roleLabel;
import '../time_entries/ai_usage.dart';

/// Membres du workspace : rôle, taux, activité de la semaine et chronomètre en cours ;
/// groupes d'utilisateurs et chefs d'équipe (plans/03-saisie-pour-autrui.md).
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  /// Fiche à montrer (`/team?member=…`, par exemple l'agent depuis Paramètres › Intégrations › Claude Code).
  final _focusKey = GlobalKey();
  String? _revealed;

  void _reveal(String? userId) {
    if (userId == null || userId == _revealed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _focusKey.currentContext;
      if (!mounted || card == null) return; // référentiel pas encore chargé : au prochain rendu
      _revealed = userId;
      Scrollable.ensureVisible(card, alignment: 0.3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final focus = GoRouterState.of(context).uri.queryParameters['member'];
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final rights = TeamRights.of(context);
    final ws = session.workspace!;
    final weekStart = startOfWeek(DateTime.now(), ws.weekStart);
    final humans = catalog.humans;
    final agents = catalog.agents;

    final membersTab = StreamBuilder<List<EntryRow>>(
      // Base locale : un chef d'équipe n'a reçu que son temps et celui de son périmètre.
      stream: entriesRepo.watchEntries(
        workspaceId: ws.id,
        userId: rights.seesOthers ? null : session.userId,
        from: weekStart,
        to: weekStart.add(const Duration(days: 7)),
        includeRunning: true,
      ),
      builder: (context, snap) {
        final rows = snap.data ?? const <EntryRow>[];
        final weekByUser = <String, int>{};
        // Usage IA de la semaine, par agent (plan 10, D17).
        final aiTokensByUser = <String, int>{};
        final aiCostByUser = <String, int>{};
        // Plusieurs chronomètres par membre si le workspace le permet (les plus récents d'abord).
        final runningByUser = <String, List<EntryRow>>{};
        for (final r in rows) {
          final u = r.entry.userId;
          weekByUser[u] = (weekByUser[u] ?? 0) + r.seconds;
          if (r.aiTokens > 0) aiTokensByUser[u] = (aiTokensByUser[u] ?? 0) + r.aiTokens;
          if (r.aiCostMicros != null) aiCostByUser[u] = (aiCostByUser[u] ?? 0) + r.aiCostMicros!;
          if (r.entry.endAt == null) (runningByUser[u] ??= []).add(r);
        }
        _reveal(focus);
        // Toutes les fiches construites (pas de ListView paresseuse), pour pouvoir amener [focus] à l'écran.
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!rights.seesTeam)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(l.teamMemberHint, style: Theme.of(context).textTheme.bodySmall),
              ),
            for (final m in [...humans, if (agents.isNotEmpty) null, ...agents])
              if (m == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.agents, style: Theme.of(context).textTheme.titleMedium),
                    Text(l.agentsHelp, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                )
              else
                Padding(
                  key: m.userId == focus ? _focusKey : null,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MemberCard(
                    member: m,
                    weekSeconds: weekByUser[m.userId] ?? 0,
                    weekAiTokens: aiTokensByUser[m.userId] ?? 0,
                    weekAiCostMicros: aiCostByUser[m.userId],
                    running: runningByUser[m.userId] ?? const [],
                    showActivity: m.userId == session.userId || rights.manages(m.userId),
                    highlighted: m.userId == focus,
                  ),
                ),
            if (session.isAdmin)
              _RemovedAgents(
                key: ValueKey('removed-agents-${ws.id}'),
                workspaceId: ws.id,
                agentIds: [for (final a in agents) a.userId].join(','),
              ),
          ]),
        );
      },
    );

    return PageScaffold(
      title: l.team,
      actions: [
        if (session.isAdmin)
          FilledButton.icon(onPressed: () => _invite(context), icon: const Icon(Icons.person_add_alt), label: Text(l.invite)),
      ],
      child: DefaultTabController(
        length: 2,
        child: Column(children: [
          TabBar(tabs: [
            Tab(text: l.members),
            Tab(text: '${l.groups} (${catalog.groups.length})'),
          ]),
          Expanded(child: TabBarView(children: [membersTab, const _GroupsTab()])),
        ]),
      ),
    );
  }

  Future<void> _invite(BuildContext context) async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final email = TextEditingController();
    var role = 'member';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.inviteMember),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: email, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: l.email)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: InputDecoration(labelText: l.role),
                items: [for (final r in const ['member', 'manager', 'admin']) DropdownMenuItem(value: r, child: Text(roleLabel(context, r)))],
                onChanged: (v) => setState(() => role = v!),
              ),
              const SizedBox(height: 12),
              Text(l.inviteHelp, style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.invite)),
          ],
        ),
      ),
    );
    if (ok != true || email.text.trim().isEmpty || !context.mounted) return;
    try {
      final res = await ServicesApi.post('/api/invitations', {
        'workspace_id': session.workspaceId,
        'email': email.text.trim(),
        'role': role,
      });
      if (!context.mounted) return;
      final link = res['invite_link'] as String?;
      if (link != null && res['emailed'] != true) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.inviteLinkTitle),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.inviteLinkMessage),
              const SizedBox(height: 12),
              SelectableText(link, style: Theme.of(ctx).textTheme.bodySmall),
            ]),
            actions: [
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: link)),
                child: Text(l.copy),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(l.close)),
            ],
          ),
        );
      } else {
        showSnack(context, l.invitationSent);
      }
    } on ServicesException catch (e) {
      if (context.mounted) showSnack(context, l.invitationFailed(e.message));
    } catch (e) {
      if (context.mounted) showSnack(context, l.invitationFailed('$e'));
    }
  }
}

/// Agents retirés (admins) : les membres retirés ne descendent pas vers l'appareil, le serveur les liste, et un
/// nouveau jeton ne les recrée pas (plan 10, D14). Hors ligne, la rubrique n'apparaît pas.
class _RemovedAgents extends StatefulWidget {
  const _RemovedAgents({super.key, required this.workspaceId, required this.agentIds});
  final String workspaceId;

  /// Agents présents sur l'appareil : quand la liste change (retrait, restauration), la rubrique se recharge.
  final String agentIds;

  @override
  State<_RemovedAgents> createState() => _RemovedAgentsState();
}

class _RemovedAgentsState extends State<_RemovedAgents> {
  List<Map<String, dynamic>> _agents = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_RemovedAgents old) {
    super.didUpdateWidget(old);
    if (old.agentIds == widget.agentIds) return;
    // Un retrait fait dans l'app part au serveur un peu après (file PowerSync) : on relit aussi plus tard.
    _load();
    Future<void>.delayed(const Duration(seconds: 3), _load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final res = await ServicesApi.get('/api/agents/removed', {'workspace_id': widget.workspaceId});
      if (mounted) setState(() => _agents = (res['agents'] as List).cast<Map<String, dynamic>>());
    } catch (_) {
      // Hors ligne : rien à proposer.
    }
  }

  Future<void> _restore(Map<String, dynamic> agent) async {
    final l = context.l10n;
    try {
      await ServicesApi.post('/api/agents/${agent['user_id']}/restore', {'workspace_id': widget.workspaceId});
      if (mounted) showSnack(context, l.agentRestored);
      await _load();
    } catch (_) {
      if (mounted) showSnack(context, l.onlineOnly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (_agents.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.removedAgents, style: theme.textTheme.titleMedium),
          Text(l.removedAgentsHelp, style: theme.textTheme.bodySmall),
        ]),
      ),
      for (final a in _agents)
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(Icons.smart_toy_outlined, color: theme.colorScheme.outline)),
            title: Text(a['display_name'] as String, style: TextStyle(color: theme.colorScheme.outline)),
            subtitle: Text(l.removedAgentOf(
              a['pilot_name'] as String? ?? '?',
              DateFormat.yMMMd(context.localeTag).format(DateTime.parse(a['removed_at'] as String).toLocal()),
            )),
            trailing: TextButton(onPressed: () => _restore(a), child: Text(l.restore)),
          ),
        ),
    ]);
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.weekSeconds,
    required this.running,
    required this.showActivity,
    this.weekAiTokens = 0,
    this.weekAiCostMicros,
    this.highlighted = false,
  });
  final WorkspaceMember member;
  final int weekSeconds;
  final int weekAiTokens;
  final int? weekAiCostMicros;
  final List<EntryRow> running;
  final bool showActivity;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.read<SessionController>();
    final catalog = context.watch<CatalogController>();
    final name = member.displayName.isEmpty ? (member.email ?? '?') : member.displayName;
    final inactive = member.status != 'active';
    // Agent Claude (plan 10) : ni rôle à choisir, ni e-mail (technique) à montrer, ni chef d'équipe.
    final agent = member.kind == 'agent';
    final ws = session.workspace!;
    final locale = context.localeTag;
    // Ce que le membre encadre : groupes entiers, puis personnes affectées directement.
    final manages = [
      for (final a in catalog.assignments.where((a) => a.managerId == member.userId))
        a.groupId != null
            ? catalog.groups.where((g) => g.id == a.groupId).firstOrNull?.name
            : memberName(catalog.memberOf(a.userId!)),
    ].whereType<String>().toList();
    final managers = [for (final m in catalog.managersOf(member.userId)) memberName(m)];

    return Card(
      color: highlighted ? theme.colorScheme.secondaryContainer : null,
      child: ListTile(
        leading: Badge(
          isLabelVisible: running.isNotEmpty,
          backgroundColor: AppColors.of(context).success,
          smallSize: 10,
          label: running.length > 1 ? Text('${running.length}') : null,
          child: CircleAvatar(child: agent ? const Icon(Icons.smart_toy_outlined) : Text(name[0].toUpperCase())),
        ),
        title: Row(children: [
          Flexible(child: Text(name, style: inactive ? TextStyle(color: theme.colorScheme.outline, decoration: TextDecoration.lineThrough) : null)),
          const SizedBox(width: 8),
          Chip(label: Text(agent ? l.agentBadge : roleLabel(context, member.role)), visualDensity: VisualDensity.compact),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (agent)
            Text(l.pilotedBy(memberName(catalog.memberOf(member.agentOwnerId ?? ''))))
          else if (member.email != null)
            Text(member.email!),
          if (showActivity) ...[
            for (final run in running)
              Row(children: [
                Icon(Icons.play_circle, size: 14, color: AppColors.of(context).success),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    [run.entry.description.isEmpty ? l.noDescription : run.entry.description, catalog.project(run.entry.projectId)?.name].whereType<String>().join(' · '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                ElapsedText(run.entry.startAt, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            Text('${l.thisWeek}: ${formatHm(weekSeconds)}'),
            if (weekAiTokens > 0) AiUsageText(tokens: weekAiTokens, costMicros: weekAiCostMicros),
          ],
          if (session.isManager && member.hourlyRateCents != null)
            Text('${l.hourlyRate}: ${formatMoney(member.hourlyRateCents! / 100, ws.currency, locale)}${l.perHour}'),
          if (manages.isNotEmpty)
            Text(l.managesLabel(manages.join(', ')), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
          if (managers.isNotEmpty)
            Text(l.managedByLabel(managers.join(', ')), style: theme.textTheme.bodySmall),
        ]),
        isThreeLine: true,
        trailing: session.isAdmin && member.userId != session.userId ? _AdminMenu(member: member) : null,
      ),
    );
  }
}

class _AdminMenu extends StatelessWidget {
  const _AdminMenu({required this.member});
  final WorkspaceMember member;

  bool get agent => member.kind == 'agent';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'member' || 'manager' || 'admin':
            await workspaceRepo.updateMember(member.id, WorkspaceMembersCompanion(role: Value(v)));
          case 'rate':
            await _editRates(context);
          case 'rename':
            final name = await promptText(context, title: l.rename, label: l.name, initial: member.displayName);
            if (name != null && name.trim().isNotEmpty) {
              await workspaceRepo.updateMember(member.id, WorkspaceMembersCompanion(displayName: Value(name.trim())));
            }
          case 'teamManager':
            await showDialog<void>(context: context, builder: (_) => _TeamManagerDialog(manager: member));
          case 'toggle':
            await workspaceRepo.updateMember(member.id, WorkspaceMembersCompanion(status: Value(member.status == 'active' ? 'inactive' : 'active')));
          case 'remove':
            final catalog = context.read<CatalogController>();
            final ok = await confirm(
              context,
              title: agent ? l.removeAgent : l.removeMember,
              message: agent ? l.removeAgentMessage(memberName(catalog.memberOf(member.agentOwnerId ?? ''))) : l.removeMemberMessage,
              confirmLabel: l.remove,
            );
            if (ok) {
              await workspaceRepo.updateMember(member.id, WorkspaceMembersCompanion(deletedAt: Value(nowUtc())));
            }
        }
      },
      itemBuilder: (_) => [
        if (member.role != 'owner' && !agent) ...[
          for (final r in const ['member', 'manager', 'admin'])
            CheckedPopupMenuItem(value: r, checked: member.role == r, child: Text(roleLabel(context, r))),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(value: 'rate', child: Text(l.editRates)),
        if (agent)
          PopupMenuItem(value: 'rename', child: Text(l.rename))
        else
          PopupMenuItem(value: 'teamManager', child: Text(l.teamManagerOf)),
        if (member.role != 'owner') ...[
          PopupMenuItem(value: 'toggle', child: Text(member.status == 'active' ? l.deactivate : l.activate)),
          PopupMenuItem(value: 'remove', child: Text(l.remove)),
        ],
      ],
    );
  }

  Future<void> _editRates(BuildContext context) async {
    final l = context.l10n;
    String fmt(int? c) => c == null ? '' : (c / 100).toStringAsFixed(2);
    int? parse(String s) {
      final v = double.tryParse(s.replaceAll(',', '.').trim());
      return v == null ? null : (v * 100).round();
    }

    final hourly = TextEditingController(text: fmt(member.hourlyRateCents));
    final cost = TextEditingController(text: fmt(member.costRateCents));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editRates),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: hourly, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.billableRate)),
            const SizedBox(height: 12),
            TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.costRate)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
        ],
      ),
    );
    if (ok != true) return;
    final rate = parse(hourly.text);
    await workspaceRepo.updateMember(
      member.id,
      WorkspaceMembersCompanion(hourlyRateCents: Value(rate), costRateCents: Value(parse(cost.text))),
    );
    if (rate == member.hourlyRateCents || !context.mounted) return;
    // Le taux du membre ne vaut que sur les projets sans taux.
    final catalog = context.read<CatalogController>();
    await offerRateChange(context,
        userId: member.userId,
        concerns: (e) => catalog.project(e.projectId)?.hourlyRateCents == null,
        rateFor: (_) => rate);
  }
}

/// Ce qu'encadre un chef d'équipe : groupes entiers et/ou personnes (admins).
class _TeamManagerDialog extends StatefulWidget {
  const _TeamManagerDialog({required this.manager});
  final WorkspaceMember manager;

  @override
  State<_TeamManagerDialog> createState() => _TeamManagerDialogState();
}

class _TeamManagerDialogState extends State<_TeamManagerDialog> {
  late final Set<String> _users;
  late final Set<String> _groups;

  @override
  void initState() {
    super.initState();
    final mine = context.read<CatalogController>().assignments.where((a) => a.managerId == widget.manager.userId);
    _users = {for (final a in mine) ?a.userId};
    _groups = {for (final a in mine) ?a.groupId};
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final others = catalog.humans.where((m) => m.userId != widget.manager.userId && m.status == 'active').toList();
    return AlertDialog(
      title: Text('${l.teamManagerOf} ${memberName(widget.manager)}'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 420,
        height: 480,
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l.teamManagerOfHelp, style: theme.textTheme.bodySmall),
          ),
          if (catalog.groups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(l.groups, style: theme.textTheme.titleSmall),
            ),
            for (final g in catalog.groups)
              CheckboxListTile(
                dense: true,
                value: _groups.contains(g.id),
                secondary: const Icon(Icons.group_work_outlined),
                title: Text(g.name),
                subtitle: Text(l.memberCount(catalog.membersOfGroup(g.id).length)),
                onChanged: (v) => setState(() => v == true ? _groups.add(g.id) : _groups.remove(g.id)),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(l.users, style: theme.textTheme.titleSmall),
          ),
          for (final m in others)
            CheckboxListTile(
              dense: true,
              value: _users.contains(m.userId),
              secondary: CircleAvatar(radius: 14, child: Text(memberName(m)[0].toUpperCase())),
              title: Text(memberName(m)),
              onChanged: (v) => setState(() => v == true ? _users.add(m.userId) : _users.remove(m.userId)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          onPressed: () async {
            await teamRepo.setManagerAssignments(
              workspaceId: widget.manager.workspaceId,
              managerId: widget.manager.userId,
              userIds: _users,
              groupIds: _groups,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Groupes d'utilisateurs : lecture pour tous, gestion par les admins.
class _GroupsTab extends StatelessWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final groups = catalog.groups;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (session.isAdmin)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.add), label: Text(l.newGroup)),
        ),
      if (groups.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: EmptyState(icon: Icons.group_work_outlined, title: l.noGroups, message: l.noGroupsMessage),
        ),
      for (final g in groups)
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.group_work_outlined)),
            title: Text(g.name),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.memberCount(catalog.membersOfGroup(g.id).length)),
              if (catalog.membersOfGroup(g.id).isNotEmpty)
                Text(catalog.membersOfGroup(g.id).map(memberName).join(', '), style: theme.textTheme.bodySmall),
              if (_managersOfGroup(catalog, g.id).isNotEmpty)
                Text(l.managedByLabel(_managersOfGroup(catalog, g.id).join(', ')),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
            ]),
            isThreeLine: true,
            onTap: session.isAdmin ? () => _editMembers(context, g) : null,
            trailing: session.isAdmin
                ? PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'members':
                          await _editMembers(context, g);
                        case 'rename':
                          final name = await promptText(context, title: l.groupName, label: l.name, initial: g.name);
                          if (name != null && name.trim().isNotEmpty) await teamRepo.renameGroup(g.id, name);
                        case 'delete':
                          if (await confirm(context, title: l.deleteGroup, message: l.deleteGroupMessage, confirmLabel: l.delete)) {
                            await teamRepo.deleteGroup(g.id);
                          }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'members', child: Text(l.groupMembers)),
                      PopupMenuItem(value: 'rename', child: Text(l.edit)),
                      PopupMenuItem(value: 'delete', child: Text(l.delete)),
                    ],
                  )
                : null,
          ),
        ),
    ]);
  }

  static List<String> _managersOfGroup(CatalogController catalog, String groupId) => [
        for (final a in catalog.assignments.where((a) => a.groupId == groupId)) memberName(catalog.memberOf(a.managerId)),
      ];

  Future<void> _create(BuildContext context) async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final name = await promptText(context, title: l.newGroup, label: l.groupName);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final group = await teamRepo.createGroup(session.workspaceId!, name);
    if (!context.mounted) return;
    final catalog = context.read<CatalogController>();
    final picked = await showMembersPicker(
      context,
      title: l.groupMembers,
      members: catalog.humans.where((m) => m.status == 'active').toList(),
      selected: const {},
    );
    if (picked != null) {
      await teamRepo.setGroupMembers(workspaceId: session.workspaceId!, groupId: group, userIds: picked);
    }
  }

  Future<void> _editMembers(BuildContext context, UserGroup group) async {
    final l = context.l10n;
    final catalog = context.read<CatalogController>();
    final picked = await showMembersPicker(
      context,
      title: '${l.groupMembers} · ${group.name}',
      members: catalog.humans.where((m) => m.status == 'active').toList(),
      selected: {for (final m in catalog.membersOfGroup(group.id)) m.userId},
    );
    if (picked != null) {
      await teamRepo.setGroupMembers(workspaceId: group.workspaceId, groupId: group.id, userIds: picked);
    }
  }
}
