import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';

/// Rapports partagés (plans/18-rapports-presence-alertes-partage.md, lot 3) : un rapport enregistré par un manager,
/// avec un lien public en lecture seule. Gérés par Flask (`/api/reports/saved`), donc en ligne seulement.

/// Période et filtres du rapport affiché, à enregistrer tels quels.
class ReportDraft {
  const ReportDraft({required this.period, this.from, this.to, this.filters = const {}, this.rounding = false});

  /// `this_week`, `last_week`, `this_month`, `last_month`, `this_year` ou `custom` (avec [from] et [to], inclus).
  final String period;
  final DateTime? from;
  final DateTime? to;

  /// client_id, project_id, user_id, billable (« true » / « false »), member_kind (« human » / « agent »).
  final Map<String, String> filters;
  final bool rounding;
}

class SavedReport {
  SavedReport.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        period = j['period'] as String,
        from = j['date_from'] == null ? null : DateTime.parse(j['date_from'] as String),
        to = j['date_to'] == null ? null : DateTime.parse(j['date_to'] as String),
        detailed = j['detailed'] as bool,
        showAmounts = j['show_amounts'] as bool,
        publicPath = j['public_path'] as String?;
  final String id;
  final String name;
  final String period;
  final DateTime? from;
  final DateTime? to;
  final bool detailed;
  final bool showAmounts;
  final String? publicPath;

  /// Adresse complète du lien public, avec l'adresse de l'instance que l'app connaît.
  String? get publicUrl => publicPath == null ? null : '${ServicesApi.baseUrl}$publicPath';
}

Future<void> showSavedReports(BuildContext context, ReportDraft current) =>
    showDialog<void>(context: context, builder: (_) => _SavedReportsDialog(current: current));

class _SavedReportsDialog extends StatefulWidget {
  const _SavedReportsDialog({required this.current});
  final ReportDraft current;

  @override
  State<_SavedReportsDialog> createState() => _SavedReportsDialogState();
}

class _SavedReportsDialogState extends State<_SavedReportsDialog> {
  late Future<List<SavedReport>> _reports = _load();
  bool _busy = false;

  String get _wid => context.read<SessionController>().workspaceId!;

  Future<List<SavedReport>> _load() async {
    final wid = context.read<SessionController>().workspaceId!;
    final res = await ServicesApi.get('/api/reports/saved', {'workspace_id': wid});
    return [for (final r in res['reports'] as List) SavedReport.fromJson(r as Map<String, dynamic>)];
  }

  /// Un appel au serveur, puis la liste relue ; une erreur (hors ligne…) s'affiche.
  Future<void> _call(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      setState(() => _reports = _load());
    } catch (e) {
      if (mounted) showSnack(context, e is ServicesException ? e.message : context.l10n.onlineOnly);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(SavedReport r) async {
    await Clipboard.setData(ClipboardData(text: r.publicUrl!));
    if (mounted) showSnack(context, context.l10n.linkCopied);
  }

  Future<void> _create() async {
    final draft = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _NewSharedReport(current: widget.current));
    if (draft == null) return;
    await _call(() => ServicesApi.post('/api/reports/saved', {'workspace_id': _wid, ...draft}));
  }

  Future<void> _update(SavedReport r, Map<String, dynamic> body) =>
      _call(() => ServicesApi.put('/api/reports/saved/${r.id}', {'workspace_id': _wid, ...body}));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.sharedReports),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<List<SavedReport>>(
          future: _reports,
          builder: (context, snap) {
            if (snap.hasError) return Text(l.onlineOnly);
            if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            final reports = snap.data!;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.sharedReportsHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 8),
              if (reports.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(l.noSharedReports))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final r in reports)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(r.publicPath == null ? Icons.link_off : Icons.link),
                        title: Text(r.name),
                        subtitle: Text([
                          periodLabel(context, r.period, r.from, r.to),
                          if (r.detailed) l.sharedDetailedShort,
                          if (r.publicPath == null) l.sharedLinkOff,
                        ].join(' · ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (r.publicUrl != null) ...[
                            IconButton(tooltip: l.copyLink, icon: const Icon(Icons.copy), onPressed: () => _copy(r)),
                            IconButton(
                              tooltip: l.open,
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () => launchUrl(Uri.parse(r.publicUrl!), webOnlyWindowName: '_blank'),
                            ),
                          ],
                          PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (v) async {
                              switch (v) {
                                case 'public':
                                  await _update(r, {'public': r.publicPath == null});
                                case 'newLink':
                                  await _update(r, {'new_link': true});
                                case 'delete':
                                  final ok = await confirm(context,
                                      title: l.deleteSharedReport, message: l.deleteSharedReportMessage, confirmLabel: l.delete);
                                  if (ok) await _call(() => ServicesApi.delete('/api/reports/saved/${r.id}', {'workspace_id': _wid}));
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'public', child: Text(r.publicPath == null ? l.sharedLinkOpen : l.sharedLinkClose)),
                              if (r.publicPath != null) PopupMenuItem(value: 'newLink', child: Text(l.sharedNewLink)),
                              PopupMenuItem(value: 'delete', child: Text(l.delete)),
                            ],
                          ),
                        ]),
                      ),
                  ]),
                ),
            ]);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
        FilledButton.icon(onPressed: _busy ? null : _create, icon: const Icon(Icons.add_link), label: Text(l.shareThisReport)),
      ],
    );
  }
}

/// « Cette semaine », « Mois dernier »…, ou les dates d'une période fixe.
String periodLabel(BuildContext context, String period, DateTime? from, DateTime? to) {
  final l = context.l10n;
  final fmt = DateFormat.yMMMd(context.localeTag);
  return switch (period) {
    'this_week' => l.thisWeek,
    'last_week' => l.lastWeek,
    'this_month' => l.thisMonth,
    'last_month' => l.lastMonth,
    'this_year' => l.thisYear,
    _ => from == null || to == null ? l.customRange : '${fmt.format(from)} – ${fmt.format(to)}',
  };
}

/// Nom et options d'un nouveau rapport partagé ; renvoie le corps de la requête, ou null.
class _NewSharedReport extends StatefulWidget {
  const _NewSharedReport({required this.current});
  final ReportDraft current;

  @override
  State<_NewSharedReport> createState() => _NewSharedReportState();
}

class _NewSharedReportState extends State<_NewSharedReport> {
  final _name = TextEditingController();
  bool _detailed = false;
  bool _amounts = true;
  bool _public = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final c = widget.current;
    Navigator.pop(context, <String, dynamic>{
      'name': name,
      'period': c.period,
      if (c.period == 'custom') 'date_from': dayKey(c.from!),
      if (c.period == 'custom') 'date_to': dayKey(c.to!),
      'filters': c.filters,
      'rounding': c.rounding,
      'detailed': _detailed,
      'show_amounts': _amounts,
      'public': _public,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = widget.current;
    return AlertDialog(
      title: Text(l.shareThisReport),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l.sharedReportName, hintText: l.sharedReportNameHint),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(l.sharedReportPeriod(periodLabel(context, c.period, c.from, c.to)), style: Theme.of(context).textTheme.bodySmall),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _detailed,
            onChanged: (v) => setState(() => _detailed = v!),
            title: Text(l.sharedDetailed),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _amounts,
            onChanged: (v) => setState(() => _amounts = v!),
            title: Text(l.sharedAmounts),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _public,
            onChanged: (v) => setState(() => _public = v),
            title: Text(l.sharedPublicLink),
            subtitle: Text(l.sharedPublicLinkHelp),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}
