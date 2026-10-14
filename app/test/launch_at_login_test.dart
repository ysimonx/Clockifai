import 'package:clockifai/features/settings/settings_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const channel = MethodChannel('clockifai/launch_at_login');

void main() {
  /// Le système simulé : un statut, et la trace des appels reçus.
  late String systemStatus;
  late List<MethodCall> calls;

  Future<void> pump(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'set') systemStatus = call.arguments == true ? 'enabled' : 'disabled';
      return call.method == 'openSettings' ? null : systemStatus;
    });
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: LaunchAtLoginTile()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => calls = []);

  testWidgets('ouverture de session : lu dans le système, activé d\'un clic', (tester) async {
    systemStatus = 'disabled';
    await pump(tester);
    expect(find.text("Démarrer à l'ouverture de session"), findsOneWidget);
    expect(find.text("Clockifai s'ouvre dans la barre de menus, sans fenêtre."), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'set');
    expect(calls.last.arguments, true);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('ouverture de session à autoriser : lien vers les Réglages Système', (tester) async {
    systemStatus = 'requiresApproval';
    await pump(tester);
    expect(find.textContaining('Réglages Système > Général > Ouverture'), findsOneWidget);
    await tester.tap(find.text('Ouvrir les Réglages'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'openSettings');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('ouverture de session indisponible (macOS 12, autres plateformes) : rien d\'affiché', (tester) async {
    systemStatus = 'unavailable';
    await pump(tester);
    expect(find.byType(SwitchListTile), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
