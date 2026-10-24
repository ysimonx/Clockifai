import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/teammates.dart';

/// Commandes de connexion d'un poste au plugin Claude Code (plans/10-suivi-claude-code.md, §6.1).
///
/// Claude Code n'accepte une marketplace servie par URL qu'en https : une instance en http (pile locale) passe par la
/// marketplace `clockifai-dev`, dossier `integrations/` du dépôt.
class ClaudeCodeSetup {
  ClaudeCodeSetup(String baseUrl, {this.platform = TargetPlatform.macOS})
      : base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final String base;
  final TargetPlatform platform;

  bool get local => !base.startsWith('https://');
  String get plugin => local ? 'clockifai@clockifai-dev' : 'clockifai@clockifai';

  String get install => [
        'claude plugin marketplace add ${local ? '<dépôt Clockifai>/integrations' : '$base/api/claude/marketplace.json'}',
        'claude plugin install $plugin${local ? ' --config url=$base' : ''}',
      ].join('\n');

  /// Le jeton passe par le presse-papiers : ni dans l'historique du shell, ni dans la liste des processus.
  String get configure => '${switch (platform) {
        TargetPlatform.windows => 'Get-Clipboard',
        TargetPlatform.linux => 'wl-paste',
        _ => 'pbpaste',
      }} | claude plugin configure $plugin --values-stdin';

  /// Ce que « Copier le jeton » met dans le presse-papiers : l'objet JSON attendu par `--values-stdin`.
  static String clipboardValue(String token) => jsonEncode({'token': token});
}

String lastEventLabel(AppLocalizations l, String locale, DateTime? at, DateTime now) {
  if (at == null) return l.lastEventNever;
  final ago = now.difference(at);
  if (ago.inMinutes < 1) return l.lastEventJustNow;
  if (ago.inHours < 1) return l.lastEventMinutesAgo(ago.inMinutes);
  if (ago.inDays < 1) return l.lastEventHoursAgo(ago.inHours);
  return l.lastEventOn(DateFormat.yMMMd(locale).add_Hm().format(at.toLocal()));
}

/// Entrée des paramètres : ouvre la connexion des postes.
class ClaudeCodeTile extends StatelessWidget {
  const ClaudeCodeTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    return ListTile(
      leading: const Icon(Icons.terminal),
      title: const Text('Claude Code'),
      subtitle: Text(l.claudeCodeHelp('Claude · ${session.displayName}')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        // Le dialogue rend l'adresse à ouvrir (« Voir sa fiche dans l'équipe ») : on y va une fois refermé.
        final target = await showDialog<String>(context: context, builder: (_) => ClaudeCodeDialog(workspaceId: session.workspaceId!));
        if (target != null && context.mounted) context.go(target);
      },
    );
  }
}

class ClaudeCodeDialog extends StatefulWidget {
  const ClaudeCodeDialog({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<ClaudeCodeDialog> createState() => _ClaudeCodeDialogState();
}

class _ClaudeCodeDialogState extends State<ClaudeCodeDialog> {
  List<Map<String, dynamic>>? _tokens;
  bool _agentActive = true;
  String? _error;
  ({String name, String token})? _created;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final query = {'workspace_id': widget.workspaceId};
      final res = await ServicesApi.get('/api/tokens', query);
      // Agent désactivé ou retiré par un admin : les événements arrivent mais ne produisent plus de temps (D7.10).
      final today = await ServicesApi.get('/api/activity/today', query);
      if (mounted) {
        setState(() {
          _tokens = (res['tokens'] as List).cast<Map<String, dynamic>>();
          _agentActive = today['agent_id'] != null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.onlineOnly);
    }
  }

  Future<void> _connect() async {
    final l = context.l10n;
    final name = await promptText(context, title: l.connectComputer, label: l.computerName);
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final res = await ServicesApi.post('/api/tokens', {'workspace_id': widget.workspaceId, 'name': name.trim()});
      setState(() => _created = (name: res['name'] as String, token: res['token'] as String));
      await _load();
    } catch (_) {
      if (mounted) showSnack(context, l.onlineOnly);
    }
  }

  Future<void> _revoke(Map<String, dynamic> t) async {
    final l = context.l10n;
    if (!await confirm(context, title: l.revoke, message: l.revokeTokenConfirm(t['name'] as String), confirmLabel: l.revoke)) return;
    try {
      await ServicesApi.delete('/api/tokens/${t['id']}', {'workspace_id': widget.workspaceId});
      await _load();
    } catch (_) {
      if (mounted) showSnack(context, l.onlineOnly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    // Créé avec le premier jeton (ensure_agent) ; absent s'il a été retiré par un admin.
    final agent = context.watch<CatalogController>().agentsOf(session.userId).firstOrNull;
    final theme = Theme.of(context);
    final now = DateTime.now();
    return AlertDialog(
      title: const Text('Claude Code'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.claudeCodeIntro(agent == null ? 'Claude · ${session.displayName}' : memberName(agent))),
            if (agent != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: Text(l.agentCardLink),
                  onPressed: () => Navigator.pop(context, Uri(path: '/team', queryParameters: {'member': agent.userId}).toString()),
                ),
              ),
            const SizedBox(height: 12),
            if (_created != null) _Steps(name: _created!.name, token: _created!.token),
            if (!_agentActive && (_tokens?.any((t) => t['user_id'] == session.userId) ?? false))
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(leading: const Icon(Icons.block), title: Text(l.agentInactive)),
              ),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(l.connectedComputers, style: theme.textTheme.titleSmall),
            ),
            if (_tokens == null && _error == null) const Center(child: CircularProgressIndicator()),
            if (_tokens != null && _tokens!.isEmpty) Text(l.noConnectedComputers, style: theme.textTheme.bodySmall),
            for (final t in _tokens ?? const <Map<String, dynamic>>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.computer),
                title: Text(t['user_id'] == session.userId ? t['name'] as String : '${t['name']} · ${t['user_name'] ?? ''}'),
                subtitle: Text(lastEventLabel(l, context.localeTag, DateTime.tryParse(t['last_used_at'] as String? ?? ''), now)),
                trailing: IconButton(tooltip: l.revoke, icon: const Icon(Icons.delete_outline), onPressed: () => _revoke(t)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton.icon(icon: const Icon(Icons.add), label: Text(l.connectComputer), onPressed: _connect),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }
}

/// Les trois étapes, affichées une seule fois avec le jeton qui vient d'être créé.
class _Steps extends StatelessWidget {
  const _Steps({required this.name, required this.token});
  final String name;
  final String token;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final setup = ClaudeCodeSetup(ServicesApi.baseUrl, platform: defaultTargetPlatform);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.apiTokenCreated(name), style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Text(l.claudeCodeStepInstall),
          _CommandBox(setup.install),
          if (setup.local) Text(l.claudeCodeLocalInstance, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Text(l.claudeCodeStepToken),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.key),
            label: Text(l.copyToken),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: ClaudeCodeSetup.clipboardValue(token)));
              if (context.mounted) showSnack(context, l.copied);
            },
          ),
          _CommandBox(setup.configure),
          const SizedBox(height: 12),
          Text(l.claudeCodeStepStart),
          const SizedBox(height: 8),
          Text(l.claudeCodeRequirements, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _CommandBox extends StatelessWidget {
  const _CommandBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
        IconButton(
          tooltip: l.copy,
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) showSnack(context, l.copied);
          },
        ),
      ]),
    );
  }
}
