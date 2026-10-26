import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/drift/database.dart';

/// Usage IA des entrées d'agent Claude (plans/10-suivi-claude-code.md, D17) : tokens et coût estimé au tarif de
/// l'API d'Anthropic, en dollars, que l'entrée soit payée à l'usage ou couverte par un abonnement.

String formatTokens(int tokens, String locale) => NumberFormat.compact(locale: locale).format(tokens);

String formatAiCost(int micros, String locale) => formatMoney(micros / 1e6, 'USD', locale);

/// « claude-opus-5-5 » → « Opus 5.5 », « claude-haiku-4-5-20251001 » → « Haiku 4.5 ».
String modelLabel(String model) {
  final parts = model.replaceFirst(RegExp(r'^claude-'), '').replaceFirst(RegExp(r'-\d{8}$'), '').split('-');
  if (parts.isEmpty || parts.first.isEmpty) return model;
  final name = parts.first[0].toUpperCase() + parts.first.substring(1);
  return parts.length == 1 ? name : '$name ${parts.skip(1).join('.')}';
}

int usageTokens(AgentUsageRow u) =>
    (u.inputTokens ?? 0) + (u.outputTokens ?? 0) + (u.cacheWrite5mTokens ?? 0) + (u.cacheWrite1hTokens ?? 0) + (u.cacheReadTokens ?? 0);

/// « ✦ 12 M tokens · 4,56 $ » sur une ligne d'entrée, un groupe ou une carte, avec l'avertissement en bulle.
class AiUsageText extends StatelessWidget {
  const AiUsageText({super.key, required this.tokens, required this.costMicros, this.style});
  final int tokens;
  final int? costMicros;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final text = [
      l.aiTokens(formatTokens(tokens, locale)),
      if (costMicros != null) formatAiCost(costMicros!, locale),
    ].join(' · ');
    return Tooltip(
      message: l.aiUsageHelp,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome, size: 14, color: theme.colorScheme.tertiary),
        const SizedBox(width: 4),
        Text(text, style: style ?? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
      ]),
    );
  }
}

/// Détail dans la fenêtre d'une entrée d'agent : une ligne par modèle, effort et vitesse.
class AiUsageSection extends StatelessWidget {
  const AiUsageSection({super.key, required this.entryId});
  final String entryId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeTag;
    return StreamBuilder<List<AgentUsageRow>>(
      stream: entriesRepo.watchUsage(entryId),
      builder: (context, snap) {
        final rows = snap.data ?? const <AgentUsageRow>[];
        if (rows.isEmpty) return const SizedBox.shrink();
        final tokens = rows.fold<int>(0, (s, u) => s + usageTokens(u));
        final priced = rows.where((u) => u.costMicros != null);
        final cost = priced.isEmpty ? null : priced.fold<int>(0, (s, u) => s + u.costMicros!);
        String n(int? v) => formatTokens(v ?? 0, locale);
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(l.aiUsage, style: theme.textTheme.titleSmall),
              const SizedBox(width: 4),
              Tooltip(message: l.aiUsageHelp, child: Icon(Icons.info_outline, size: 16, color: theme.colorScheme.outline)),
              const Spacer(),
              AiUsageText(tokens: tokens, costMicros: cost),
            ]),
            for (final u in rows)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    [
                      modelLabel(u.model),
                      if (u.effort != null) l.aiEffort(u.effort!),
                      if (u.speed == 'fast') l.aiFastMode,
                      l.aiRequests(u.requests ?? 0),
                      u.costMicros == null ? l.aiUnknownPrice : formatAiCost(u.costMicros!, locale),
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    l.aiUsageBreakdown(n(u.inputTokens), n(u.outputTokens),
                        n((u.cacheWrite5mTokens ?? 0) + (u.cacheWrite1hTokens ?? 0)), n(u.cacheReadTokens)),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}
