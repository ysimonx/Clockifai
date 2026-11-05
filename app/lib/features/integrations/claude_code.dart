import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/teammates.dart';
import '../../data/drift/database.dart';

/// Installation du plugin Claude Code sur un poste (plans/21-installation-simple-du-plugin.md). Le poste se connecte
/// ensuite seul : sa première session donne un lien, ouvert dans l'app (`ConnectComputerPage`).
///
/// Claude Code n'accepte une marketplace servie par URL qu'en https : une instance en http (pile locale) passe par la
/// marketplace `clockifai-dev`, dossier `integrations/` du dépôt.
class ClaudeCodeSetup {
  ClaudeCodeSetup(String baseUrl, {this.platform = TargetPlatform.macOS})
      : base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final String base;
  final TargetPlatform platform;

  bool get local => !base.startsWith('https://');

  /// Installation de la commande `claude` (installeur natif, code.claude.com/docs/en/setup). L'extension VSCode embarque
  /// sa propre copie de Claude Code, hors du `PATH` : elle marche sans la commande, qui sert à installer le plugin.
  String get installCli => platform == TargetPlatform.windows
      ? 'irm https://claude.ai/install.ps1 | iex'
      : 'curl -fsSL https://claude.ai/install.sh | bash';

  String get marketplace => local ? '<dépôt Clockifai>/integrations' : '$base/api/claude/marketplace.json';

  /// `--marketplace` ajoute la marketplace si elle manque (Claude Code 2.1.292 ou plus).
  String get install => 'claude plugin install clockifai --marketplace $marketplace';

  /// Lien d'installation de l'extension VSCode, sans terminal ni commande `claude` : ordinateurs seulement, et il
  /// refuse une marketplace en http ou un chemin local (plans/21-installation-simple-du-plugin.md).
  String? get vscodeLink => local || !const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}.contains(platform)
      ? null
      : Uri(
          scheme: 'vscode',
          host: 'anthropic.claude-code',
          path: '/install-plugin',
          queryParameters: {'plugin': 'clockifai', 'marketplace': marketplace},
        ).toString();
}

/// Le poste qui vient de se connecter : un jeton absent de [known] dont un premier événement est arrivé.
String? newComputer(List<Map<String, dynamic>> tokens, Set<String> known) {
  for (final t in tokens) {
    if (!known.contains(t['id']) && t['last_used_at'] != null) return t['name'] as String;
  }
  return null;
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
  bool _showSteps = false;
  /// Jetons connus quand les étapes s'affichent : la fenêtre relit la liste jusqu'à voir un nouveau poste.
  Set<String>? _known;
  Timer? _watch;
  String? _connected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  void _connect() {
    setState(() {
      _showSteps = true;
      _known = {for (final t in _tokens ?? const <Map<String, dynamic>>[]) t['id'] as String};
      _connected = null;
    });
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 5), (_) => _load());
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
          _error = null;
          final known = _known;
          _connected ??= known == null ? null : newComputer(_tokens!, known);
          if (_connected != null) _watch?.cancel();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.onlineOnly);
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
            Wrap(spacing: 8, children: [
              if (agent != null)
                TextButton.icon(
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: Text(l.agentCardLink),
                  onPressed: () => Navigator.pop(context, Uri(path: '/team', queryParameters: {'member': agent.userId}).toString()),
                ),
            ]),
            // Réglage personnel (profiles.claude_tasks, plan 10, D18) : appliqué par le serveur au calcul des sessions.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.claudeTasks, style: theme.textTheme.titleSmall),
            ),
            Text(l.claudeTasksHelp, style: theme.textTheme.bodySmall),
            DropdownButton<String>(
              value: session.profile?.claudeTasks ?? 'subject',
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 'subject', child: Text(l.claudeTasksSubject)),
                DropdownMenuItem(value: 'session', child: Text(l.claudeTasksSession)),
                DropdownMenuItem(value: 'off', child: Text(l.claudeTasksOff)),
              ],
              onChanged: (v) => workspaceRepo.updateProfile(session.userId!, ProfilesCompanion(claudeTasks: Value(v))),
            ),
            const SizedBox(height: 12),
            if (_connected != null)
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(leading: const Icon(Icons.check_circle), title: Text(l.claudeCodeConnected(_connected!))),
              )
            else if (_showSteps) ...[
              const _Steps(),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(l.claudeCodeWaiting, style: theme.textTheme.bodySmall),
                ]),
              ),
            ],
            if (!_agentActive && (_tokens?.any((t) => t['user_id'] == session.userId) ?? false))
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(l.agentInactive),
                  // Un admin le réactive (menu de sa fiche) ou le restaure (Agents retirés) dans Équipe.
                  trailing: session.isAdmin
                      ? TextButton(onPressed: () => Navigator.pop(context, '/team'), child: Text(l.team))
                      : null,
                ),
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
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: l.revoke, icon: const Icon(Icons.delete_outline), onPressed: () => _revoke(t)),
                ]),
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

/// Les étapes de connexion : installer le plugin, puis la première session donne le lien.
class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final setup = ClaudeCodeSetup(ServicesApi.baseUrl, platform: defaultTargetPlatform);
    final vscode = setup.vscodeLink;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.claudeCodeStepInstall),
          if (vscode != null) ...[
            const SizedBox(height: 6),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.open_in_new),
              label: Text(l.openInVscode),
              // _self : une adresse vscode:// ouvre l'éditeur, un nouvel onglet resterait vide.
              onPressed: () => launchUrl(Uri.parse(vscode), mode: LaunchMode.externalApplication, webOnlyWindowName: '_self'),
            ),
            const SizedBox(height: 8),
            Text(l.claudeCodeOrTerminal),
          ],
          _CommandBox(setup.install),
          if (setup.local) Text(l.claudeCodeLocalInstance, style: theme.textTheme.bodySmall),
          Text(l.claudeCodeStepCli, style: theme.textTheme.bodySmall),
          _CommandBox(setup.installCli),
          const SizedBox(height: 12),
          Text(l.claudeCodeStepStart),
          const SizedBox(height: 8),
          Text(l.claudeCodeStepLink),
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
