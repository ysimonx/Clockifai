import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appBuildName;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../core/l10n.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _redirect => kIsWeb ? '${Uri.base.origin}/auth/callback' : AppConfig.authRedirectMobile;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
        final auth = Supabase.instance.client.auth;
        final email = _email.text.trim();
        if (_signUp) {
          final res = await auth.signUp(
            email: email,
            password: _password.text,
            emailRedirectTo: _redirect,
            data: {'display_name': _name.text.trim()},
          );
          if (res.session == null && mounted) setState(() => _info = context.l10n.checkYourEmail);
        } else {
          await auth.signInWithPassword(email: email, password: _password.text);
        }
      });

  Future<void> _magicLink() => _run(() async {
        final l = context.l10n;
        if (_email.text.trim().isEmpty) throw AuthException(l.emailRequired);
        await Supabase.instance.client.auth.signInWithOtp(email: _email.text.trim(), emailRedirectTo: _redirect);
        if (mounted) setState(() => _info = l.magicLinkSent);
      });

  Future<void> _resetPassword() => _run(() async {
        final l = context.l10n;
        if (_email.text.trim().isEmpty) throw AuthException(l.emailRequired);
        await Supabase.instance.client.auth.resetPasswordForEmail(_email.text.trim(), redirectTo: _redirect);
        if (mounted) setState(() => _info = l.resetEmailSent);
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.timer, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text('Clockifai', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(l.tagline, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 32),
              if (!AppConfig.isConfigured)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(padding: const EdgeInsets.all(12), child: Text(l.notConfigured)),
                ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l.signIn)),
                  ButtonSegment(value: true, label: Text(l.signUp)),
                ],
                selected: {_signUp},
                onSelectionChanged: (s) => setState(() => _signUp = s.first),
              ),
              const SizedBox(height: 16),
              if (_signUp) ...[
                TextField(controller: _name, decoration: InputDecoration(labelText: l.yourName), textInputAction: TextInputAction.next),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                decoration: InputDecoration(labelText: l.email),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: InputDecoration(labelText: l.password),
                obscureText: true,
                autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
              if (_info != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_info!, style: TextStyle(color: theme.colorScheme.primary))),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_signUp ? l.createAccount : l.signIn),
                ),
              ),
              const SizedBox(height: 8),
              if (!_signUp) ...[
                OutlinedButton(onPressed: _busy ? null : _magicLink, child: Text(l.sendMagicLink)),
                TextButton(onPressed: _busy ? null : _resetPassword, child: Text(l.forgotPassword)),
              ],
              const Divider(height: 32),
              TextButton.icon(
                icon: const Icon(Icons.tablet_mac),
                label: Text(l.kioskMode),
                onPressed: () => context.go('/kiosk'),
              ),
              const SizedBox(height: 8),
              const EnvironmentBadge(),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Version lancée : serveur local (développement) ou production, et numéro de version (`pubspec.yaml`).
class EnvironmentBadge extends StatelessWidget {
  const EnvironmentBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final local = AppConfig.isLocal;
    final foreground = local ? scheme.onTertiaryContainer : scheme.outline;
    final label = [
      local ? l.environmentLocal : l.environmentProduction,
      AppConfig.serverLabel,
      if (appBuildName != null) 'v$appBuildName',
    ].join(' · ');
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: local ? scheme.tertiaryContainer : null,
          border: Border.all(color: local ? scheme.tertiary : scheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(local ? Icons.computer : Icons.cloud_outlined, size: 16, color: foreground),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: foreground))),
        ]),
      ),
    );
  }
}
