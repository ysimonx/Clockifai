import 'package:get_it/get_it.dart';

import '../data/powersync/sync_service.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/modules_repository.dart';
import '../data/repositories/team_repository.dart';
import '../data/repositories/time_entry_repository.dart';
import '../data/repositories/workspace_repository.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  final sync = await SyncService.open();
  getIt
    ..registerSingleton<SyncService>(sync)
    ..registerSingleton<TimeEntryRepository>(TimeEntryRepository(sync.db))
    ..registerSingleton<CatalogRepository>(CatalogRepository(sync.db))
    ..registerSingleton<WorkspaceRepository>(WorkspaceRepository(sync.db))
    ..registerSingleton<ModulesRepository>(ModulesRepository(sync.db))
    ..registerSingleton<TeamRepository>(TeamRepository(sync.db));
}

SyncService get syncService => getIt<SyncService>();
TimeEntryRepository get entriesRepo => getIt<TimeEntryRepository>();
CatalogRepository get catalogRepo => getIt<CatalogRepository>();
WorkspaceRepository get workspaceRepo => getIt<WorkspaceRepository>();
ModulesRepository get modulesRepo => getIt<ModulesRepository>();
TeamRepository get teamRepo => getIt<TeamRepository>();
