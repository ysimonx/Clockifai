import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/widgets/common.dart';

/// Mode kiosque : tablette partagée (entrée d'atelier, base vie de chantier…).
/// L'appareil est enregistré par un jeton créé par un admin ; chaque membre pointe avec son PIN.
/// Nécessite le réseau (le serveur vérifie les PIN, jamais stockés sur l'appareil).
class KioskPage extends StatefulWidget {
  const KioskPage({super.key});

  @override
  State<KioskPage> createState() => _KioskPageState();
}

class _KioskPageState extends State<KioskPage> {
  static const _prefKey = 'kiosk_device_token';
  String? _token;
  Map<String, dynamic>? _state;
  String? _error;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      setState(() => _token = p.getString(_prefKey));
      _load();
    });
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final t = _token;
    if (t == null) return;
    try {
      final s = await ServicesApi.kiosk('GET', '/api/kiosk/state', t);
      if (mounted) {
        setState(() {
          _state = s;
          _error = null;
        });
      }
    } on ServicesException catch (e) {
      if (mounted) setState(() => _error = e.status == 401 ? context.l10n.kioskTokenInvalid : e.message);
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.offline);
    }
  }

  Future<void> _saveToken(String? token) async {
    final p = await SharedPreferences.getInstance();
    if (token == null) {
      await p.remove(_prefKey);
    } else {
      await p.setString(_prefKey, token.trim());
    }
    setState(() {
      _token = token?.trim();
      _state = null;
      _error = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_token == null) return _Setup(onSave: _saveToken);
    final ws = _state?['workspace'] as Map<String, dynamic>?;
    final members = ((_state?['members'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final projects = ((_state?['projects'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        title: Text(ws?['name'] as String? ?? l.kiosk),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reset' && await confirm(context, title: l.kioskReset, message: l.kioskResetMessage, confirmLabel: l.kioskReset)) {
                await _saveToken(null);
              }
              if (v == 'exit' && context.mounted) context.go('/login');
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'reset', child: Text(l.kioskReset)),
              PopupMenuItem(value: 'exit', child: Text(l.kioskExit)),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_error != null)
          MaterialBanner(content: Text(_error!), actions: [TextButton(onPressed: _load, child: Text(l.retry))]),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l.kioskTapYourName, style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: (width / 220).floor().clamp(2, 8),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              for (final m in members)
                _MemberTile(
                  member: m,
                  onTap: () => _punch(m, projects),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Future<void> _punch(Map<String, dynamic> m, List<Map<String, dynamic>> projects) async {
    final l = context.l10n;
    if (m['has_pin'] != true) return showSnack(context, l.kioskNoPin);
    final running = m['running_since'] != null;
    final res = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _PinDialog(name: m['display_name'] as String, clockingIn: !running, projects: projects),
    );
    if (res == null || !mounted) return;
    try {
      final out = await ServicesApi.kiosk('POST', '/api/kiosk/punch', _token!, {'user_id': m['user_id'], 'pin': res.$1, 'project_id': res.$2});
      if (!mounted) return;
      final name = m['display_name'] as String;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          Timer(const Duration(seconds: 2), () {
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
          });
          final isIn = out['action'] == 'in';
          return AlertDialog(
            icon: Icon(isIn ? Icons.login : Icons.logout, size: 48, color: isIn ? Colors.green : Colors.orange),
            title: Text(isIn ? l.kioskHello(name) : l.kioskGoodbye(name)),
            content: Text(isIn ? l.kioskClockedIn : l.kioskClockedOut, textAlign: TextAlign.center),
          );
        },
      );
      await _load();
    } on ServicesException catch (e) {
      if (mounted) showSnack(context, e.status == 403 ? l.kioskWrongPin : (e.status == 429 ? l.kioskTooManyAttempts : e.message));
    } catch (_) {
      if (mounted) showSnack(context, l.offline);
    }
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});
  final Map<String, dynamic> member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final since = member['running_since'] == null ? null : DateTime.parse(member['running_since'] as String);
    final name = member['display_name'] as String? ?? '?';
    return Card(
      color: since != null ? Colors.green.withValues(alpha: 0.12) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircleAvatar(radius: 26, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 22))),
            const SizedBox(height: 8),
            Text(name, style: theme.textTheme.titleMedium, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            if (since != null) ...[
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.circle, size: 10, color: Colors.green),
                const SizedBox(width: 4),
                ElapsedText(since.toUtc(), style: theme.textTheme.bodySmall),
              ]),
              if (member['running_project'] != null) Text(member['running_project'] as String, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.name, required this.clockingIn, required this.projects});
  final String name;
  final bool clockingIn;
  final List<Map<String, dynamic>> projects;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';
  String? _projectId;

  void _tap(String d) {
    if (_pin.length < 8) setState(() => _pin += d);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 72,
            height: 60,
            child: FilledButton.tonal(
              onPressed: onTap ?? () => _tap(label),
              child: icon != null ? Icon(icon) : Text(label, style: const TextStyle(fontSize: 22)),
            ),
          ),
        );
    return AlertDialog(
      title: Text(widget.clockingIn ? l.kioskClockInAs(widget.name) : l.kioskClockOutAs(widget.name)),
      content: SizedBox(
        width: 260,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.clockingIn && widget.projects.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              initialValue: _projectId,
              decoration: InputDecoration(labelText: l.project),
              items: [
                DropdownMenuItem(value: null, child: Text(l.noProject)),
                for (final p in widget.projects) DropdownMenuItem(value: p['id'] as String, child: Row(children: [ColorDot(p['color'] as String), const SizedBox(width: 6), Text(p['name'] as String)])),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            const SizedBox(height: 12),
          ],
          Text('●' * _pin.length + '○' * (4 - _pin.length).clamp(0, 4), style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 6)),
          const SizedBox(height: 12),
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d)]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            key('', icon: Icons.backspace_outlined, onTap: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1))),
            key('0'),
            key('', icon: Icons.check, onTap: _pin.length >= 4 ? () => Navigator.pop(context, (_pin, _projectId)) : null),
          ]),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel))],
    );
  }
}

class _Setup extends StatefulWidget {
  const _Setup({required this.onSave});
  final ValueChanged<String> onSave;

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  final _c = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.kiosk), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/login'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.tablet_mac, size: 56),
              const SizedBox(height: 16),
              Text(l.kioskSetupHelp, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(controller: _c, decoration: InputDecoration(labelText: l.kioskToken, hintText: 'kio_…')),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _c.text.trim().isEmpty ? null : widget.onSave(_c.text), child: Text(l.save)),
            ]),
          ),
        ),
      ),
    );
  }
}
