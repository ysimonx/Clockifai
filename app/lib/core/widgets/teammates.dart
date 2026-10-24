import 'package:flutter/material.dart';

import '../../data/drift/database.dart';
import '../l10n.dart';
import '../team_rights.dart';

/// Nom affiché d'un membre (nom, sinon email).
String memberName(WorkspaceMember? m) =>
    m == null ? '?' : (m.displayName.isNotEmpty ? m.displayName : (m.email ?? '?'));

/// Bandeau de la feuille de temps et du calendrier pour les chefs d'équipe et managers :
/// choix de la personne affichée (équivalent du sélecteur « Teammates » de Clockify)
/// et rappel quand on saisit, ou consulte seulement, le temps de quelqu'un d'autre.
/// Invisible pour qui ne voit que son propre temps.
class TeammateBar extends StatelessWidget {
  const TeammateBar({super.key, required this.userId, required this.onChanged});
  final String userId;
  final ValueChanged<String> onChanged;

  /// Personne effectivement affichée : [userId] s'il est toujours visible, sinon soi-même.
  static String resolve(TeamRights rights, String? userId) =>
      userId != null && rights.visibleMembers.any((m) => m.userId == userId) ? userId : rights.me;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final rights = TeamRights.of(context);
    final members = rights.visibleMembers;
    if (members.length < 2) return const SizedBox.shrink();
    final selected = members.where((m) => m.userId == userId).firstOrNull;
    final name = memberName(selected);
    final editable = rights.canEditTimeOf(userId);
    final hint = userId == rights.me
        ? null
        : rights.isAgent(userId) && editable
            ? l.agentTimeOf(name)
            : (editable ? l.enteringFor(name) : l.readOnlyTimeOf(name));
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.people_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              child: DropdownButton<String>(
                value: selected?.userId,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                hint: Text(l.teammate),
                items: [
                  for (final m in members)
                    DropdownMenuItem(value: m.userId, child: Text(memberName(m), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => v == null ? null : onChanged(v),
              ),
            ),
          ]),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(hint, style: theme.textTheme.bodySmall?.copyWith(
                color: editable ? theme.colorScheme.primary : theme.colorScheme.outline,
              )),
            ),
        ]),
      ),
    );
  }
}

/// Choix multiple de personnes (saisie pour plusieurs collaborateurs, membres d'un groupe…).
Future<Set<String>?> showMembersPicker(
  BuildContext context, {
  required String title,
  required List<WorkspaceMember> members,
  required Set<String> selected,
  String? help,
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: (_) => _MembersPickerDialog(title: title, members: members, selected: selected, help: help),
  );
}

class _MembersPickerDialog extends StatefulWidget {
  const _MembersPickerDialog({required this.title, required this.members, required this.selected, this.help});
  final String title;
  final List<WorkspaceMember> members;
  final Set<String> selected;
  final String? help;

  @override
  State<_MembersPickerDialog> createState() => _MembersPickerDialogState();
}

class _MembersPickerDialogState extends State<_MembersPickerDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final all = widget.members.every((m) => _selected.contains(m.userId));
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.help != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(widget.help!, style: Theme.of(context).textTheme.bodySmall),
            ),
          CheckboxListTile(
            value: all,
            title: Text(l.selectAll, style: const TextStyle(fontWeight: FontWeight.w600)),
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.addAll(widget.members.map((m) => m.userId));
              } else {
                _selected.clear();
              }
            }),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(children: [
              for (final m in widget.members)
                CheckboxListTile(
                  dense: true,
                  value: _selected.contains(m.userId),
                  secondary: CircleAvatar(radius: 14, child: Text(memberName(m)[0].toUpperCase())),
                  title: Text(memberName(m)),
                  onChanged: (v) => setState(() => v == true ? _selected.add(m.userId) : _selected.remove(m.userId)),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: Text(l.apply)),
      ],
    );
  }
}
