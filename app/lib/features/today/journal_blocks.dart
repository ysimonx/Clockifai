part of 'today_page.dart';

// Blocs de la frise « Aujourd'hui » : modèle, couleurs et dessin (sortis de today_page.dart, plan 17).

enum _Kind { logged, draft, fresh }

/// Un bloc de la ligne « Vous » : entrée saisie, proposition ou nouvelle entrée en cours de création.
class _Block {
  _Block({required this.id, required this.kind, required this.span, required this.title, this.projectId, this.taskId, this.entry, this.draft,
      this.fixed = false});
  final String id;
  final _Kind kind;
  final Span span;
  final String title;
  final String? projectId;
  final String? taskId;
  final TimeEntry? entry;
  final Draft? draft;

  /// Entrée qu'on ne déplace pas ici : verrouillée, dans une période verrouillée, d'une autre personne sans droit, ou à
  /// cheval sur un autre jour (sa plage est coupée à minuit).
  final bool fixed;

  bool get running => entry != null && entry!.endAt == null;
  bool get movable => kind != _Kind.logged || (!running && !fixed);
}

class _DraftEdit {
  const _DraftEdit({this.span, this.title, this.projectId, this.taskId, this.projectSet = false});
  final Span? span;
  final String? title;
  final String? projectId;
  final String? taskId;
  final bool projectSet;
  _DraftEdit copyWith({Span? span, String? title, String? projectId, String? taskId, bool? projectSet}) => _DraftEdit(
        span: span ?? this.span,
        title: title ?? this.title,
        projectId: projectSet == true ? projectId : this.projectId,
        taskId: projectSet == true ? taskId : this.taskId,
        projectSet: projectSet ?? this.projectSet,
      );
}

enum _Drag { create, move, left, right }

Color _projectColor(CatalogController catalog, String? projectId, ThemeData theme) {
  final p = catalog.project(projectId);
  return p == null ? theme.colorScheme.outline : colorFromHex(p.color);
}

/// D'où vient une proposition : « Habitude », « Agenda », « Chantier »…
String _sourceLabel(AppLocalizations l, DraftSource? source) => switch (source) {
      DraftSource.presence => l.journalSourcePresence,
      DraftSource.calendar => l.journalSourceCalendar,
      DraftSource.commits => l.journalSourceCommits,
      DraftSource.habit => l.journalSourceHabit,
      DraftSource.planning => l.journalSourcePlanning,
      null => '',
    };

/// Lignes des heures sur une piste de la frise.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.hours, required this.color});
  final List<double> hours;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(r, Paint()
      ..color = color
      ..style = PaintingStyle.stroke);
    for (final x in hours) {
      if (x <= 0 || x >= size.width) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.hours != hours || old.color != color;
}

/// Bloc de la frise : fond, bord plein ou pointillé, trame hachurée (Claude, créneau vide), contour de sélection.
class _BlockPainter extends CustomPainter {
  _BlockPainter({required this.fill, required this.border, this.dashed = false, this.hatch, this.selected, this.runningEdge});
  final Color fill;
  final Color border;
  final bool dashed;
  final Color? hatch;
  final Color? selected;
  final Color? runningEdge;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(9));
    canvas.drawRRect(rrect, Paint()..color = fill);
    if (hatch != null) {
      canvas.save();
      canvas.clipRRect(rrect);
      final hp = Paint()
        ..color = hatch!
        ..strokeWidth = 3;
      for (double x = -size.height; x < size.width; x += 9) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hp);
      }
      canvas.restore();
    }
    final bp = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 1.5 : 1;
    if (dashed) {
      final path = Path()..addRRect(rrect.deflate(0.75));
      for (final metric in path.computeMetrics()) {
        for (double d = 0; d < metric.length; d += 9) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), bp);
        }
      }
    } else {
      canvas.drawRRect(rrect.deflate(0.5), bp);
    }
    if (runningEdge != null) {
      final ep = Paint()
        ..color = runningEdge!
        ..strokeWidth = 2;
      for (double y = 4; y < size.height - 4; y += 7) {
        canvas.drawLine(Offset(size.width - 1, y), Offset(size.width - 1, math.min(y + 4, size.height - 4)), ep);
      }
    }
    if (selected != null) {
      canvas.drawRRect(
          rrect.inflate(1.5),
          Paint()
            ..color = selected!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_BlockPainter old) =>
      old.fill != fill || old.border != border || old.dashed != dashed || old.hatch != hatch || old.selected != selected || old.runningEdge != runningEdge;
}
