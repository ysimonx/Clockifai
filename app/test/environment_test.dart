import 'package:clockifai/config.dart';
import 'package:clockifai/features/auth/login_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serveur local ou production selon l\'URL du backend', () {
    for (final url in [
      'http://localhost:8000',
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8000', // émulateur Android
      'http://192.168.0.84:8000',
      'http://172.20.0.5:8000',
      'http://mac-mini.local:8000',
    ]) {
      expect(isLocalServer(url), isTrue, reason: url);
    }
    for (final url in [
      'https://supabase.clockifai.kysoe.com',
      'https://8.8.8.8',
      'http://172.32.0.1:8000',
      'https://localhost.example.com',
      '',
    ]) {
      expect(isLocalServer(url), isFalse, reason: url);
    }
  });

  testWidgets('écran de connexion : la pastille indique la version lancée', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: EnvironmentBadge()),
    ));
    // Config par défaut : backend local ; avec --dart-define=SUPABASE_URL=https://… : production.
    if (AppConfig.isLocal) {
      expect(find.textContaining('Version locale · ${AppConfig.serverLabel}'), findsOneWidget);
      expect(find.byIcon(Icons.computer), findsOneWidget);
    } else {
      expect(find.textContaining('Production · ${AppConfig.serverLabel}'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    }
  });
}
