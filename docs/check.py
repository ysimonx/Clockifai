"""Contrôle du guide utilisateur (docs/guide/) et des statuts des plans (plans/).

    uv run --no-project python docs/check.py      # ou : make docs-check

Vérifie, dans chaque page HTML du guide :
  * que les liens internes (href, src) mènent à un fichier existant et, pour une ancre, à un id existant ;
  * que chaque lien de scène <a class="scene" data-video="…" data-scene="…"> et chaque lecteur
    <video data-video="…"> désignent une vidéo (`export const name`) et une scène (`h.scene('…')`)
    des scénarios demo/videos/*.mjs ;
  * que chaque vidéo tournée figure dans le guide.
Les fichiers sous videos/ ne sont pas versionnés (publiés à part) : seul leur nom est contrôlé.

Vérifie aussi que chaque plan porte en tête un statut connu (`> Statut : **…**`) et figure dans l'index
plans/README.md avec ce même statut.
Bibliothèque standard uniquement. Code de sortie 1 s'il y a un problème.
"""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

DOCS = Path(__file__).resolve().parent
GUIDE = DOCS / "guide"
SCENARIOS = DOCS.parent / "demo" / "videos"
PLANS = DOCS.parent / "plans"

NAME_RE = re.compile(r"""export\s+const\s+name\s*=\s*(['"`])(.+?)\1""")
SCENE_RE = re.compile(r"""\bh\.scene\(\s*(['"`])(.+?)\1""")
VIDEO_FILE_RE = re.compile(r"^videos/(.+?)(\.mp4|\.chapters\.json)$")

PLAN_STATUSES = ("envisagé", "validé", "en cours", "fait", "en attente", "remplacé")
PLAN_STATUS_RE = re.compile(r"^> Statut : \*\*(.+?)\*\*", re.MULTILINE)
INDEX_ROW_RE = re.compile(r"^\| \[([^\]]+\.md)\]\(([^)]+)\) \|[^|]*\| ([^|]+) \|", re.MULTILINE)


def check_plans() -> tuple[int, list[str]]:
    """Statut en tête de chaque plan, et même statut dans l'index plans/README.md."""
    problems: list[str] = []
    statuses: dict[str, str] = {}
    for path in sorted(PLANS.glob("[0-9]*.md")):
        head = "\n".join(path.read_text(encoding="utf-8").splitlines()[:15])
        found = PLAN_STATUS_RE.search(head)
        if not found:
            problems.append(f"plans/{path.name} : pas de ligne « > Statut : **…** » en tête")
        elif found.group(1) not in PLAN_STATUSES:
            problems.append(f"plans/{path.name} : statut inconnu « {found.group(1)} » ({', '.join(PLAN_STATUSES)})")
        else:
            statuses[path.name] = found.group(1)

    index = PLANS / "README.md"
    if not index.exists():
        return len(statuses), problems + ["plans/README.md : index absent"]
    listed: set[str] = set()
    for name, target, status in INDEX_ROW_RE.findall(index.read_text(encoding="utf-8")):
        listed.add(name)
        if target != name or not (PLANS / name).exists():
            problems.append(f"plans/README.md : lien cassé vers {target}")
        elif name in statuses and not status.strip().startswith(statuses[name]):
            problems.append(f"plans/README.md : {name} indiqué « {status.strip()} », le plan dit « {statuses[name]} »")
    for path in sorted(PLANS.glob("[0-9]*.md")):
        if path.name not in listed:
            problems.append(f"plans/README.md : {path.name} absent de l'index")
    return len(statuses), problems


def load_scenarios() -> dict[str, list[str]]:
    """Nom de chaque vidéo → scènes, dans l'ordre du scénario."""
    videos: dict[str, list[str]] = {}
    for path in sorted(SCENARIOS.glob("*.mjs")):
        text = path.read_text(encoding="utf-8")
        name = NAME_RE.search(text)
        if name:
            videos[name.group(2)] = [m.group(2) for m in SCENE_RE.finditer(text)]
    return videos


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: dict[str, int] = {}
        self.duplicate_ids: list[tuple[str, int]] = []
        self.links: list[tuple[str, int]] = []
        self.scenes: list[tuple[str | None, str | None, str | None, int]] = []
        self.players: list[tuple[str, int]] = []
        self.has_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = {k: (v or "") for k, v in attrs}
        line = self.getpos()[0]
        if "id" in a:
            if a["id"] in self.ids:
                self.duplicate_ids.append((a["id"], line))
            self.ids.setdefault(a["id"], line)
        for attr in ("href", "src"):
            if a.get(attr):
                self.links.append((a[attr], line))
        if tag == "title":
            self.has_title = True
        if tag == "a" and "scene" in a.get("class", "").split():
            self.scenes.append((a.get("data-video"), a.get("data-scene"), a.get("href"), line))
        if tag == "video" and "data-video" in a:
            self.players.append((a["data-video"], line))


def parse(path: Path) -> Page:
    page = Page()
    page.feed(path.read_text(encoding="utf-8"))
    page.close()
    return page


def main() -> int:
    videos = load_scenarios()
    if not videos:
        print(f"Aucun scénario trouvé dans {SCENARIOS}", file=sys.stderr)
        return 1

    pages = {p: parse(p) for p in sorted(GUIDE.glob("*.html"))}
    problems: list[str] = []
    used_videos: set[str] = set()
    used_scenes: set[tuple[str, str]] = set()

    def rel(path: Path) -> str:
        return str(path.relative_to(DOCS.parent))

    for path, page in pages.items():
        where = rel(path)
        if not page.has_title:
            problems.append(f"{where} : pas de <title>")
        for ident, line in page.duplicate_ids:
            problems.append(f"{where}:{line} : id « {ident} » en double")

        for link, line in page.links:
            parts = urlsplit(link)
            if parts.scheme or parts.netloc or link.startswith("//"):
                continue  # externe, data:, mailto:…
            target_path = unquote(parts.path)
            fragment = unquote(parts.fragment)
            video_file = VIDEO_FILE_RE.match(target_path)
            if video_file:
                name = video_file.group(1)
                if name not in videos:
                    problems.append(f"{where}:{line} : vidéo inconnue « {name} » ({link})")
                continue
            if target_path.startswith("videos/"):
                problems.append(f"{where}:{line} : fichier vidéo inattendu ({link})")
                continue
            target = (path.parent / target_path).resolve() if target_path else path
            if not target.exists():
                problems.append(f"{where}:{line} : lien cassé ({link})")
                continue
            if fragment and target.suffix == ".html":
                ids = pages[target].ids if target in pages else parse(target).ids
                if fragment not in ids:
                    problems.append(f"{where}:{line} : ancre « #{fragment} » absente de {rel(target)}")

        for video, scene, href, line in page.scenes:
            if not video or not scene:
                problems.append(f"{where}:{line} : lien de scène sans data-video ou data-scene")
                continue
            if video not in videos:
                problems.append(f"{where}:{line} : vidéo inconnue « {video} »")
                continue
            used_videos.add(video)
            if scene not in videos[video]:
                problems.append(
                    f"{where}:{line} : scène « {scene} » absente de « {video} » "
                    f"(scènes : {', '.join(videos[video])})"
                )
            else:
                used_scenes.add((video, scene))
            if href != f"videos/{video}.mp4":
                problems.append(f"{where}:{line} : le lien de scène doit pointer vers videos/{video}.mp4 (trouvé : {href})")

        for video, line in page.players:
            if video not in videos:
                problems.append(f"{where}:{line} : lecteur d'une vidéo inconnue « {video} »")
            used_videos.add(video)

    for video in videos:
        if video not in used_videos:
            problems.append(f"vidéo « {video} » absente du guide (ni lecteur ni lien de scène)")

    # Simple information : le lecteur ajoute de lui-même les scènes non citées à la liste des chapitres.
    for video, scenes in videos.items():
        missing = [s for s in scenes if (video, s) not in used_scenes]
        if missing and video in used_videos:
            print(f"info : scènes de « {video} » non citées dans le guide : {', '.join(missing)}")

    plan_count, plan_problems = check_plans()
    problems += plan_problems

    if problems:
        print(f"{len(problems)} problème(s) dans le guide ou les plans :", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"Guide : {len(pages)} pages, {len(used_scenes)} scènes citées sur {sum(map(len, videos.values()))}, liens valides.")
    print(f"Plans : {plan_count} plans, statuts conformes à l'index plans/README.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
