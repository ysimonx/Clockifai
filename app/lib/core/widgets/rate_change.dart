import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/drift/database.dart';
import '../di.dart';
import '../l10n.dart';
import '../session.dart';
import 'common.dart';

/// Un taux de projet ou de membre vient de changer. Chaque entrée garde le taux posé à sa saisie : on propose
/// d'appliquer le nouveau aux entrées non facturées, et encore modifiables, qui en ont un autre ([rateFor] donne
/// celui que prendrait l'entrée, [concerns] écarte celles que le changement ne vise pas).
Future<void> offerRateChange(
  BuildContext context, {
  String? projectId,
  String? userId,
  required int? Function(TimeEntry entry) rateFor,
  bool Function(TimeEntry entry)? concerns,
}) async {
  final session = context.read<SessionController>();
  final ws = session.workspace;
  if (ws == null) return;
  final entries = await modulesRepo.rerateableEntries(ws.id,
      projectId: projectId,
      userId: userId,
      isAdmin: session.isAdmin,
      lockBefore: DateTime.tryParse(ws.lockEntriesBefore ?? ''));
  final changes = <String, int?>{
    for (final e in entries)
      if ((concerns?.call(e) ?? true) && rateFor(e) != e.hourlyRateCents) e.id: rateFor(e),
  };
  if (changes.isEmpty || !context.mounted) return;
  final l = context.l10n;
  final apply = await confirm(context,
      title: l.applyRateTitle,
      message: l.applyRateBody(changes.length),
      confirmLabel: l.applyRateApply,
      cancelLabel: l.applyRateKeep,
      destructive: false);
  if (apply) await modulesRepo.setEntryRates(changes);
}
