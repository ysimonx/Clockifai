import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../today/day_plan.dart' show atMinute, minuteOf;
import 'entry_groups.dart';

/// Une ligne du « Suivi du temps » : une entrée, ou un groupe d'entrées similaires.
class EntryLine {
  const EntryLine(this.key, this.rows, {required this.selectable, this.group});
  final String key;
  final List<EntryRow> rows;

  /// Modifiable par l'utilisateur : droits, entrée verrouillée, période close.
  final bool selectable;
  final EntryGroup? group;
}

String entryLineKey(String entryId) => 'e:$entryId';
String groupLineKey(DateTime day, EntryGroup group) => 'g:$day ${group.key}';

/// Mêmes conditions que le dialogue d'entrée : le serveur refuserait une entrée verrouillée ou d'une période close.
bool entryEditable(SessionController session, TeamRights rights, TimeEntry e) {
  final lockDate = DateTime.tryParse(session.workspace?.lockEntriesBefore ?? '');
  final locked = !session.isAdmin && (e.locked || (lockDate != null && e.startAt.toLocal().isBefore(lockDate)));
  return !locked && rights.canEditTimeOf(e.userId);
}

/// Sélection multiple et curseur clavier du « Suivi du temps » (plans/13-ux-moderne.md, lot 1). La page donne ses
/// lignes dans l'ordre affiché à chaque construction ([setLines]) ; les lignes lisent la sélection.
class EntrySelection extends ChangeNotifier {
  final _ids = <String>{};
  List<EntryLine> _lines = const [];
  String? _cursor;
  final _keys = <String, GlobalKey>{};

  bool get isActive => _ids.isNotEmpty;
  String? get cursor => _cursor;
  EntryLine? get cursorLine => _lines.where((l) => l.key == _cursor).firstOrNull;
  bool isSelected(String entryId) => _ids.contains(entryId);

  /// Les entrées sélectionnées, dans l'ordre affiché.
  List<EntryRow> get selectedRows => [
        for (final line in _lines)
          for (final r in line.rows)
            if (_ids.contains(r.entry.id)) r,
      ];

  /// Clé du widget d'une ligne, pour la faire défiler jusqu'à l'écran.
  GlobalKey keyFor(String lineKey) => _keys.putIfAbsent(lineKey, GlobalKey.new);

  /// Lignes visibles, dans l'ordre ; la sélection oublie ce qui a disparu (supprimé, verrouillé, plus chargé).
  void setLines(List<EntryLine> lines) {
    _lines = lines;
    final visible = {
      for (final line in lines)
        if (line.selectable)
          for (final r in line.rows) r.entry.id,
    };
    _ids.removeWhere((id) => !visible.contains(id));
    if (_cursor != null && !lines.any((l) => l.key == _cursor)) _cursor = null;
    _keys.removeWhere((k, _) => !lines.any((l) => l.key == k));
  }

  /// Tout (true), rien (false) ou une partie d'un groupe (null).
  bool? stateOf(EntryLine line) {
    final n = line.rows.where((r) => _ids.contains(r.entry.id)).length;
    return n == 0 ? false : (n == line.rows.length ? true : null);
  }

  void toggle(EntryLine line) {
    if (!line.selectable) return;
    final ids = [for (final r in line.rows) r.entry.id];
    if (stateOf(line) == true) {
      _ids.removeAll(ids);
    } else {
      _ids.addAll(ids);
    }
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty && _cursor == null) return;
    _ids.clear();
    _cursor = null;
    notifyListeners();
  }

  /// J / K : ligne suivante ou précédente, amenée à l'écran.
  void moveCursor(int delta) {
    if (_lines.isEmpty) return;
    final i = _lines.indexWhere((l) => l.key == _cursor);
    final next = i < 0 ? (delta > 0 ? 0 : _lines.length - 1) : (i + delta).clamp(0, _lines.length - 1);
    _cursor = _lines[next].key;
    notifyListeners();
    final target = _keys[_cursor]?.currentContext;
    if (target != null) Scrollable.ensureVisible(target, alignment: 0.3, duration: const Duration(milliseconds: 120));
  }
}

// ------------------------------------------------------------------ actions sur plusieurs entrées, avec Annuler
// Chacune renvoie vrai si elle a eu lieu (faux : sélecteur fermé, règle du workspace).

Future<bool> deleteRows(BuildContext context, List<EntryRow> rows) async {
  final l = context.l10n;
  final before = await entriesRepo.deleteMany([for (final r in rows) r.entry.id]);
  if (context.mounted) showUndo(context, l.entriesDeleted(before.length), () => entriesRepo.restore(before));
  return true;
}

Future<bool> setBillable(BuildContext context, List<EntryRow> rows, bool billable) async {
  final l = context.l10n;
  final before = [for (final r in rows) r.entry];
  await entriesRepo.updateEach(before, billable: billable);
  if (context.mounted) showUndo(context, l.entriesUpdated(before.length), () => entriesRepo.restore(before));
  return true;
}

/// Projet et tâche : le taux suit le nouveau projet, comme dans le dialogue.
Future<bool> pickProjectFor(BuildContext context, List<EntryRow> rows) async {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final first = rows.first.entry;
  final pick = await showProjectPicker(context, projectId: first.projectId, taskId: first.taskId);
  if (pick == null || !context.mounted) return false;
  if (session.workspace!.requireProject && pick.projectId == null) {
    showSnack(context, l.projectRequired);
    return false;
  }
  final before = [for (final r in rows) r.entry];
  await entriesRepo.updateEach(
    before,
    projectId: pick.projectId,
    clearProject: pick.projectId == null,
    taskId: pick.taskId,
    clearTask: pick.taskId == null,
    hourlyRateFor: (e) => pick.projectId != e.projectId ? catalog.rateFor(projectId: pick.projectId, userId: e.userId) : null,
  );
  if (context.mounted) showUndo(context, l.entriesUpdated(before.length), () => entriesRepo.restore(before));
  return true;
}

/// Copie des entrées : le jour [day] (null : le leur), aux mêmes heures. Annuler supprime les copies.
Future<bool> duplicateRows(BuildContext context, List<EntryRow> rows, {DateTime? day}) async {
  final l = context.l10n;
  final me = context.read<SessionController>().userId;
  final ids = <String>[];
  for (final r in rows) {
    final e = r.entry;
    final end = e.endAt ?? DateTime.now().toUtc();
    final start = day == null ? e.startAt : atMinute(day, minuteOf(e.startAt, e.startAt.toLocal()));
    ids.add(await entriesRepo.createManual(
      workspaceId: e.workspaceId,
      userId: e.userId,
      start: start,
      end: start.add(end.difference(e.startAt)),
      createdBy: me,
      draft: EntryDraft(
        description: e.description,
        projectId: e.projectId,
        taskId: e.taskId,
        billable: e.billable,
        hourlyRateCents: e.hourlyRateCents,
        tagIds: r.tagIds,
      ),
    ));
  }
  if (context.mounted) showUndo(context, l.entriesDuplicated(ids.length), () => entriesRepo.deleteMany(ids));
  return true;
}

Future<bool> duplicateRowsTo(BuildContext context, List<EntryRow> rows) async {
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 1, 12, 31),
  );
  if (day == null || !context.mounted) return false;
  return duplicateRows(context, rows, day: day);
}

/// Survol de la souris (case à cocher révélée).
class HoverRegion extends StatefulWidget {
  const HoverRegion({super.key, required this.builder});
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.builder(context, _hovered),
      );
}

/// Fond d'une ligne : sélectionnée, ou sous le curseur clavier (filet à gauche).
BoxDecoration lineDecoration(BuildContext context, {required bool selected, required bool cursor}) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
    border: Border(left: BorderSide(color: cursor ? scheme.primary : Colors.transparent, width: 3)),
  );
}

/// Case à cocher d'une ligne (entrée ou groupe) ; null : pas de sélection sur cette page.
class LineCheckbox extends StatelessWidget {
  const LineCheckbox({super.key, required this.line, required this.visible, this.compact = false});
  final EntryLine line;

  /// Affichée (survol, sélection en cours) ; sinon la place reste réservée.
  final bool visible;

  /// Écran étroit : pas de place réservée tant que rien n'est sélectionné (appui long pour commencer).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<EntrySelection>();
    final state = selection.stateOf(line);
    if (compact && !selection.isActive) return const SizedBox.shrink();
    final show = line.selectable && (visible || selection.isActive || state != false);
    return SizedBox(
      width: 36,
      child: show
          ? Checkbox(
              tristate: line.group != null,
              value: state,
              semanticLabel: context.l10n.selectEntry,
              onChanged: (_) => selection.toggle(line),
            )
          : null,
    );
  }
}

/// Barre d'actions de la sélection, en bas du « Suivi du temps ».
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final selection = context.watch<EntrySelection>();
    final rows = selection.selectedRows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final total = rows.fold<int>(0, (s, r) => s + r.seconds);
    Future<void> then(Future<bool> action) async {
      if (await action) selection.clear();
    }

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.inverseSurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: IconTheme(
          data: IconThemeData(color: theme.colorScheme.onInverseSurface),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
            IconButton(tooltip: l.kbClear, icon: const Icon(Icons.close), onPressed: selection.clear),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${l.selectedCount(rows.length)} · ${formatHm(total)}',
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onInverseSurface)),
            ),
            IconButton(tooltip: l.project, icon: const Icon(Icons.folder_outlined), onPressed: () => then(pickProjectFor(context, rows))),
            IconButton(tooltip: l.billable, icon: const Icon(Icons.attach_money), onPressed: () => then(setBillable(context, rows, true))),
            IconButton(tooltip: l.nonBillable, icon: const Icon(Icons.money_off), onPressed: () => then(setBillable(context, rows, false))),
            IconButton(tooltip: l.duplicateTo, icon: const Icon(Icons.copy_all_outlined), onPressed: () => then(duplicateRowsTo(context, rows))),
            IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: () => then(deleteRows(context, rows))),
          ]),
        ),
      ),
    );
  }
}
