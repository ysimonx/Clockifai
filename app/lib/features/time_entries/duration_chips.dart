import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../today/day_plan.dart';

/// Durée au pouce (plans/13-ux-moderne.md, lot 9) : ±15 min sur la fin, durées toutes faites, matin ou après-midi
/// de la journée type. Une rangée de pastilles qui passe à la ligne ; sans son rappel, un groupe n'est pas affiché.
class DurationChips extends StatelessWidget {
  const DurationChips({super.key, this.onNudge, this.onLength, this.onRange, this.typical = TypicalDay.fallback});

  /// Fin décalée de ces minutes (−15 ou +15).
  final ValueChanged<int>? onNudge;

  /// Durée fixée, en minutes, depuis le début.
  final ValueChanged<int>? onLength;

  /// Début et fin posés ensemble (matin, après-midi).
  final void Function(TimeOfDay start, TimeOfDay end)? onRange;

  final TypicalDay typical;

  static TimeOfDay _time(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  /// Matin et après-midi : de part et d'autre de la pause, sinon la journée coupée en deux.
  (Span, Span) get halves {
    final lunch = typical.lunch;
    if (lunch != null) return (Span(typical.start, lunch.start), Span(lunch.end, typical.end));
    final mid = (typical.start + (typical.end - typical.start) ~/ 2) ~/ 15 * 15;
    return (Span(typical.start, mid), Span(mid, typical.end));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget chip(String label, VoidCallback onTap) => ActionChip(
          label: Text(label),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: onTap,
        );
    final (morning, afternoon) = halves;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      if (onNudge case final nudge?) ...[
        chip('−15 min', () => nudge(-15)),
        chip('+15 min', () => nudge(15)),
      ],
      if (onLength case final length?)
        for (final m in const [30, 60, 120, 240]) chip(m < 60 ? '$m min' : '${m ~/ 60} h', () => length(m)),
      if (onRange case final range?) ...[
        chip(l.morning, () => range(_time(morning.start), _time(morning.end))),
        chip(l.afternoon, () => range(_time(afternoon.start), _time(afternoon.end))),
      ],
    ]);
  }
}
