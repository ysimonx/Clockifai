import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, UserAttributes;

import '../../core/di.dart';
import '../../core/display_prefs.dart';
import '../../core/guide.dart';
import '../../core/launch_at_login.dart';
import '../../core/l10n.dart';
import '../../core/locale_controller.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart';
import '../integrations/claude_code.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    return PageScaffold(
      title: l.settings,
      maxWidth: 800,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        _Section(title: l.profile, children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(session.displayName),
            subtitle: Text(session.user?.email ?? ''),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final name = await promptText(context, title: l.yourName, label: l.name, initial: session.profile?.displayName ?? '');
              if (name != null && name.trim().isNotEmpty) {
                await workspaceRepo.updateProfile(session.userId!, ProfilesCompanion(displayName: Value(name.trim())));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: Text(l.setPassword),
            subtitle: Text(l.setPasswordHelp),
            onTap: () async {
              final pwd = await promptText(context, title: l.setPassword, label: l.newPassword);
              if (pwd == null || pwd.length < 8) {
                if (context.mounted && pwd != null) showSnack(context, l.passwordTooShort);
                return;
              }
              try {
                await Supabase.instance.client.auth.updateUser(UserAttributes(password: pwd));
                if (context.mounted) showSnack(context, l.passwordUpdated);
              } catch (e) {
                if (context.mounted) showSnack(context, '$e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(l.kioskPin),
            subtitle: Text(l.kioskPinHelp),
            onTap: () => _setPin(context, session.workspaceId!),
          ),
          const _LanguageTile(),
          SwitchListTile(
            secondary: const Icon(Icons.layers_outlined),
            title: Text(l.groupSimilarEntries),
            subtitle: Text(l.groupSimilarEntriesHelp),
            value: context.watch<DisplayPrefs>().groupSimilarEntries,
            onChanged: (v) => context.read<DisplayPrefs>().setGroupSimilarEntries(v),
          ),
          if (LaunchAtLogin.supported) const LaunchAtLoginTile(),
        ]),
        const SizedBox(height: 16),
        _Section(title: l.workspaces, children: [
          RadioGroup<String>(
            groupValue: session.workspaceId,
            onChanged: (id) => id == null ? null : session.selectWorkspace(id),
            child: Column(children: [
              for (final m in session.memberships)
                RadioListTile<String>(
                  value: m.workspace.id,
                  title: Text(m.workspace.name),
                  subtitle: Text(roleLabel(context, m.member.role)),
                ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l.createWorkspace),
            onTap: () async {
              final name = await promptText(context, title: l.createWorkspace, label: l.name);
              if (name == null || name.trim().isEmpty) return;
              final id = await workspaceRepo.createWorkspace(name: name, userId: session.userId!, currency: session.workspace?.currency ?? 'EUR');
              if (context.mounted) showSnack(context, l.workspaceCreated);
              await session.selectWorkspace(id);
            },
          ),
        ]),
        const SizedBox(height: 16),
        if (session.workspace != null) _WorkspaceSettings(workspace: session.workspace!, editable: session.isAdmin),
        if (session.isAdmin && session.workspace != null) ...[
          const SizedBox(height: 16),
          _BillingSettings(workspace: session.workspace!),
          const SizedBox(height: 16),
          _Section(title: l.kiosk, children: [
            ListTile(
              leading: const Icon(Icons.tablet_mac),
              title: Text(l.kioskDevices),
              subtitle: Text(l.kioskDevicesHelp),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(context: context, builder: (_) => _KioskDevicesDialog(workspaceId: session.workspaceId!)),
            ),
          ]),
        ],
        if (session.workspace != null) ...[
          const SizedBox(height: 16),
          _Section(title: l.integrations, children: const [ClaudeCodeTile()]),
        ],
        const SizedBox(height: 16),
        _Section(title: l.help, children: [
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l.userGuide),
            subtitle: Text(l.userGuideHelp),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openGuide(context),
          ),
        ]),
        const SizedBox(height: 16),
        _Section(title: l.account, children: [
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(l.signOut),
            subtitle: Text(l.signOutHelp),
            onTap: () async {
              if (await confirm(context, title: l.signOut, message: l.signOutHelp, confirmLabel: l.signOut)) {
                await session.signOut();
              }
            },
          ),
        ]),
      ]),
    );
  }
}

Future<void> _setPin(BuildContext context, String workspaceId) async {
  final l = context.l10n;
  final pin = await promptText(context, title: l.kioskPin, label: l.kioskPinLabel);
  if (pin == null || !context.mounted) return;
  if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) return showSnack(context, l.kioskPinInvalid);
  try {
    await Supabase.instance.client.rpc('set_kiosk_pin', params: {'p_workspace_id': workspaceId, 'p_pin': pin});
    if (context.mounted) showSnack(context, l.kioskPinSaved);
  } catch (e) {
    if (context.mounted) showSnack(context, l.onlineOnly);
  }
}

String roleLabel(BuildContext context, String role) {
  final l = context.l10n;
  return switch (role) {
    'owner' => l.roleOwner,
    'admin' => l.roleAdmin,
    'manager' => l.roleManager,
    _ => l.roleMember,
  };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card(child: Column(children: children)),
      ]);
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ctrl = context.watch<LocaleController>();
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l.language),
      trailing: DropdownButton<String>(
        value: ctrl.locale?.languageCode ?? 'system',
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(value: 'system', child: Text(l.systemLanguage)),
          const DropdownMenuItem(value: 'fr', child: Text('Français')),
          const DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (v) => ctrl.set(v == null || v == 'system' ? null : Locale(v)),
      ),
    );
  }
}

/// Démarrage à l'ouverture de session (macOS) : l'app s'ouvre dans la barre de menus, sans fenêtre.
/// Relu au retour dans l'app : le réglage peut aussi changer dans Réglages Système ou par le menu de l'icône.
class LaunchAtLoginTile extends StatefulWidget {
  const LaunchAtLoginTile({super.key});

  @override
  State<LaunchAtLoginTile> createState() => _LaunchAtLoginTileState();
}

class _LaunchAtLoginTileState extends State<LaunchAtLoginTile> {
  LaunchAtLoginStatus? _status;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async => _show(await LaunchAtLogin.status());

  void _show(LaunchAtLoginStatus status) {
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = _status;
    if (status == null || status == LaunchAtLoginStatus.unavailable) return const SizedBox.shrink();
    final approval = status == LaunchAtLoginStatus.requiresApproval;
    return SwitchListTile(
      secondary: const Icon(Icons.power_settings_new),
      title: Text(l.launchAtLogin),
      subtitle: approval
          ? Row(children: [
              Flexible(child: Text(l.launchAtLoginApproval)),
              TextButton(onPressed: LaunchAtLogin.openSystemSettings, child: Text(l.openSystemSettings)),
            ])
          : Text(l.launchAtLoginHelp),
      value: status != LaunchAtLoginStatus.disabled,
      onChanged: (on) async => _show(await LaunchAtLogin.setEnabled(on)),
    );
  }
}

class _WorkspaceSettings extends StatefulWidget {
  const _WorkspaceSettings({required this.workspace, required this.editable});
  final Workspace workspace;
  final bool editable;

  @override
  State<_WorkspaceSettings> createState() => _WorkspaceSettingsState();
}

class _WorkspaceSettingsState extends State<_WorkspaceSettings> {
  Future<void> _update(WorkspacesCompanion data) => workspaceRepo.updateWorkspace(widget.workspace.id, data);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ws = widget.workspace;
    final e = widget.editable;
    final lock = DateTime.tryParse(ws.lockEntriesBefore ?? '');
    final days = [for (var i = 1; i <= 7; i++) DateTime(2024, 1, i)]; // 1er janvier 2024 = lundi
    return _Section(title: l.workspaceSettings, children: [
      if (!e)
        ListTile(leading: const Icon(Icons.info_outline), title: Text(l.adminOnlySettings)),
      ListTile(
        title: Text(l.name),
        subtitle: Text(ws.name),
        trailing: e ? const Icon(Icons.edit_outlined) : null,
        onTap: !e
            ? null
            : () async {
                final name = await promptText(context, title: l.name, label: l.name, initial: ws.name);
                if (name != null && name.trim().isNotEmpty) await _update(WorkspacesCompanion(name: Value(name.trim())));
              },
      ),
      ListTile(
        title: Text(l.currency),
        trailing: DropdownButton<String>(
          value: ws.currency,
          underline: const SizedBox.shrink(),
          items: [for (final c in {'EUR', 'USD', 'GBP', 'CHF', 'CAD', ws.currency}) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: !e ? null : (v) => _update(WorkspacesCompanion(currency: Value(v!))),
        ),
      ),
      ListTile(
        title: Text(l.weekStartsOn),
        trailing: DropdownButton<int>(
          value: ws.weekStart,
          underline: const SizedBox.shrink(),
          items: [
            for (var i = 1; i <= 7; i++)
              DropdownMenuItem(value: i, child: Text(toBeginningOfSentenceCase(DateFormat.EEEE(context.localeTag).format(days[i - 1])))),
          ],
          onChanged: !e ? null : (v) => _update(WorkspacesCompanion(weekStart: Value(v!))),
        ),
      ),
      ListTile(
        title: Text(l.rounding),
        subtitle: Text(l.roundingHelp),
        trailing: DropdownButton<int>(
          value: ws.roundingMinutes,
          underline: const SizedBox.shrink(),
          items: [for (final m in const [0, 5, 6, 10, 12, 15, 30, 60]) DropdownMenuItem(value: m, child: Text(m == 0 ? l.none : '$m min'))],
          onChanged: !e ? null : (v) => _update(WorkspacesCompanion(roundingMinutes: Value(v!))),
        ),
      ),
      SwitchListTile(
        title: Text(l.requireProject),
        value: ws.requireProject,
        onChanged: !e ? null : (v) => _update(WorkspacesCompanion(requireProject: Value(v))),
      ),
      SwitchListTile(
        title: Text(l.requireDescription),
        value: ws.requireDescription,
        onChanged: !e ? null : (v) => _update(WorkspacesCompanion(requireDescription: Value(v))),
      ),
      ListTile(
        title: Text(l.timeForOthers),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.timeForOthersHelp),
          DropdownButton<String>(
            value: ws.timeForOthers ?? 'admins',
            isExpanded: true,
            items: [
              DropdownMenuItem(value: 'admins', child: Text(l.timeForOthersAdmins)),
              DropdownMenuItem(value: 'admins_and_team_managers', child: Text(l.timeForOthersAdminsAndTeamManagers)),
            ],
            onChanged: !e ? null : (v) => _update(WorkspacesCompanion(timeForOthers: Value(v))),
          ),
        ]),
      ),
      ListTile(
        title: Text(l.taskCreation),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.taskCreationHelp),
          DropdownButton<String>(
            value: ws.taskCreation ?? 'everyone',
            isExpanded: true,
            items: [
              DropdownMenuItem(value: 'everyone', child: Text(l.taskCreationEveryone)),
              DropdownMenuItem(value: 'managers', child: Text(l.taskCreationManagers)),
            ],
            onChanged: !e ? null : (v) => _update(WorkspacesCompanion(taskCreation: Value(v))),
          ),
        ]),
      ),
      ListTile(
        title: Text(l.autoStopTimers),
        subtitle: Text(l.autoStopTimersHelp),
        trailing: DropdownButton<int>(
          value: ws.autoStopAfterHours,
          underline: const SizedBox.shrink(),
          items: [for (final h in const [0, 8, 10, 12, 14, 24]) DropdownMenuItem(value: h, child: Text(h == 0 ? l.never : '$h h'))],
          onChanged: !e ? null : (v) => _update(WorkspacesCompanion(autoStopAfterHours: Value(v!))),
        ),
      ),
      ListTile(
        title: Text(l.parallelTimers),
        subtitle: Text(l.parallelTimersHelp),
        trailing: DropdownButton<int>(
          value: ws.maxRunningTimers ?? 1,
          underline: const SizedBox.shrink(),
          items: [for (final n in const [1, 2, 3, 5, 0]) DropdownMenuItem(value: n, child: Text(n == 0 ? l.unlimited : '$n'))],
          onChanged: !e ? null : (v) => _update(WorkspacesCompanion(maxRunningTimers: Value(v!))),
        ),
      ),
      ListTile(
        title: Text(l.agentBilling),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.agentBillingHelp),
          DropdownButton<String>(
            value: ws.agentBilling ?? 'like_humans',
            isExpanded: true,
            items: [
              DropdownMenuItem(value: 'like_humans', child: Text(l.agentBillingLikeHumans)),
              DropdownMenuItem(value: 'never', child: Text(l.agentBillingNever)),
            ],
            onChanged: !e ? null : (v) => _update(WorkspacesCompanion(agentBilling: Value(v))),
          ),
        ]),
      ),
      ListTile(
        title: Text(l.lockEntriesBefore),
        subtitle: Text(lock == null ? l.lockEntriesNone : DateFormat.yMMMMd(context.localeTag).format(lock)),
        trailing: !e
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (lock != null)
                  IconButton(
                    tooltip: l.unlock,
                    icon: const Icon(Icons.lock_open),
                    onPressed: () => _update(const WorkspacesCompanion(lockEntriesBefore: Value(null))),
                  ),
                IconButton(
                  icon: const Icon(Icons.lock_clock),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: lock ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (d != null) {
                      await _update(WorkspacesCompanion(lockEntriesBefore: Value(DateFormat('yyyy-MM-dd').format(d))));
                    }
                  },
                ),
              ]),
      ),
    ]);
  }
}

class _BillingSettings extends StatefulWidget {
  const _BillingSettings({required this.workspace});
  final Workspace workspace;

  @override
  State<_BillingSettings> createState() => _BillingSettingsState();
}

class _BillingSettingsState extends State<_BillingSettings> {
  late final _company = TextEditingController(text: widget.workspace.companyName ?? '');
  late final _details = TextEditingController(text: widget.workspace.companyDetails ?? '');
  late final _prefix = TextEditingController(text: widget.workspace.invoicePrefix);
  late final _tax = TextEditingController(text: widget.workspace.defaultTaxPercent.toString());
  late final _due = TextEditingController(text: widget.workspace.invoiceDueDays.toString());

  @override
  void dispose() {
    for (final c in [_company, _details, _prefix, _tax, _due]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _Section(title: l.billing, children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _company, decoration: InputDecoration(labelText: l.companyName)),
          const SizedBox(height: 12),
          TextField(controller: _details, maxLines: 4, decoration: InputDecoration(labelText: l.companyDetails, hintText: l.companyDetailsHint)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _prefix, decoration: InputDecoration(labelText: l.invoicePrefix))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.taxPercent, suffixText: '%'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _due, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.paymentTermDays))),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                await workspaceRepo.updateWorkspace(widget.workspace.id, WorkspacesCompanion(
                  companyName: Value(_company.text.trim().isEmpty ? null : _company.text.trim()),
                  companyDetails: Value(_details.text.trim().isEmpty ? null : _details.text.trim()),
                  invoicePrefix: Value(_prefix.text.trim().isEmpty ? 'F' : _prefix.text.trim()),
                  defaultTaxPercent: Value(double.tryParse(_tax.text.replaceAll(',', '.')) ?? 20),
                  invoiceDueDays: Value(int.tryParse(_due.text) ?? 30),
                ));
                if (context.mounted) showSnack(context, l.saved);
              },
              child: Text(l.save),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _KioskDevicesDialog extends StatefulWidget {
  const _KioskDevicesDialog({required this.workspaceId});
  final String workspaceId;

  @override
  State<_KioskDevicesDialog> createState() => _KioskDevicesDialogState();
}

class _KioskDevicesDialogState extends State<_KioskDevicesDialog> {
  List<Map<String, dynamic>>? _devices;
  String? _error;
  String? _newToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ServicesApi.get('/api/kiosk/devices', {'workspace_id': widget.workspaceId});
      setState(() => _devices = (res['devices'] as List).cast<Map<String, dynamic>>());
    } catch (e) {
      setState(() => _error = context.l10n.onlineOnly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.kioskDevices),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_newToken != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.kioskTokenOnce),
                  const SizedBox(height: 6),
                  SelectableText(_newToken!, style: const TextStyle(fontFamily: 'monospace')),
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: Text(l.copy),
                    onPressed: () => Clipboard.setData(ClipboardData(text: _newToken!)),
                  ),
                ]),
              ),
            ),
          if (_devices == null && _error == null) const Center(child: CircularProgressIndicator()),
          for (final d in _devices ?? const <Map<String, dynamic>>[])
            ListTile(
              leading: const Icon(Icons.tablet_mac),
              title: Text(d['name'] as String),
              subtitle: Text(d['last_seen_at'] == null ? l.neverSeen : '${l.lastSeen}: ${d['last_seen_at']}'),
              trailing: IconButton(
                tooltip: l.revoke,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await ServicesApi.delete('/api/kiosk/devices/${d['id']}', {'workspace_id': widget.workspaceId});
                  await _load();
                },
              ),
            ),
        ]),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(l.newKioskDevice),
          onPressed: () async {
            final name = await promptText(context, title: l.newKioskDevice, label: l.name, initial: l.kiosk);
            if (name == null || name.trim().isEmpty) return;
            try {
              final res = await ServicesApi.post('/api/kiosk/devices', {'workspace_id': widget.workspaceId, 'name': name.trim()});
              setState(() => _newToken = res['token'] as String);
              await _load();
            } catch (e) {
              if (context.mounted) showSnack(context, l.onlineOnly);
            }
          },
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }
}
