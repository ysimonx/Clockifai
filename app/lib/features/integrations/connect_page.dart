import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';

/// Page du lien que la première session de Claude Code donne à l'utilisateur : relie ce poste à son compte
/// (plans/21-installation-simple-du-plugin.md). Le jeton ne passe pas par ici : le hook le retire ensuite.
class ConnectComputerPage extends StatefulWidget {
  const ConnectComputerPage({super.key, required this.code});
  final String code;

  @override
  State<ConnectComputerPage> createState() => _ConnectComputerPageState();
}

class _ConnectComputerPageState extends State<ConnectComputerPage> {
  final _name = TextEditingController();
  bool _ready = false;
  bool _gone = false;
  bool _busy = false;
  String? _workspaceId;
  String? _connected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _failed(Object e) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (e is ServicesException && e.status == 404) {
        _gone = true;
      } else {
        _error = context.l10n.onlineOnly;
      }
    });
  }

  Future<void> _load() async {
    try {
      final res = await ServicesApi.get('/api/claude/link/${widget.code}', const {});
      if (!mounted) return;
      setState(() {
        _name.text = res['machine'] as String;
        _ready = true;
      });
    } catch (e) {
      _failed(e);
    }
  }

  Future<void> _connect(String workspaceId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ServicesApi.post('/api/claude/link/${widget.code}/approve', {'workspace_id': workspaceId, 'name': _name.text});
      if (mounted) setState(() => _connected = res['name'] as String);
    } catch (e) {
      _failed(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final workspaceId = _workspaceId ?? session.workspaceId;
    final home = FilledButton(onPressed: () => context.go('/today'), child: Text(l.openClockifai));
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Center(child: AppLogo(size: 56)),
              const SizedBox(height: 24),
              if (_connected != null) ...[
                Text(l.connectDone(_connected!), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                home,
              ] else if (_gone) ...[
                Text(l.connectGone, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                home,
              ] else if (!_ready || workspaceId == null) ...[
                if (_error != null)
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error))
                else
                  const Center(child: CircularProgressIndicator()),
              ] else ...[
                Text(l.connectTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(l.connectHelp),
                const SizedBox(height: 8),
                Text(l.connectWarning, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                TextField(controller: _name, decoration: InputDecoration(labelText: l.computerName)),
                if (session.memberships.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButton<String>(
                    value: workspaceId,
                    isExpanded: true,
                    items: [
                      for (final m in session.memberships)
                        DropdownMenuItem(value: m.workspace.id, child: Text(m.workspace.name)),
                    ],
                    onChanged: (v) => setState(() => _workspaceId = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : () => _connect(workspaceId), child: Text(l.connectAction)),
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.go('/today'), child: Text(l.cancel)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
