import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/shortcuts.dart';
import '../../core/theme.dart';

/// Une touche, dessinée comme sur le clavier.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Text(label, style: theme.textTheme.labelMedium?.copyWith(fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// Aide des raccourcis clavier (touche ?, palette ⌘K).
Future<void> showShortcutsHelp(BuildContext context) {
  final l = context.l10n;
  final theme = Theme.of(context);
  Widget section(String title, List<(List<String>, String)> rows) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(title.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        ),
        for (final (keys, label) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 120, child: Wrap(spacing: 4, children: [for (final k in keys) KeyCap(k)])),
              Expanded(child: Text(label)),
            ]),
          ),
      ]);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.shortcutsTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(l.shortcutsHelp, style: theme.textTheme.bodySmall),
            section(l.shortcutsEverywhere, [
              ([commandKeyLabel, 'K'], l.kbPalette),
              ([commandKeyLabel, 'J'], l.kbAssistant),
              (['N'], l.kbNewEntry),
              (['S'], l.kbTimer),
              ([commandKeyLabel, 'Z'], l.kbUndo),
              (['?'], l.kbHelp),
            ]),
            section(l.timeTracker, [
              (['J', 'K'], l.kbMove),
              (['X'], l.kbSelect),
              (['E'], l.kbEdit),
              (['D'], l.kbDuplicate),
              (['⌫'], l.kbDelete),
              ([l.keyEscape], l.kbClear),
            ]),
            section(l.today, [
              (['↵'], l.kbTodayConfirm),
              (['⌫'], l.kbTodayIgnore),
              (['←', '→'], l.kbTodayShift),
            ]),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.close))],
    ),
  );
}
