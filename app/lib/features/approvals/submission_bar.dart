import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/modules_repository.dart';

/// Bandeau de la feuille de temps : état d'approbation de la période et action de soumission.
/// Pour la feuille d'un collaborateur ([userId] ≠ soi) : état seul, l'approbation se fait dans Approbations.
class SubmissionBar extends StatelessWidget {
  const SubmissionBar({super.key, this.userId, required this.periodStart, required this.periodEnd, required this.totalSeconds});
  final String? userId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final uid = userId ?? session.userId;
    final mine = uid == session.userId;
    return StreamBuilder<List<TimesheetSubmission>>(
      stream: modulesRepo.watchSubmissions(session.workspaceId!, userId: uid),
      builder: (context, snap) {
        final sub = (snap.data ?? const <TimesheetSubmission>[]).where((s) => s.periodStart == dayKey(periodStart)).firstOrNull;
        final status = sub?.status;
        final (icon, color, label) = switch (status) {
          'submitted' => (Icons.hourglass_top, theme.colorScheme.tertiary, l.statusSubmitted),
          'approved' => (Icons.verified, Colors.green, l.statusApproved),
          'rejected' => (Icons.report_gmailerrorred, theme.colorScheme.error, l.statusRejected),
          _ => (Icons.edit_calendar, theme.colorScheme.outline, l.statusNotSubmitted),
        };
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: theme.textTheme.titleSmall?.copyWith(color: color)),
                  if (status == 'rejected' && (sub?.decisionNote?.isNotEmpty ?? false))
                    Text(sub!.decisionNote!, style: theme.textTheme.bodySmall),
                ]),
              ),
              if (mine && (status == null || status == 'withdrawn' || status == 'rejected'))
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.send),
                  label: Text(l.submitForApproval),
                  onPressed: totalSeconds == 0
                      ? null
                      : () async {
                          final note = await _askNote(context, l.submitForApproval);
                          if (note == null) return;
                          await modulesRepo.submitPeriod(
                            workspaceId: session.workspaceId!,
                            userId: session.userId!,
                            start: periodStart,
                            end: periodEnd,
                            totalSeconds: totalSeconds,
                            note: note.isEmpty ? null : note,
                          );
                          if (context.mounted) showSnack(context, l.submittedForApproval(formatHm(totalSeconds)));
                        },
                ),
              if (mine && status == 'submitted')
                TextButton(onPressed: () => modulesRepo.withdrawSubmission(sub!.id), child: Text(l.withdraw)),
            ]),
          ),
        );
      },
    );
  }
}

Future<String?> _askNote(BuildContext context, String title) {
  final c = TextEditingController();
  final l = context.l10n;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(labelText: l.noteOptional)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(l.confirm)),
      ],
    ),
  );
}

Future<String?> askDecisionNote(BuildContext context, String title) => _askNote(context, title);
