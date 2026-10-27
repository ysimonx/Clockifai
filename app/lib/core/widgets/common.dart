import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/drift/database.dart';
import '../catalog.dart';
import '../format.dart';
import '../l10n.dart';

/// Pastille de couleur (projet, tag).
class ColorDot extends StatelessWidget {
  const ColorDot(this.hex, {super.key, this.size = 10});
  final String hex;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: colorFromHex(hex), shape: BoxShape.circle),
      );
}

/// « ● Projet · Client — Tâche » ou « Sans projet ».
class ProjectLabel extends StatelessWidget {
  const ProjectLabel({super.key, required this.projectId, this.taskId, this.dense = false});
  final String? projectId;
  final String? taskId;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final theme = Theme.of(context);
    final project = catalog.project(projectId);
    final style = dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium;
    if (project == null) {
      return Text(context.l10n.noProject, style: style?.copyWith(color: theme.colorScheme.outline));
    }
    final client = catalog.client(project.clientId);
    final task = catalog.taskPath(taskId);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ColorDot(project.color),
      const SizedBox(width: 6),
      Flexible(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: project.name, style: TextStyle(color: colorFromHex(project.color), fontWeight: FontWeight.w600)),
            if (task != null) TextSpan(text: ' : $task'),
            if (client != null) TextSpan(text: ' · ${client.name}', style: TextStyle(color: theme.colorScheme.outline)),
          ]),
          style: style,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

/// Puces des tags d'une entrée.
class TagChips extends StatelessWidget {
  const TagChips(this.tagIds, {super.key});
  final List<String> tagIds;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final tags = tagIds.map(catalog.tag).whereType<Tag>().toList();
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final t in tags)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: colorFromHex(t.color).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(t.name, style: theme.textTheme.labelSmall?.copyWith(color: colorFromHex(t.color))),
        ),
    ]);
  }
}

/// Durée écoulée depuis [start], rafraîchie chaque seconde.
class ElapsedText extends StatefulWidget {
  const ElapsedText(this.start, {super.key, this.style});
  final DateTime start;
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        formatClock(DateTime.now().toUtc().difference(widget.start).inSeconds),
        style: widget.style,
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// En-tête de page : titre + actions, largeur contrainte sur grand écran.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, required this.child, this.actions = const [], this.maxWidth = 1100});
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
              ...actions,
            ]),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context,
    {required String title, String? message, String? confirmLabel, String? cancelLabel, bool destructive = true}) async {
  final l = context.l10n;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel ?? l.cancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? l.delete),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// La dernière action encore annulable (son bandeau est affiché), pour ⌘Z.
Future<void> Function()? _pendingUndo;

/// « Annuler plutôt que confirmer » (plans/13-ux-moderne.md, principe 5) : l'action est déjà faite, le bandeau propose
/// de la défaire quelques secondes ; ⌘Z fait de même ([undoLast]). `persist: false` : sinon un bandeau à action
/// reste affiché jusqu'à un clic.
void showUndo(BuildContext context, String message, Future<void> Function() undo) {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  late final Future<void> Function() once;
  once = () {
    if (_pendingUndo == once) _pendingUndo = null;
    return undo();
  };
  messenger.hideCurrentSnackBar();
  _pendingUndo = once;
  messenger
      .showSnackBar(SnackBar(
        content: Text(message),
        persist: false,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: l.undo, onPressed: () => once()),
      ))
      .closed
      .then((_) {
    if (_pendingUndo == once) _pendingUndo = null;
  });
}

/// ⌘Z : défait la dernière action dont le bandeau « Annuler » est encore affiché. Faux s'il n'y en a pas.
bool undoLast(BuildContext context) {
  final undo = _pendingUndo;
  if (undo == null) return false;
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  undo();
  return true;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Sélecteur de couleur parmi la palette projet.
class ColorPalettePicker extends StatelessWidget {
  const ColorPalettePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in projectPalette)
          InkWell(
            onTap: () => onChanged(c),
            customBorder: const CircleBorder(),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colorFromHex(c),
                shape: BoxShape.circle,
                border: c.toUpperCase() == value.toUpperCase()
                    ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                    : null,
              ),
            ),
          ),
      ]);
}
