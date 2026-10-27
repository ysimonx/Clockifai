import 'package:clockifai/core/text_search.dart';
import 'package:clockifai/features/commands/command_palette.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Palette ⌘K et recherche sans accents (plans/13-ux-moderne.md, lot 1).
void main() {
  test('recherche : sans accents ni majuscules, chaque mot commence un mot du texte', () {
    expect(searchRank('rap', 'Rapports'), 0);
    expect(searchRank('sombre', 'Apparence : sombre'), 1);
    expect(searchRank('ECHEANCE', 'Échéance du devis'), 0);
    expect(searchRank('appel', 'Rappels par SMS'), isNull, reason: 'pas au milieu d’un mot');
    expect(searchRank('bou site', 'Site de la boulangerie'), 3 + 0);
    expect(searchRank('  ', 'Tout'), 0);
  });

  testWidgets('la palette filtre, les flèches choisissent, Entrée exécute', (tester) async {
    PaletteCommand? chosen;
    final commands = [
      PaletteCommand(icon: Icons.play_arrow, title: 'Démarrer le chronomètre', shortcut: 'S', run: () {}),
      PaletteCommand(icon: Icons.bar_chart, title: 'Rapports', subtitle: 'Aller à', run: () {}),
      PaletteCommand(icon: Icons.timer, title: 'Suivi du temps', subtitle: 'Aller à', run: () {}),
      PaletteCommand(icon: Icons.play_circle, title: 'Site de la boulangerie', subtitle: 'Démarrer le chronomètre sur ce projet', always: false, run: () {}),
    ];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => chosen = await showDialog<PaletteCommand>(context: context, builder: (_) => CommandPalette(commands: commands)),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.text('Site de la boulangerie'), findsNothing, reason: 'un projet n’apparaît qu’en cherchant');
    expect(find.text('Rapports'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'demar');
    await tester.pump();
    expect(find.text('Démarrer le chronomètre'), findsOneWidget);
    expect(find.text('Site de la boulangerie'), findsOneWidget, reason: '« démarrer » dans son sous-titre');
    expect(find.text('Rapports'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(chosen?.title, 'Site de la boulangerie');

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pump();
    expect(find.text('Aucune commande'), findsOneWidget);
  });
}
