import 'dart:convert';

import 'package:clockifai/features/integrations/claude_code.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  test('instance en https : marketplace servie par l\'instance', () {
    final s = ClaudeCodeSetup('https://clockifai.kysoe.com/');
    expect(s.local, isFalse);
    expect(s.install, 'claude plugin marketplace add https://clockifai.kysoe.com/api/claude/marketplace.json\n'
        'claude plugin install clockifai@clockifai');
    expect(s.configure, 'pbpaste | claude plugin configure clockifai@clockifai --values-stdin');
  });

  test('pile locale en http : marketplace du dépôt, adresse donnée à l\'installation', () {
    final s = ClaudeCodeSetup('http://localhost:5050', platform: TargetPlatform.linux);
    expect(s.local, isTrue);
    expect(s.install, 'claude plugin marketplace add <dépôt Clockifai>/integrations\n'
        'claude plugin install clockifai@clockifai-dev --config url=http://localhost:5050');
    expect(s.configure, 'wl-paste | claude plugin configure clockifai@clockifai-dev --values-stdin');
    expect(ClaudeCodeSetup('https://x', platform: TargetPlatform.windows).configure, startsWith('Get-Clipboard | '));
  });

  test('le presse-papiers reçoit l\'objet JSON attendu par --values-stdin', () {
    expect(jsonDecode(ClaudeCodeSetup.clipboardValue('clk_0123')), {'token': 'clk_0123'});
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
