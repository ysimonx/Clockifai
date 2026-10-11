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
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../settings/settings_page.dart' show roleLabel;

/// Membres du workspace : rôle, taux, activité de la semaine et chronomètre en cours.
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
    final ws = session.workspace!;
    final weekStart = startOfWeek(DateTime.now(), ws.weekStart);
    final members = catalog.members;

    return PageScaffold(
      title: l.team,
      actions: [
        if (session.isAdmin)
          FilledButton.icon(onPressed: () => _invite(context), icon: const Icon(Icons.person_add_alt), label: Text(l.invite)),
      ],
      child: StreamBuilder<List<EntryRow>>(
        stream: entriesRepo.watchEntries(
          workspaceId: ws.id,
          userId: session.isManager ? null : session.userId,
          from: weekStart,
          to: weekStart.add(const Duration(days: 7)),
          includeRunning: true,
        ),
        builder: (context, snap) {
          final rows = snap.data ?? const <EntryRow>[];
          final weekByUser = <String, int>{};
          final runningByUser = <String, EntryRow>{};
          for (final r in rows) {
            weekByUser[r.entry.userId] = (weekByUser[r.entry.userId] ?? 0) + r.seconds;
            if (r.entry.endAt == null) runningByUser[r.entry.userId] = r;
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (!session.isManager)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(l.teamMemberHint, style: Theme.of(context).textTheme.bodySmall),
              ),
            for (final m in members)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MemberCard(
                  member: m,
                  weekSeconds: weekByUser[m.userId] ?? 0,
                  running: runningByUser[m.userId],
                  showActivity: session.isManager || m.userId == session.userId,
                ),
              ),
          ]);
        },
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
  final EntryRow? running;
  final bool showActivity;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.read<SessionController>();
    final catalog = context.watch<CatalogController>();
    final name = member.displayName.isEmpty ? (member.email ?? '?') : member.displayName;
    final inactive = member.status != 'active';
    final ws = session.workspace!;
    final locale = context.localeTag;
    final run = running;

    return Card(
      child: ListTile(
        leading: Badge(
          isLabelVisible: run != null,
          backgroundColor: Colors.green,
          smallSize: 10,
          child: CircleAvatar(child: Text(name[0].toUpperCase())),
        ),
        title: Row(children: [
          Flexible(child: Text(name, style: inactive ? TextStyle(color: theme.colorScheme.outline, decoration: TextDecoration.lineThrough) : null)),
          const SizedBox(width: 8),
          Chip(label: Text(roleLabel(context, member.role)), visualDensity: VisualDensity.compact),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (member.email != null) Text(member.email!),
          if (showActivity) ...[
            if (run != null)
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
          case 'toggle':
            await workspaceRepo.updateMember(member.id, WorkspaceMembersCompanion(status: Value(member.status == 'active' ? 'inactive' : 'active')));
          case 'remove':
            if (await confirm(context, title: l.removeMember, message: l.removeMemberMessage, confirmLabel: l.remove)) {
              await workspaceRepo.updateMember(member.id, WorkspaceMembersCompanion(deletedAt: Value(nowUtc())));
            }
        }
      },
      itemBuilder: (_) => [
        if (member.role != 'owner') ...[
          for (final r in const ['member', 'manager', 'admin'])
            CheckedPopupMenuItem(value: r, checked: member.role == r, child: Text(roleLabel(context, r))),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(value: 'rate', child: Text(l.editRates)),
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
