import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/drift/database.dart';
import '../l10n.dart';
import 'common.dart';

/// Ouvre le ticket du client d'une tâche (plans/19-tickets-clients.md) dans le navigateur ; rien sans URL.
class TicketLink extends StatelessWidget {
  const TicketLink({super.key, required this.task, this.size = 18});
  final Task? task;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = task?.ticketUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return const SizedBox.shrink();
    final l = context.l10n;
    return IconButton(
      tooltip: l.openTicket(task!.ticketKey ?? url!),
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.open_in_new, size: size),
      onPressed: () async {
        var opened = false;
        try {
          opened = await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
        } catch (_) {
          // Pas de navigateur disponible : signalé ci-dessous.
        }
        if (!opened && context.mounted) showSnack(context, l.cannotOpenLink(url!));
      },
    );
  }
}
