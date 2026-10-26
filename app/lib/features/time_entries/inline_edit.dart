import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';

/// Description modifiable sur place (plans/13-ux-moderne.md, lot 1) : un clic la change en champ ; Entrée ou un clic
/// ailleurs enregistre, Échap abandonne. Sans [onSave], simple texte. Pas d'infobulle : le curseur et le survol
/// suffisent, et l'étiquette d'accessibilité reste la description elle-même.
class InlineDescription extends StatefulWidget {
  const InlineDescription({super.key, required this.text, this.onSave});
  final String text;
  final Future<void> Function(String text)? onSave;

  @override
  State<InlineDescription> createState() => _InlineDescriptionState();
}

class _InlineDescriptionState extends State<InlineDescription> {
  final _controller = TextEditingController();
  late final _focus = FocusNode(debugLabel: 'description')..addListener(_onFocus);
  bool _editing = false;

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _start() {
    _controller.text = widget.text;
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.text.length);
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _cancel() => setState(() => _editing = false);

  Future<void> _commit() async {
    if (!_editing) return;
    setState(() => _editing = false);
    final text = _controller.text.trim();
    if (text != widget.text.trim()) await widget.onSave!(text);
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (_editing) {
      return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            hintText: l.noDescription,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    final text = Text(
      widget.text.isEmpty ? l.noDescription : widget.text,
      style: widget.text.isEmpty ? TextStyle(color: theme.colorScheme.outline) : null,
      overflow: TextOverflow.ellipsis,
    );
    if (widget.onSave == null) return text;
    return InkWell(onTap: _start, mouseCursor: SystemMouseCursors.text, borderRadius: BorderRadius.circular(4), child: text);
  }
}

/// Projet et tâche modifiables sur place : un clic ouvre le sélecteur. Sans [onPick], simple étiquette.
class InlineProject extends StatelessWidget {
  const InlineProject({super.key, required this.projectId, this.taskId, this.onPick});
  final String? projectId;
  final String? taskId;
  final Future<void> Function(ProjectPick pick)? onPick;

  @override
  Widget build(BuildContext context) {
    final label = ProjectLabel(projectId: projectId, taskId: taskId, dense: true);
    if (onPick == null) return label;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final pick = await showProjectPicker(context, projectId: projectId, taskId: taskId);
        if (pick == null || (pick.projectId == projectId && pick.taskId == taskId)) return;
        await onPick!(pick);
      },
      child: label,
    );
  }
}
