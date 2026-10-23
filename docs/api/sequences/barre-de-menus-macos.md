# Barre de menus macOS

L'icône Clockifai en haut à droite de l'écran ouvre un panneau natif SwiftUI. Ce panneau n'a **aucun accès
aux données** : le widget Flutter `MacMenuBar` lui pousse l'état par le canal `clockifai/menu_bar` et exécute
ses commandes sur la base locale, comme la barre du chronomètre. Tout marche hors ligne et fenêtre fermée
(le moteur Flutter et la synchronisation continuent tant que l'app tourne).

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant P as Panneau SwiftUI (MenuBarController)
    participant W as MacMenuBar (Flutter)
    participant DB as Base locale

    Note over W,DB: surveille watchRunning et watchRecent du workspace courant
    DB-->>W: chronomètre en cours, entrées récentes, référentiel
    W->>W: regroupe les changements (microtâche), ignore un état identique au précédent
    W->>P: update (connecté, première sync, en cours, récentes, projets, libellés traduits)
    P->>P: icône pleine ou vide, temps écoulé à côté de l'icône

    U->>P: clic, saisit une description, choisit un projet, Démarrer
    P->>W: start (description, projectId)
    W->>W: règles du workspace, puis un seul chronomètre par tâche
    alt Bloqué
        W-->>P: message affiché dans le panneau
    else Autorisé
        W->>DB: entriesRepo.start (limite max_running_timers)
        W-->>P: null
        DB-->>W: nouveau chronomètre en cours
        W->>P: update
    end

    opt Autres commandes
        P->>W: stop, setDescription, setProject ou continue (entrée récente)
        W->>DB: même dépôt que l'interface principale
    end
    Note over DB: l'envoi au serveur suit le chemin habituel (ecriture-hors-ligne.md)
```

- Les commandes renvoient `null`, ou le message à afficher dans le panneau. Les libellés arrivent traduits
  depuis l'ARB avec l'état : le code Swift n'en contient aucun.
- Clic droit sur l'icône : ouvrir l'app, démarrage à l'ouverture de session (canal
  `clockifai/launch_at_login`, `SMAppService`, macOS 13+), quitter.
- `setProject` retire la tâche (propre à l'ancien projet) et recalcule facturable et taux.

Sources : `app/lib/features/timer/menu_bar.dart`, `app/macos/Runner/MenuBarController.swift`,
`app/macos/Runner/LaunchAtLogin.swift`, `app/test/` (pont simulé), `plans/06-macos-barre-de-menus.md`.
