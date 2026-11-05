import 'package:clockifai/features/integrations/claude_code.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  test('instance en https : marketplace servie par l\'instance', () {
    final s = ClaudeCodeSetup('https://clockifai.kysoe.com/');
    expect(s.local, isFalse);
    expect(s.install, 'claude plugin install clockifai --marketplace https://clockifai.kysoe.com/api/claude/marketplace.json');
  });

  test('pile locale en http : marketplace du dépôt', () {
    final s = ClaudeCodeSetup('http://localhost:5050', platform: TargetPlatform.linux);
    expect(s.local, isTrue);
    expect(s.install, 'claude plugin install clockifai --marketplace <dépôt Clockifai>/integrations');
  });

  test('lien VSCode : ordinateur et instance en https seulement', () {
    final uri = Uri.parse(ClaudeCodeSetup('https://clockifai.kysoe.com').vscodeLink!);
    expect('${uri.scheme}://${uri.host}${uri.path}', 'vscode://anthropic.claude-code/install-plugin');
    expect(uri.queryParameters, {'plugin': 'clockifai', 'marketplace': 'https://clockifai.kysoe.com/api/claude/marketplace.json'});
    expect(ClaudeCodeSetup('http://localhost:5050').vscodeLink, isNull);
    expect(ClaudeCodeSetup('https://x', platform: TargetPlatform.iOS).vscodeLink, isNull);
    expect(ClaudeCodeSetup('https://x', platform: TargetPlatform.windows).vscodeLink, isNotNull);
  });

  test('un poste connecté : nouveau jeton et premier événement reçu', () {
    final tokens = [
      {'id': 'a', 'name': 'Mac mini', 'last_used_at': '2026-11-05T10:00:00Z'},
      {'id': 'b', 'name': 'MacBook Air', 'last_used_at': null},
    ];
    expect(newComputer(tokens, {'a'}), isNull);
    expect(newComputer(tokens, {'a', 'b'}), isNull);
    tokens[1]['last_used_at'] = '2026-11-05T10:01:00Z';
    expect(newComputer(tokens, {'a'}), 'MacBook Air');
  });

  test('installation de la commande claude selon le système', () {
    expect(ClaudeCodeSetup('https://x').installCli, 'curl -fsSL https://claude.ai/install.sh | bash');
    expect(ClaudeCodeSetup('https://x', platform: TargetPlatform.linux).installCli, 'curl -fsSL https://claude.ai/install.sh | bash');
    expect(ClaudeCodeSetup('https://x', platform: TargetPlatform.windows).installCli, 'irm https://claude.ai/install.ps1 | iex');
  });

  test('dernier événement reçu', () async {
    await initializeDateFormatting('fr');
    final l = lookupAppLocalizations(const Locale('fr'));
    final now = DateTime.utc(2026, 10, 24, 12);
    expect(lastEventLabel(l, 'fr', null, now), 'Aucun événement reçu');
    expect(lastEventLabel(l, 'fr', now.subtract(const Duration(seconds: 20)), now), "Dernier événement à l'instant");
    expect(lastEventLabel(l, 'fr', now.subtract(const Duration(minutes: 7)), now), 'Dernier événement il y a 7 min');
    expect(lastEventLabel(l, 'fr', now.subtract(const Duration(hours: 3, minutes: 5)), now), 'Dernier événement il y a 3 h');
    expect(lastEventLabel(l, 'fr', now.subtract(const Duration(days: 2)), now), startsWith('Dernier événement le 22 oct. 2026'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(lastEventLabel(en, 'en', now.subtract(const Duration(minutes: 7)), now), 'Last event 7 min ago');
  });
}
