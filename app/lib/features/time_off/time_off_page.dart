import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/modules_repository.dart';
import '../approvals/submission_bar.dart' show askDecisionNote;

/// Jours ouvrés (lundi–vendredi hors jours fériés) entre deux dates incluses.
double workingDays(DateTime start, DateTime end, Set<String> holidays) {
  var n = 0;
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday <= 5 && !holidays.contains(dayKey(d))) n++;
  }
  return n.toDouble();
}

class TimeOffPage extends StatelessWidget {
  const TimeOffPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final rights = TeamRights.of(context);
    final ws = session.workspaceId!;
    return PageScaffold(
      title: l.timeOff,
      actions: [
        FilledButton.icon(onPressed: () => _requestDialog(context), icon: const Icon(Icons.beach_access), label: Text(l.requestTimeOff)),
      ],
      child: StreamBuilder<List<TimeOffPolicy>>(
        stream: modulesRepo.watchPolicies(ws),
        builder: (context, polSnap) {
          final policies = polSnap.data ?? const <TimeOffPolicy>[];
          return StreamBuilder<List<TimeOffRequest>>(
            stream: modulesRepo.watchRequests(ws, userId: rights.seesTeam ? null : session.userId),
            builder: (context, reqSnap) {
              // Manager : tout le workspace ; chef d'équipe : son périmètre.
              final requests = (reqSnap.data ?? const <TimeOffRequest>[])
                  .where((r) => r.userId == session.userId || rights.manages(r.userId))
                  .toList();
              final mine = requests.where((r) => r.userId == session.userId).toList();
              final policyOf = {for (final p in policies) p.id: p};
              final pending = requests
                  .where((r) => r.status == 'pending' && r.userId != session.userId)
                  .where((r) => rights.canDecideTimeOff(r.userId, policyOf[r.policyId]))
                  .toList();
              return ListView(padding: const EdgeInsets.all(16), children: [
                _Balances(policies: policies, mine: mine),
                if (rights.seesTeam) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(l.toApprove),
                  if (pending.isEmpty)
                    Text(l.nothingToApprove, style: TextStyle(color: Theme.of(context).colorScheme.outline))
                  else
                    for (final r in pending) _RequestTile(request: r, policies: policies, managerView: true),
                ],
                const SizedBox(height: 20),
                _SectionTitle(l.myRequests),
                if (mine.isEmpty)
                  Text(l.noRequests, style: TextStyle(color: Theme.of(context).colorScheme.outline))
                else
                  for (final r in mine) _RequestTile(request: r, policies: policies, managerView: false),
                if (rights.seesTeam) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(l.teamRequests),
                  for (final r in requests.where((r) => r.userId != session.userId && !pending.contains(r)).take(50))
                    _RequestTile(request: r, policies: policies, managerView: true),
                ],
                if (session.isAdmin) ...[
                  const SizedBox(height: 20),
                  _PoliciesAdmin(policies: policies),
                  const SizedBox(height: 20),
                  const _HolidaysAdmin(),
                ],
              ]);
            },
          );
        },
      ),
    );
  }

  static Future<void> _requestDialog(BuildContext context) async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final ws = session.workspaceId!;
    final policies = (await modulesRepo.watchPolicies(ws).first).where((p) => !p.archived).toList();
    final holidays = (await modulesRepo.watchHolidays(ws).first).map((h) => h.date).toSet();
    if (!context.mounted) return;
    if (policies.isEmpty) return showSnack(context, l.noPoliciesYet);
    var policy = policies.first;
    var range = DateTimeRange(start: startOfDay(DateTime.now()), end: startOfDay(DateTime.now()));
    var halfDay = false;
    final note = TextEditingController();
    final amount = TextEditingController();
    final capacity = context.read<CatalogController>().memberOf(session.userId!)?.capacityHoursPerDay ?? 7;

    void recompute() {
      final days = workingDays(range.start, range.end, holidays) * (halfDay ? 0.5 : 1);
      amount.text = (policy.unit == 'hours' ? days * capacity : days).toStringAsFixed(policy.unit == 'hours' ? 1 : 1).replaceAll('.0', '');
    }

    recompute();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        final fmt = DateFormat.yMMMEd(ctx.localeTag);
        return AlertDialog(
          title: Text(l.requestTimeOff),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<TimeOffPolicy>(
                initialValue: policy,
                decoration: InputDecoration(labelText: l.policy),
                items: [for (final p in policies) DropdownMenuItem(value: p, child: Row(children: [ColorDot(p.color), const SizedBox(width: 8), Text(p.name)]))],
                onChanged: (p) => setState(() {
                  policy = p!;
                  recompute();
                }),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(range.start == range.end ? fmt.format(range.start) : '${fmt.format(range.start)} → ${fmt.format(range.end)}'),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    initialDateRange: range,
                  );
                  if (r != null) {
                    setState(() {
                      range = r;
                      if (r.start != r.end) halfDay = false;
                      recompute();
                    });
                  }
                },
              ),
              if (range.start == range.end && policy.unit == 'days')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.halfDay),
                  value: halfDay,
                  onChanged: (v) => setState(() {
                    halfDay = v;
                    recompute();
                  }),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: policy.unit == 'hours' ? l.hoursRequested : l.daysRequested),
              ),
              const SizedBox(height: 8),
              TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: l.noteOptional)),
              if (policy.requiresApproval)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.requiresApprovalHint, style: Theme.of(ctx).textTheme.bodySmall)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.send)),
          ],
        );
      }),
    );
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (ok != true || value == null || value <= 0) return;
    await modulesRepo.requestTimeOff(
      workspaceId: ws,
      userId: session.userId!,
      policyId: policy.id,
      start: range.start,
      end: range.end,
      amount: value,
      halfDay: halfDay,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    );
    if (context.mounted) showSnack(context, l.requestSent);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: Theme.of(context).textTheme.titleMedium));
}

/// Soldes de l'année en cours par politique.
class _Balances extends StatelessWidget {
  const _Balances({required this.policies, required this.mine});
  final List<TimeOffPolicy> policies;
  final List<TimeOffRequest> mine;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final year = DateTime.now().year;
    final active = policies.where((p) => !p.archived).toList();
    if (active.isEmpty) return Text(l.noPoliciesYet, style: TextStyle(color: Theme.of(context).colorScheme.outline));
    return StreamBuilder<List<TimeOffAllowance>>(
      stream: modulesRepo.watchAllowances(session.workspaceId!, userId: session.userId),
      builder: (context, snap) {
        final allowances = snap.data ?? const <TimeOffAllowance>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(l.balancesFor(year)),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final p in active)
              () {
                final override = allowances.where((a) => a.policyId == p.id && a.year == year).firstOrNull;
                final allowance = override?.allowance ?? p.annualAllowance;
                double sum(String status) => mine
                    .where((r) => r.policyId == p.id && r.status == status && r.startDate.startsWith('$year'))
                    .fold(0.0, (s, r) => s + r.amount);
                final used = sum('approved'), pending = sum('pending');
                final unit = p.unit == 'hours' ? 'h' : l.daysShort;
                String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
                return SizedBox(
                  width: 240,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [ColorDot(p.color), const SizedBox(width: 8), Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)))]),
                        const SizedBox(height: 8),
                        Text(allowance == null ? l.unlimited : '${n(allowance - used)} $unit ${l.remaining}',
                            style: Theme.of(context).textTheme.headlineSmall),
                        Text('${l.used} : ${n(used)} $unit${pending > 0 ? ' · ${l.pending} : ${n(pending)} $unit' : ''}',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (allowance != null) Text('${l.allowance} : ${n(allowance)} $unit', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ),
                );
              }(),
          ]),
        ]);
      },
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.policies, required this.managerView});
  final TimeOffRequest request;
  final List<TimeOffPolicy> policies;
  final bool managerView;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final session = context.read<SessionController>();
    final r = request;
    final policy = policies.where((p) => p.id == r.policyId).firstOrNull;
    final fmt = DateFormat.yMMMd(context.localeTag);
    final start = parseDay(r.startDate), end = parseDay(r.endDate);
    final (color, label) = switch (r.status) {
      'approved' => (Colors.green, l.statusApproved),
      'rejected' => (theme.colorScheme.error, l.statusRejected),
      'cancelled' => (theme.colorScheme.outline, l.statusCancelled),
      _ => (theme.colorScheme.tertiary, l.statusPending),
    };
    final who = managerView ? '${catalog.memberOf(r.userId)?.displayName ?? '?'} · ' : '';
    final unit = policy?.unit == 'hours' ? 'h' : l.daysShort;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ColorDot(policy?.color ?? '#999999', size: 14),
        title: Text('$who${policy?.name ?? '?'} · ${r.amount.toStringAsFixed(r.amount % 1 == 0 ? 0 : 1)} $unit'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(start == end ? fmt.format(start) : '${fmt.format(start)} → ${fmt.format(end)}${r.halfDay ? ' (½)' : ''}'),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          if (r.note?.isNotEmpty ?? false) Text('« ${r.note} »', style: theme.textTheme.bodySmall),
          if (r.decisionNote?.isNotEmpty ?? false) Text('${l.decision} : ${r.decisionNote}', style: theme.textTheme.bodySmall),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // Approbation selon la politique : managers, ou aussi chefs d'équipe pour leur périmètre.
          if (managerView && r.status == 'pending' && TeamRights.of(context).canDecideTimeOff(r.userId, policy)) ...[
            IconButton(
              tooltip: l.reject,
              icon: Icon(Icons.close, color: theme.colorScheme.error),
              onPressed: () async {
                final note = await askDecisionNote(context, l.reject);
                if (note != null) await modulesRepo.decideRequest(r.id, approve: false, note: note.isEmpty ? null : note);
              },
            ),
            FilledButton(onPressed: () => modulesRepo.decideRequest(r.id, approve: true), child: Text(l.approve)),
          ],
          if (r.userId == session.userId && (r.status == 'pending' || r.status == 'approved'))
            TextButton(
              onPressed: () async {
                if (await confirm(context, title: l.cancelRequest, confirmLabel: l.cancelRequest)) {
                  await modulesRepo.cancelRequest(r.id);
                }
              },
              child: Text(l.cancelRequest),
            ),
        ]),
      ),
    );
  }
}

class _PoliciesAdmin extends StatelessWidget {
  const _PoliciesAdmin({required this.policies});
  final List<TimeOffPolicy> policies;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _SectionTitle(l.policies)),
        TextButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: Text(l.newPolicy)),
      ]),
      Card(
        child: Column(children: [
          for (final p in policies)
            ListTile(
              leading: ColorDot(p.color, size: 14),
              title: Text(p.name, style: p.archived ? TextStyle(color: Theme.of(context).colorScheme.outline) : null),
              subtitle: Text([
                p.annualAllowance == null ? l.unlimited : '${p.annualAllowance} ${p.unit == 'hours' ? 'h' : l.daysShort} / ${l.year}',
                p.requiresApproval
                    ? (p.approvers == 'managers_and_team_managers' ? '${l.requiresApproval} (${l.approversManagersAndTeamManagers})' : l.requiresApproval)
                    : l.noApproval,
                if (!p.paid) l.unpaid,
              ].join(' · ')),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      await _edit(context, p);
                    case 'allowances':
                      await _allowances(context, p);
                    case 'archive':
                      await modulesRepo.savePolicy(p.workspaceId, TimeOffPoliciesCompanion(archived: Value(!p.archived)), id: p.id);
                    case 'delete':
                      if (await confirm(context, title: l.deletePolicy)) await modulesRepo.deletePolicy(p.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l.edit)),
                  PopupMenuItem(value: 'allowances', child: Text(l.memberAllowances)),
                  PopupMenuItem(value: 'archive', child: Text(p.archived ? l.restore : l.archive)),
                  PopupMenuItem(value: 'delete', child: Text(l.delete)),
                ],
              ),
            ),
          if (policies.isEmpty) ListTile(title: Text(l.noPoliciesYet)),
        ]),
      ),
    ]);
  }

  Future<void> _edit(BuildContext context, TimeOffPolicy? p) async {
    final l = context.l10n;
    final name = TextEditingController(text: p?.name ?? '');
    final allowance = TextEditingController(text: p?.annualAllowance?.toString() ?? '');
    var unit = p?.unit ?? 'days';
    var paid = p?.paid ?? true;
    var approval = p?.requiresApproval ?? true;
    var approvers = p?.approvers ?? 'managers';
    var color = p?.color ?? '#10B981';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(p == null ? l.newPolicy : l.editPolicy),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: l.name, hintText: l.policyExample)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: allowance, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.annualAllowance, hintText: l.emptyIsUnlimited))),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: unit,
                    items: [DropdownMenuItem(value: 'days', child: Text(l.days)), DropdownMenuItem(value: 'hours', child: Text(l.hours))],
                    onChanged: (v) => setState(() => unit = v!),
                  ),
                ]),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(l.requiresApproval), value: approval, onChanged: (v) => setState(() => approval = v)),
                if (approval)
                  DropdownButtonFormField<String>(
                    initialValue: approvers,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.approvers),
                    items: [
                      DropdownMenuItem(value: 'managers', child: Text(l.approversManagers)),
                      DropdownMenuItem(value: 'managers_and_team_managers', child: Text(l.approversManagersAndTeamManagers)),
                    ],
                    onChanged: (v) => setState(() => approvers = v!),
                  ),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(l.paid), value: paid, onChanged: (v) => setState(() => paid = v)),
                const SizedBox(height: 8),
                ColorPalettePicker(value: color, onChanged: (c) => setState(() => color = c)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    final ws = context.read<SessionController>().workspaceId!;
    final data = TimeOffPoliciesCompanion(
      name: Value(name.text.trim()),
      unit: Value(unit),
      annualAllowance: Value(double.tryParse(allowance.text.replaceAll(',', '.'))),
      paid: Value(paid),
      requiresApproval: Value(approval),
      approvers: Value(approvers),
      color: Value(color),
    );
    await modulesRepo.savePolicy(ws, p == null ? data.copyWith(workspaceId: Value(ws)) : data, id: p?.id);
  }

  Future<void> _allowances(BuildContext context, TimeOffPolicy p) async {
    final l = context.l10n;
    final catalog = context.read<CatalogController>();
    final year = DateTime.now().year;
    final existing = await modulesRepo.watchAllowances(p.workspaceId).first;
    final controllers = {
      for (final m in catalog.humans)
        m.userId: TextEditingController(
          text: existing.where((a) => a.userId == m.userId && a.policyId == p.id && a.year == year).firstOrNull?.allowance.toString() ?? '',
        ),
    };
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l.memberAllowances} — ${p.name} $year'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            Text(l.allowanceOverrideHelp(p.annualAllowance?.toString() ?? l.unlimited), style: Theme.of(ctx).textTheme.bodySmall),
            for (final m in catalog.humans)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: controllers[m.userId],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: m.displayName),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
        ],
      ),
    );
    if (ok != true) return;
    for (final e in controllers.entries) {
      final v = double.tryParse(e.value.text.replaceAll(',', '.'));
      if (v != null) {
        await modulesRepo.setAllowance(workspaceId: p.workspaceId, userId: e.key, policyId: p.id, year: year, allowance: v);
      }
    }
  }
}

class _HolidaysAdmin extends StatelessWidget {
  const _HolidaysAdmin();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ws = context.read<SessionController>().workspaceId!;
    final fmt = DateFormat.yMMMMEEEEd(context.localeTag);
    return StreamBuilder<List<Holiday>>(
      stream: modulesRepo.watchHolidays(ws),
      builder: (context, snap) {
        final holidays = snap.data ?? const <Holiday>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _SectionTitle(l.holidays)),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l.addHoliday),
              onPressed: () async {
                final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: DateTime.now());
                if (d == null || !context.mounted) return;
                final name = await _ask(context, l.addHoliday);
                if (name != null && name.isNotEmpty) await modulesRepo.addHoliday(ws, name, d);
              },
            ),
          ]),
          Card(
            child: Column(children: [
              for (final h in holidays)
                ListTile(
                  dense: true,
                  title: Text(h.name),
                  subtitle: Text(toBeginningOfSentenceCase(fmt.format(parseDay(h.date)))),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => modulesRepo.deleteHoliday(h.id)),
                ),
              if (holidays.isEmpty) ListTile(title: Text(l.noHolidays)),
            ]),
          ),
        ]);
      },
    );
  }

  Future<String?> _ask(BuildContext context, String title) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: ctx.l10n.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.l10n.save)),
        ],
      ),
    );
  }
}
