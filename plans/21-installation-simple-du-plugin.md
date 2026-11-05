# Plan 21 — Installation simple du plugin Claude Code

> Statut : **fait** (5 novembre 2026). Demandé par Yannick : « je trouve l'installation du plugin claude très
> compliquée pour un utilisateur lambda ».

## Constat

Connecter un poste demandait cinq étapes sur trois fenêtres (app, terminal, Claude Code) :

- **Le vocabulaire** : poste, jeton, marketplace.
- **La commande `claude`** : exigée même par ceux qui n'utilisent que le panneau VSCode.
- **Le jeton** : coller une commande sans la valider, revenir le copier, retourner valider. L'app devait expliquer
  pourquoi l'ordre comptait.
- **Aucune confirmation** : la fenêtre ne se mettait pas à jour, et un hook sans jeton ne laissait qu'une ligne dans
  un journal local.
- **Une consigne périmée** : « le panneau de VSCode ne sait pas installer de plugin ». Il sait le faire depuis
  `/plugins`.

## Ce qui a été vérifié (5 novembre 2026)

Avec Claude Code 2.1.312 et l'extension VSCode 2.1.318, dans un dossier de configuration jetable
(`CLAUDE_CONFIG_DIR`) :

| Question | Résultat |
|---|---|
| Une seule commande suffit-elle ? | Oui : `claude plugin install clockifai --marketplace <URL>` ajoute la marketplace et installe, en moins d'une seconde sur la prod (Claude Code 2.1.292 ou plus) |
| Une option facultative évite-t-elle le formulaire de VSCode ? | Non : l'extension le montre dès que `unconfigured` n'est pas vide, et une option facultative ou avec valeur par défaut y reste. Il faut retirer `userConfig` |
| Un poste déjà réglé perd-il ses options si `userConfig` disparaît ? | Non pour une option non sensible : `CLAUDE_PLUGIN_OPTION_URL` arrive toujours au hook. Non vérifié pour le jeton, rangé dans le trousseau |
| `CLAUDE_PLUGIN_DATA` arrive-t-il au hook ? | Oui, même sans référence dans la commande ; le dossier n'existe pas forcément, le hook le crée |
| `additionalContext` et `systemMessage` passent-ils ensemble au `SessionStart` ? | Oui, Claude reçoit le contexte |
| Claude donne-t-il le lien ? | Oui : deux vraies sessions (`claude -p`, Haiku, plugin du dépôt) l'ont écrit au début de leur réponse |

Le parcours complet a tourné sur la pile locale : lien donné par Claude, navigateur déconnecté renvoyé vers la
connexion puis vers le lien, validation, jeton retiré par la session suivante, file locale vidée, et les sessions
d'avant la connexion enregistrées.

## Décisions (validées le 5 novembre 2026)

1. **Une seule commande.** `claude plugin install clockifai --marketplace <URL>` remplace les deux commandes.
2. **Un bouton pour VSCode.** « Ouvrir dans VSCode » suit `vscode://anthropic.claude-code/install-plugin`, sans
   terminal ni commande `claude`. Il n'apparaît que sur un ordinateur et sur une instance en https (le lien refuse
   `http://` et les chemins locaux). L'app de bureau n'a pas d'équivalent documenté : ses utilisateurs passent par la
   commande, le plugin installé valant pour les trois (mêmes réglages).
3. **Confirmation en direct.** Tant que les étapes sont affichées, la fenêtre relit les postes toutes les 5 secondes
   et annonce le poste dès son premier événement.
4. **Plus de jeton à copier : connexion par lien.**
   1. Au `SessionStart`, sans jeton, le hook demande un lien à l'instance et l'ajoute au contexte. Claude le donne à
      l'utilisateur. Le même texte part en `systemMessage`, pour l'afficher sans attendre là où c'est possible.
   2. Le lien ouvre `/connect/<code>` dans l'app web. On y confirme le nom du poste et l'espace de travail.
   3. À son prochain événement, le hook retire le jeton de l'instance et le garde sur le poste.
5. **Plus de `userConfig`** dans le plugin : l'installation ne pose aucune question. L'adresse de l'instance passe dans
   `metadata.url` de `plugin.json`, posée par l'instance dans le zip. Le hook lit encore `CLAUDE_PLUGIN_OPTION_*` et
   `CLOCKIFAI_*` : un poste déjà connecté garde son jeton s'il arrive toujours ; sinon, un clic sur le lien suffit.
6. **Jeton dans `${CLAUDE_PLUGIN_DATA}/token`**, droits `0600`, et non plus dans le trousseau : un hook ne peut pas
   écrire dans le stockage sécurisé de Claude Code. Le fichier suit les mises à jour du plugin et disparaît à sa
   désinstallation.
7. **Deux secrets par lien, jamais le jeton.** `code` (dans l'adresse, pour l'humain) et `poll` (gardé par le hook).
   L'instance n'en stocke que les empreintes SHA-256 (`clockifai_private.device_links`). Le jeton n'existe qu'au
   retrait, créé et remis une seule fois par `poll`.
8. **Hameçonnage.** Quelqu'un pourrait envoyer son propre lien pour relier sa machine à un autre compte. Le lien vit
   10 minutes, la page montre le nom de la machine et demande de ne valider que si l'on vient de lancer Claude Code
   sur cet ordinateur. Le poste reste révocable. Une fois validé, le retrait reste possible un jour.
9. **Route publique bornée.** `POST /api/claude/link` est sans compte, par nature. Les liens expirés sont supprimés
   à chaque création et l'instance refuse au-delà de 500 liens vivants (429). Le lien ne sert à rien sans validation.
10. **Le temps d'avant la connexion n'est pas perdu.** Les événements attendent dans la file locale (5 Mo au plus) et
    partent avec le jeton : la première session est comptée dès son début.
11. **Révoquer, reconnecter.** Un refus 401 fait oublier le jeton du fichier : la session suivante redonne un lien.
    Un poste relié sous le nom d'un poste existant le remplace, sans doublon dans la liste. « Reconnecter » et
    `claude plugin configure` disparaissent de l'app. `POST /api/tokens` reste, pour les scripts.
12. **Le lien vient de l'instance** (`APP_PUBLIC_URL`, qui diffère de l'adresse de Flask sur la pile locale). Le hook
    le contrôle (`http(s)`, une ligne, 300 caractères) avant de l'écrire : c'est la seule donnée du serveur, avec le
    nom du projet du plan 19, qui entre dans le contexte de Claude.

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 | Une seule commande, bouton VSCode, confirmation en direct, textes corrigés dans l'app et le guide | fait |
| 2 | Connexion par lien : table, routes, page `/connect/<code>`, hook, plugin sans `userConfig`, documentation, vidéo 6 | fait |

## Reste à observer sur un vrai poste

- **Le bouton VSCode** : lien lu dans le code de l'extension, jamais cliqué.
- **`systemMessage`** : s'affiche-t-il dans le terminal et le panneau VSCode, ou seul Claude donne-t-il le lien ? Les
  deux ne se gênent pas : au pire, le lien paraît deux fois, jusqu'à la connexion.
- **Un poste connecté avant ce plan** : garde-t-il son jeton après `claude plugin update` ? Non vérifié pour une valeur
  rangée dans le trousseau. Sinon, le lien réapparaît et un clic suffit.

## Limites acceptées

- **python3** : sur un Mac sans outils de développement, Apple propose de les installer au premier hook. Sous Windows,
  il manque souvent. Les utilisateurs actuels sont sur Mac : on n'y touche pas pour l'instant (Yannick, 5 novembre
  2026).
- **Mises à jour du plugin** : `autoUpdate` reste désactivé pour une marketplace tierce. Il faudrait modifier
  `~/.claude/settings.json` du poste : hors de ce plan.
