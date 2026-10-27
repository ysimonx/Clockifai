import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/time_entry_repository.dart';

/// « Demander à Clockifai » (plans/13-ux-moderne.md, lot 12) : questions sur le temps passé, réponses de Claude par
/// le serveur (`/api/assistant`), à partir de totaux seulement. Une modification proposée s'affiche en aperçu ; la
/// personne l'applique sur sa base locale (Annuler), ou non.
class AssistantApi {
  static Future<bool>? _enabled;

  /// Disponible sur cette installation (clé d'API côté serveur) ; lu une fois, faux hors ligne.
  static Future<bool> enabled() => _enabled ??= ServicesApi.get('/api/assistant/status', const {})
      .then((r) => r['enabled'] == true, onError: (Object _) {
        _enabled = null; // réessayé à la prochaine demande
        return false;
      });

  /// Remplace l'appel au serveur (tests).
  static Future<Map<String, dynamic>> Function(String workspaceId, String question, List<Map<String, String>> history)?
      override;

  static Future<Map<String, dynamic>> ask(String workspaceId, String question, List<Map<String, String>> history) =>
      override?.call(workspaceId, question, history) ??
      ServicesApi.post('/api/assistant/ask', {'workspace_id': workspaceId, 'question': question, 'history': history});
}

/// Une modification groupée proposée par l'assistant.
class Proposal {
  Proposal.fromJson(Map<String, dynamic> j)
      : entryIds = (j['entry_ids'] as List? ?? const []).cast<String>(),
        projectId = j['project_id'] as String?,
        taskId = j['task_id'] as String?,
        billable = j['billable'] as bool?,
        summary = j['summary'] as String? ?? '';
  final List<String> entryIds;
  final String? projectId;
  final String? taskId;
  final bool? billable;
  final String summary;
}

class _Message {
  _Message.user(this.text) : user = true, proposals = const [];
  _Message.assistant(this.text, {this.proposals = const []}) : user = false;
  final bool user;
  final String text;
  final List<Proposal> proposals;
}

Future<void> showAssistant(BuildContext context) => showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.assistantTitle,
      barrierColor: Colors.black26,
      pageBuilder: (context, _, _) => const Align(alignment: Alignment.centerRight, child: AssistantPanel()),
    );

/// Le panneau, à droite de l'écran : conversation, exemples, propositions.
class AssistantPanel extends StatefulWidget {
  const AssistantPanel({super.key});

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _messages = <_Message>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final l = context.l10n;
    final question = text.trim();
    if (question.isEmpty || _busy) return;
    final ws = context.read<SessionController>().workspaceId!;
    final history = [
      for (final m in _messages) {'role': m.user ? 'user' : 'assistant', 'text': m.text},
    ];
    setState(() {
      _messages.add(_Message.user(question));
      _busy = true;
      _input.clear();
    });
    _toBottom();
    String answer;
    var proposals = <Proposal>[];
    try {
      final r = await AssistantApi.ask(ws, question, history);
      proposals = [for (final p in (r['proposals'] as List? ?? const [])) Proposal.fromJson((p as Map).cast())];
      answer = r['refused'] == true ? l.assistantRefused : (r['answer'] as String? ?? l.assistantTooLong);
    } on ServicesException catch (e) {
      answer = switch (e.message) {
        'rate_limited' => l.assistantRateLimited,
        _ => l.assistantUnavailable,
      };
    } catch (_) {
      answer = l.assistantOffline;
    }
    if (!mounted) return;
    setState(() {
      _messages.add(_Message.assistant(answer, proposals: proposals));
      _busy = false;
    });
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Material(
      elevation: 8,
      child: SizedBox(
        width: width < 600 ? width : 460,
        height: double.infinity,
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.tertiary),
                const SizedBox(width: 8),
                Expanded(child: Text(l.assistantTitle, style: theme.textTheme.titleMedium)),
                IconButton(tooltip: l.close, icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
                if (_messages.isEmpty) ...[
                  Text(l.assistantIntro, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  for (final ex in [l.assistantExample1, l.assistantExample2, l.assistantExample3])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // Un bouton plutôt qu'une puce : la question peut passer à la ligne.
                        child: OutlinedButton(onPressed: () => _send(ex), child: Text(ex)),
                      ),
                    ),
                ],
                for (final m in _messages) _bubble(context, m),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text(l.assistantThinking, style: theme.textTheme.bodySmall),
                    ]),
                  ),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _input,
                autofocus: true,
                enabled: !_busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: l.assistantHint,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: () => _send(_input.text)),
                ),
                onSubmitted: _send,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, _Message m) {
    final theme = Theme.of(context);
    return Align(
      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: m.user ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(m.text),
          for (final p in m.proposals) _ProposalCard(proposal: p),
        ]),
      ),
    );
  }
}

/// Une modification proposée : aperçu des entrées concernées, puis « Appliquer » (Annuler dans le bandeau).
class _ProposalCard extends StatefulWidget {
  const _ProposalCard({required this.proposal});
  final Proposal proposal;

  @override
  State<_ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends State<_ProposalCard> {
  late final Future<List<EntryRow>> _rows = entriesRepo.rowsByIds(widget.proposal.entryIds);
  bool _open = false;
  bool _done = false;

  Future<void> _apply(List<EntryRow> rows) async {
    final l = context.l10n;
    final catalog = context.read<CatalogController>();
    final p = widget.proposal;
    final before = [for (final r in rows) r.entry];
    await entriesRepo.updateEach(
      before,
      projectId: p.projectId,
      taskId: p.taskId,
      clearTask: p.projectId != null && p.taskId == null,
      billable: p.billable,
      hourlyRateFor: (e) => p.projectId != null && p.projectId != e.projectId ? catalog.rateFor(projectId: p.projectId, userId: e.userId) : null,
    );
    if (!mounted) return;
    setState(() => _done = true);
    showUndo(context, l.entriesUpdated(before.length), () async {
      await entriesRepo.restore(before);
      if (mounted) setState(() => _done = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final p = widget.proposal;
    return FutureBuilder<List<EntryRow>>(
      future: _rows,
      builder: (context, snap) {
        final rows = snap.data ?? const <EntryRow>[];
        final change = [
          if (catalog.project(p.projectId) case final project?) '→ ${project.name}${catalog.task(p.taskId) == null ? '' : ' : ${catalog.task(p.taskId)!.name}'}',
          if (p.billable != null) '→ ${p.billable! ? l.billable : l.nonBillable}',
        ].join(' · ');
        return Card(
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.summary, style: theme.textTheme.titleSmall),
              Text('${l.assistantEntries(rows.length)}${change.isEmpty ? '' : ' $change'}', style: theme.textTheme.bodySmall),
              if (_open)
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${dayLabel(context, r.entry.startAt.toLocal(), today: l.today, yesterday: l.yesterday)} '
                      '${timeLabel(context, r.entry.startAt)} · ${formatHm(r.seconds)} · '
                      '${r.entry.description.isEmpty ? l.noDescription : r.entry.description} · '
                      '${catalog.project(r.entry.projectId)?.name ?? l.noProject}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              const SizedBox(height: 6),
              OverflowBar(alignment: MainAxisAlignment.spaceBetween, overflowSpacing: 4, children: [
                TextButton(onPressed: () => setState(() => _open = !_open), child: Text(l.assistantPreview)),
                FilledButton.tonal(
                  onPressed: _done || rows.isEmpty ? null : () => _apply(rows),
                  child: Text(_done ? l.assistantApplied : l.assistantApply),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
