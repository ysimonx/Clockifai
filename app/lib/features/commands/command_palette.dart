import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/display_prefs.dart';
import '../../core/guide.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/shortcuts.dart' show commandKeyLabel;
import '../../core/text_search.dart';
import '../../core/widgets/app_shell.dart' show navDestinations;
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../assistant/assistant.dart';
import '../time_entries/entry_dialog.dart';
import '../time_entries/time_entries_page.dart' show continueEntry;
import '../timer/timer_control.dart' show toggleTimer;
import '../timer/timer_rules.dart';
import 'shortcuts_help.dart';

/// Une commande de la palette ⌘K.
class PaletteCommand {
  const PaletteCommand({required this.icon, required this.title, this.subtitle, this.shortcut, this.always = true, required this.run});
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Touche seule qui fait la même chose (affichée à droite).
  final String? shortcut;

  /// Faux : n'apparaît qu'en cherchant (un projet parmi beaucoup, l'apparence).
  final bool always;
  final FutureOr<void> Function() run;
}

/// Palette de commandes ⌘K (plans/13-ux-moderne.md, lot 1) : chronomètre, nouvelle entrée, entrées récentes à
/// reprendre, pages, démarrer sur un projet, apparence, raccourcis, guide. La commande choisie s'exécute une fois
/// la palette fermée.
Future<void> showCommandPalette(BuildContext context) async {
  final commands = await paletteCommands(context);
  if (!context.mounted) return;
  final chosen = await showDialog<PaletteCommand>(context: context, builder: (_) => CommandPalette(commands: commands));
  await chosen?.run();
}

Future<List<PaletteCommand>> paletteCommands(BuildContext context) async {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final prefs = context.read<DisplayPrefs>();
  final router = GoRouter.of(context);
  final ws = session.workspaceId!, me = session.userId!;
  final running = await entriesRepo.watchRunningAll(ws, me).first;
  final recent = await entriesRepo.watchRecent(ws, me).first;
  final assistantOn = await AssistantApi.enabled();
  if (!context.mounted) return const [];
  return [
    if (assistantOn)
      PaletteCommand(icon: Icons.auto_awesome_outlined, title: l.assistantTitle, shortcut: '${commandKeyLabel}J', run: () => showAssistant(context)),
    PaletteCommand(
        icon: running.isEmpty ? Icons.play_arrow : Icons.stop,
        title: running.isEmpty ? l.cmdStartTimer : l.cmdStopTimer,
        shortcut: 'S',
        run: toggleTimer),
    PaletteCommand(icon: Icons.add, title: l.kbNewEntry, shortcut: 'N', run: () => showEntryDialog(context)),
    for (final r in recent)
      PaletteCommand(
        icon: Icons.replay,
        title: r.entry.description.isEmpty ? l.noDescription : r.entry.description,
        subtitle: '${l.cmdResume} · ${catalog.project(r.entry.projectId)?.name ?? l.noProject}',
        run: () => continueEntry(context, r),
      ),
    for (final d in navDestinations(context))
      PaletteCommand(icon: d.icon, title: d.label, subtitle: l.cmdGoTo, run: () => router.go(d.path)),
    for (final p in catalog.activeProjects)
      PaletteCommand(
        icon: Icons.play_circle_outline,
        title: p.name,
        subtitle: [l.cmdStartOnProject, ?catalog.client(p.clientId)?.name].join(' · '),
        always: false,
        run: () => _startOn(context, p),
      ),
    PaletteCommand(icon: Icons.dark_mode_outlined, title: l.cmdThemeDark, always: false, run: () => prefs.setThemeMode(ThemeMode.dark)),
    PaletteCommand(icon: Icons.light_mode_outlined, title: l.cmdThemeLight, always: false, run: () => prefs.setThemeMode(ThemeMode.light)),
    PaletteCommand(icon: Icons.brightness_auto_outlined, title: l.cmdThemeSystem, always: false, run: () => prefs.setThemeMode(ThemeMode.system)),
    PaletteCommand(icon: Icons.keyboard_outlined, title: l.shortcutsTitle, shortcut: '?', run: () => showShortcutsHelp(context)),
    PaletteCommand(icon: Icons.help_outline, title: l.userGuide, run: () => openGuide(context)),
    PaletteCommand(icon: Icons.logout, title: l.signOut, always: false, run: () => confirmSignOut(context)),
  ];
}

/// Démarre un chronomètre sur [project], aux règles de la barre (projet ou description exigés, un par tâche).
Future<void> _startOn(BuildContext context, Project project) async {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final ws = session.workspace!, me = session.userId!;
  final running = await entriesRepo.watchRunningAll(ws.id, me).first;
  if (!context.mounted) return;
  final blocked = timerRuleViolation(l, ws, description: '', projectId: project.id) ??
      alreadyRunningViolation(l, running, description: '', projectId: project.id, taskId: null);
  if (blocked != null) return showSnack(context, blocked);
  await entriesRepo.start(
    workspaceId: ws.id,
    userId: me,
    draft: EntryDraft(
      description: '',
      projectId: project.id,
      billable: catalog.billableFor(projectId: project.id, userId: me),
      hourlyRateCents: catalog.rateFor(projectId: project.id, userId: me),
    ),
    maxRunning: session.runningTimersLimit,
  );
}

/// La palette : un champ de recherche (sans accents, par début de mot) et la liste ; ↑ ↓ choisissent, Entrée
/// exécute, Échap ferme.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.commands});
  final List<PaletteCommand> commands;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  static const _rowHeight = 56.0;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _index = 0;

  List<PaletteCommand> get _matches {
    final q = _query.text.trim();
    if (q.isEmpty) return widget.commands.where((c) => c.always).toList();
    final ranked = [
      for (final (i, c) in widget.commands.indexed)
        if (searchRank(q, '${c.title} ${c.subtitle ?? ''}') case final rank?) (rank, i, c),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [for (final r in ranked) r.$3];
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _index = (_index + delta).clamp(0, count - 1));
    final top = _index * _rowHeight;
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) _scroll.jumpTo(top);
    if (top + _rowHeight > _scroll.offset + view) _scroll.jumpTo(top + _rowHeight - view);
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final matches = _matches;
    if (_index >= matches.length) _index = matches.isEmpty ? 0 : matches.length - 1;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1, matches.length),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1, matches.length),
            },
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                labelText: l.commandPalette,
                hintText: l.commandPaletteHint,
                prefixIcon: const Icon(Icons.search),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
              onChanged: (_) => setState(() => _index = 0),
              onSubmitted: (_) {
                if (matches.isNotEmpty) Navigator.pop(context, matches[_index]);
              },
            ),
          ),
          const Divider(height: 1),
          if (matches.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Text(l.commandNoResult, style: TextStyle(color: theme.colorScheme.outline)))
          else
            Flexible(
              child: ListView.builder(
                controller: _scroll,
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemExtent: _rowHeight,
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final c = matches[i];
                  return ListTile(
                    selected: i == _index,
                    selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    leading: Icon(c.icon),
                    title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: c.subtitle == null ? null : Text(c.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: c.shortcut == null ? null : KeyCap(c.shortcut!),
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}
