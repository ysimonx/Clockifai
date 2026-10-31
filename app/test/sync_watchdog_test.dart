import 'package:clockifai/core/widgets/sync_indicator.dart';
import 'package:clockifai/data/powersync/sync_service.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:powersync/powersync.dart' show SyncStatus;

// État construit à la main, comme le SDK le publie (son constructeur est réservé au paquet).
// ignore: invalid_use_of_internal_member
SyncStatus _status({bool connected = true, bool downloading = false, DateTime? lastSyncedAt}) => SyncStatus(
      connected: connected,
      connecting: false,
      lastSyncedAt: lastSyncedAt,
      downloadProgress: null,
      downloading: downloading,
      uploading: false,
      downloadError: null,
      uploadError: null,
      priorityStatusEntries: const [],
      streamSubscriptions: null,
      lastAppliedCheckpoint: null,
    );

/// Sync figée après une mise en veille : reconnexion et âge affiché (app macOS, 31 octobre 2026 : une entrée de
/// Claude « en cours » depuis 3 h, la dernière synchro datant de 21:39).
void main() {
  final now = DateTime(2026, 11, 1, 0, 10);
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

  group('reconnexion', () {
    test('connectée sans rien reçu depuis 10 minutes : reconnectée', () {
      expect(SyncService.shouldReconnect(_status(lastSyncedAt: ago(151)), now), isTrue);
      expect(SyncService.shouldReconnect(_status(lastSyncedAt: ago(10)), now), isTrue);
      expect(SyncService.shouldReconnect(_status(lastSyncedAt: ago(9)), now), isFalse);
    });

    test('au retour au premier plan, dès 2 minutes', () {
      expect(SyncService.shouldReconnect(_status(lastSyncedAt: ago(3)), now, after: const Duration(minutes: 2)), isTrue);
    });

    test('jamais hors ligne, pendant un téléchargement, avant la première synchro, ni deux fois par minute', () {
      expect(SyncService.shouldReconnect(_status(connected: false, lastSyncedAt: ago(60)), now), isFalse);
      expect(SyncService.shouldReconnect(_status(downloading: true, lastSyncedAt: ago(60)), now), isFalse);
      expect(SyncService.shouldReconnect(_status(), now), isFalse);
      expect(SyncService.shouldReconnect(_status(lastSyncedAt: ago(60)), now, lastReconnect: now.subtract(const Duration(seconds: 30))),
          isFalse);
    });
  });

  group('âge de la dernière synchro', () {
    late AppLocalizations l;
    setUpAll(() async {
      await initializeDateFormatting('fr');
      l = lookupAppLocalizations(const Locale('fr'));
    });

    String? label(SyncStatus s) => staleSyncLabel(l, 'fr', s, now);

    test('rien tant que la reconnexion a pu agir', () {
      expect(label(_status(lastSyncedAt: ago(14))), isNull);
      expect(label(_status()), isNull);
    });

    test('au-delà : depuis combien de temps', () {
      expect(label(_status(lastSyncedAt: ago(20))), 'Dernière synchro il y a 20 min');
      expect(label(_status(lastSyncedAt: ago(151))), 'Dernière synchro il y a 2 h');
      expect(label(_status(lastSyncedAt: DateTime(2026, 10, 30, 21, 39))), startsWith('Dernière synchro le 30 oct. 2026'));
    });

    test('hors ligne : l’état « Hors ligne » suffit', () {
      expect(label(_status(connected: false, lastSyncedAt: ago(151))), isNull);
    });
  });
}
