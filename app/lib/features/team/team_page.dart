import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/teammates.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../settings/settings_page.dart' show roleLabel;

/// Membres du workspace : rôle, taux, activité de la semaine et chronomètre en cours ;
/// groupes d'utilisateurs et chefs d'équipe (plans/03-saisie-pour-autrui.md).
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
        // Plusieurs chronomètres par membre si le workspace le permet (les plus récents d'abord).
        final runningByUser = <String, List<EntryRow>>{};
        for (final r in rows) {
          weekByUser[r.entry.userId] = (weekByUser[r.entry.userId] ?? 0) + r.seconds;
          if (r.entry.endAt == null) (runningByUser[r.entry.userId] ??= []).add(r);
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
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
                padding: const EdgeInsets.only(bottom: 8),
                child: _MemberCard(
                  member: m,
                  weekSeconds: weekByUser[m.userId] ?? 0,
                  running: runningByUser[m.userId] ?? const [],
                  showActivity: m.userId == session.userId || rights.manages(m.userId),
                ),
              ),
        ]);
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

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.weekSeconds, required this.running, required this.showActivity});
  final WorkspaceMember member;
  final int weekSeconds;
  final List<EntryRow> running;
  final bool showActivity;

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
      child: ListTile(
        leading: Badge(
          isLabelVisible: running.isNotEmpty,
          backgroundColor: Colors.green,
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
                const Icon(Icons.play_circle, size: 14, color: Colors.green),
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
            if (await confirm(context, title: l.removeMember, message: l.removeMemberMessage, confirmLabel: l.remove)) {
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
    await workspaceRepo.updateMember(
      member.id,
      WorkspaceMembersCompanion(hourlyRateCents: Value(parse(hourly.text)), costRateCents: Value(parse(cost.text))),
    );
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
