// Point d'entrée du worker web PowerSync, compilé avec les dépendances EXACTES de l'app
// (le worker publié par PowerSync peut être en décalage avec sqlite_async résolu ici).
//   fvm dart compile js -O4 -o web/powersync_db.worker.js tool/powersync_worker.dart
// Lancé par `make app-web-assets`.
import 'package:powersync/web_worker.dart' as worker;

void main() => worker.main();
