import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../today/traces.dart';

/// Agenda (plans/13-ux-moderne.md, lot 4) : l'adresse iCal privée de son agenda, lue par le serveur pour proposer
/// ses réunions dans « Aujourd'hui ». Seul l'hôte est affiché ; l'adresse ne revient jamais du serveur.
class CalendarTile extends StatefulWidget {
  const CalendarTile({super.key});

  @override
  State<CalendarTile> createState() => _CalendarTileState();
}

class _CalendarTileState extends State<CalendarTile> {
  late Future<Map<String, dynamic>> _source = TracesApi.calendarSource();

  void _reload() => setState(() => _source = TracesApi.calendarSource());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return FutureBuilder<Map<String, dynamic>>(
      future: _source,
      builder: (context, snap) {
        final configured = snap.data?['configured'] == true;
        final subtitle = snap.hasError
            ? l.calendarOffline
            : !snap.hasData
                ? ''
                : configured
                    ? l.calendarLinked(snap.data!['host'] as String? ?? '')
                    : l.calendarNone;
        return ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: Text(l.calendarTitle),
          subtitle: Text(subtitle),
          onTap: snap.hasError
              ? _reload
              : () async {
                  await showDialog<void>(context: context, builder: (_) => _CalendarDialog(configured: configured));
                  _reload();
                },
        );
      },
    );
  }
}

String calendarError(AppLocalizations l, String code) => switch (code) {
      'https_required' => l.calendarErrorHttps,
      'host_not_allowed' => l.calendarErrorHost,
      'not_a_calendar' => l.calendarErrorFormat,
      'too_large' => l.calendarErrorTooLarge,
      _ => l.calendarErrorUnreachable,
    };

class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({required this.configured});
  final bool configured;

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } on ServicesException catch (e) {
      if (mounted) setState(() => _error = e.status == 400 ? calendarError(l, e.message) : l.calendarErrorUnreachable);
    } catch (_) {
      if (mounted) setState(() => _error = l.calendarOffline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.calendarTitle),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.calendarHelp, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: l.calendarUrl, hintText: 'https://…/basic.ics', errorText: _error),
            onSubmitted: (_) => _run(() => TracesApi.setCalendar(_url.text)),
          ),
        ]),
      ),
      actions: [
        if (widget.configured)
          TextButton(onPressed: _busy ? null : () => _run(TracesApi.removeCalendar), child: Text(l.calendarRemove)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _busy ? null : () => _run(() => TracesApi.setCalendar(_url.text)), child: Text(l.save)),
      ],
    );
  }
}
