import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/teammates.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/modules_repository.dart';
import '../today/day_recap.dart' show RecapNotifications;

/// Relance reçue (plans/13-ux-moderne.md, lot 8) : un bandeau tant qu'elle n'est pas vue, et une notification à son
/// arrivée (Mac, téléphone). « Ouvrir la feuille » mène à la semaine visée.
class ReminderBanner extends StatefulWidget {
  const ReminderBanner({super.key});

  @override
  State<ReminderBanner> createState() => _ReminderBannerState();
}

class _ReminderBannerState extends State<ReminderBanner> {
  final _notified = <String>{};

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    if (session.workspaceId == null || session.userId == null) return const SizedBox.shrink();
    return StreamBuilder<List<Reminder>>(
      stream: modulesRepo.watchReminders(session.workspaceId!, userId: session.userId, unseen: true),
      builder: (context, snap) {
        final r = (snap.data ?? const <Reminder>[]).firstOrNull;
        if (r == null) return const SizedBox.shrink();
        final who = memberName(r.createdBy == null ? null : catalog.memberOf(r.createdBy!));
        final week = parseDay(r.periodStart);
        final text = l.reminderBanner(who, DateFormat.MMMd(context.localeTag).format(week));
        if (_notified.add(r.id)) RecapNotifications.instance.alert(l.reminderTitle, text);
        return Material(
          color: theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Icon(Icons.notifications_active_outlined, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onTertiaryContainer))),
              TextButton(onPressed: () => modulesRepo.markReminderSeen(r.id), child: Text(l.reminderOk)),
              FilledButton.tonal(
                onPressed: () {
                  modulesRepo.markReminderSeen(r.id);
                  context.go('/timesheet?week=${r.periodStart}');
                },
                child: Text(l.reminderOpen),
              ),
            ]),
          ),
        );
      },
    );
  }
}
