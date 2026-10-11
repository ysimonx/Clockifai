import 'dart:async';

import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';

final _log = Logger('clockifai.connector');

/// Codes Postgres non récupérables par un simple nouvel essai.
final List<RegExp> _fatalCodes = [
  RegExp(r'^22...$'), // Data exception (type invalide…)
  RegExp(r'^23...$'), // Contrainte (NOT NULL, FK, UNIQUE, CHECK)
  RegExp(r'^42501$'), // Privilèges insuffisants : RLS, entrée verrouillée…
];

/// Colonnes calculées ou posées par le serveur : jamais envoyées.
const _serverOwnedColumns = {'updated_at', 'duration_seconds'};

/// Erreur d'envoi abandonnée (la modification locale est annulée par la sync suivante).
class UploadRejection {
  UploadRejection(this.table, this.op, this.code, this.message);
  final String table;
  final UpdateType op;
  final String? code;
  final String message;
}

/// Pont PowerSync ↔ Supabase :
///   * fetchCredentials : le JWT Supabase de l'utilisateur sert à s'authentifier auprès de PowerSync ;
///   * uploadData : rejoue la file locale de modifications via PostgREST (soumis à la RLS).
class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector({required this.onRejected});

  final void Function(UploadRejection rejection) onRejected;
  Future<void>? _refreshFuture;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    await _refreshFuture;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: AppConfig.powersyncUrl,
      token: session.accessToken,
      userId: session.user.id,
      expiresAt: session.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000),
    );
  }

  @override
  void invalidateCredentials() {
    _refreshFuture = Supabase.instance.client.auth
        .refreshSession()
        .timeout(const Duration(seconds: 5))
        .then((_) => null, onError: (_) => null);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    final rest = Supabase.instance.client.rest;
    CrudEntry? lastOp;
    try {
      for (final op in transaction.crud) {
        lastOp = op;
        final table = rest.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            // Insertion : on n'envoie pas les null (le serveur applique ses valeurs par défaut).
            final data = <String, dynamic>{
              for (final e in (op.opData ?? const {}).entries)
                if (e.value != null && !_serverOwnedColumns.contains(e.key)) e.key: e.value,
            }..['id'] = op.id;
            await table.upsert(data);
          case UpdateType.patch:
            final data = <String, dynamic>{
              for (final e in (op.opData ?? const {}).entries)
                if (!_serverOwnedColumns.contains(e.key)) e.key: e.value,
            };
            if (data.isNotEmpty) await table.update(data).eq('id', op.id);
          case UpdateType.delete:
            await table.delete().eq('id', op.id);
        }
      }
      await transaction.complete();
    } on PostgrestException catch (e) {
      final code = e.code;
      if (code != null && _fatalCodes.any((re) => re.hasMatch(code))) {
        // Ne pas bloquer la file : on abandonne cette transaction et on prévient l'utilisateur.
        // Le serveur restant la référence, la donnée locale est corrigée à la sync suivante.
        _log.severe('Envoi rejeté ($code) pour $lastOp : ${e.message}');
        if (lastOp != null) {
          onRejected(UploadRejection(lastOp.table, lastOp.op, code, e.message));
        }
        await transaction.complete();
      } else {
        // Erreur réseau / serveur temporaire : PowerSync réessaiera.
        rethrow;
      }
    }
  }
}
