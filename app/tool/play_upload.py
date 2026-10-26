# /// script
# requires-python = ">=3.12"
# dependencies = ["google-auth>=2.30", "requests>=2.32"]
# ///
"""Envoie un app bundle de « Clockifai » sur Google Play, piste de test interne par défaut.

  make app-upload-android [AAB=app/build/Clockifai-<version>-<build>.aab]   (le plus récent par défaut)
  uv run --script app/tool/play_upload.py [--track internal] [--dry-run] [fichier.aab]

Compte de service Google hors du dépôt, comme la clé d'envoi : ~/.config/clockifai/android/play-service-account.json
(PLAY_SERVICE_ACCOUNT=… pour un autre chemin), invité dans la Play Console avec le droit de publier sur les pistes de
test. Notes de version : les entrées du CHANGELOG pour cette version qui tiennent dans les 500 caractères de Google.
"""

import argparse
import os
import re
import sys
from pathlib import Path

PACKAGE = 'com.kysoe.clockifai'
API = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'
UPLOAD = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}'
ROOT = Path(__file__).resolve().parents[2]
KEY = Path(os.environ.get('PLAY_SERVICE_ACCOUNT', Path.home() / '.config/clockifai/android/play-service-account.json'))
NOTES_MAX = 500


def release_notes(version: str) -> str:
    """Entrées de la section « [version] » du CHANGELOG, sans gras ni date d'arrivée, tant qu'elles tiennent."""
    changelog = (ROOT / 'CHANGELOG.md').read_text(encoding='utf-8')
    section = re.search(rf'^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|\Z)', changelog, re.MULTILINE | re.DOTALL)
    if not section:
        return ''
    body = '\n'.join(line for line in section.group(1).splitlines() if not line.startswith('#'))
    notes = ''
    for item in re.split(r'^- ', body, flags=re.MULTILINE)[1:]:
        item = ' '.join(item.split())
        item = re.sub(r'\*\*(.+?)\*\*', r'\1', item)
        item = re.sub(r' \(\d{1,2}(?:er)? \w+ \d{4}\)', '', item)
        line = f'• {item}'
        if len(notes) + len(line) + 1 <= NOTES_MAX:
            notes = f'{notes}\n{line}' if notes else line
    return notes


class PlayError(Exception):
    pass


def check(response):
    if response.ok:
        return response.json() if response.content else {}
    try:
        message = response.json()['error']['message']
    except (ValueError, KeyError):
        message = response.text[:300]
    raise PlayError(message)


def publish(session, aab: Path, version: str, track: str, notes: str) -> str:
    edit = check(session.post(f'{API}/edits'))['id']
    with aab.open('rb') as f:
        bundle = check(session.post(f'{UPLOAD}/edits/{edit}/bundles', params={'uploadType': 'media'}, data=f,
                                    headers={'Content-Type': 'application/octet-stream'}, timeout=900))
    release = {'name': version, 'versionCodes': [str(bundle['versionCode'])], 'status': 'completed'}
    if notes:
        language = check(session.get(f'{API}/edits/{edit}/details'))['defaultLanguage']
        release['releaseNotes'] = [{'language': language, 'text': notes}]

    def put_and_commit(params=None):
        check(session.put(f'{API}/edits/{edit}/tracks/{track}', json={'track': track, 'releases': [release]}))
        check(session.post(f'{API}/edits/{edit}:commit', params=params))

    try:
        put_and_commit()
    except PlayError as e:
        if 'draft' in str(e).lower():
            # Une app jamais publiée n'accepte que des versions en brouillon, à déployer depuis la Play Console.
            release['status'] = 'draft'
            put_and_commit()
        elif 'changesNotSentForReview' in str(e):
            put_and_commit({'changesNotSentForReview': 'true'})
        else:
            raise
    return release['status']


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('aab', nargs='?', type=Path, help='app bundle (le plus récent de app/build par défaut)')
    parser.add_argument('--track', default=os.environ.get('PLAY_TRACK', 'internal'))
    parser.add_argument('--dry-run', action='store_true', help='affiche ce qui serait envoyé, sans rien envoyer')
    args = parser.parse_args()

    aab = args.aab or max((ROOT / 'app/build').glob('Clockifai-*.aab'), key=lambda p: p.stat().st_mtime, default=None)
    if aab is None or not aab.is_file():
        sys.exit(f'App bundle introuvable ({aab or "app/build/Clockifai-*.aab"}) : make app-dist-android')
    name = re.fullmatch(r'Clockifai-(.+)-(\d+)\.aab', aab.name)
    if not name:
        sys.exit(f'Nom inattendu : {aab.name} (Clockifai-<version>-<build>.aab, comme make app-dist-android)')
    version, build = name.groups()
    notes = release_notes(version)
    print(f'[play] {aab.name} → piste « {args.track} » de {PACKAGE}, version {version} ({build})')
    if args.dry_run:
        print(f'[play] notes ({len(notes)} caractères) :\n{notes}')
        return
    if not KEY.is_file():
        sys.exit(f'Compte de service absent ({KEY}) : voir « Google Play » dans le README.')

    from google.auth.exceptions import RefreshError
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    credentials = service_account.Credentials.from_service_account_file(
        str(KEY), scopes=['https://www.googleapis.com/auth/androidpublisher'])
    try:
        status = publish(AuthorizedSession(credentials), aab, version, args.track, notes)
    except RefreshError as e:
        sys.exit(f'Compte de service refusé par Google : {e}')
    except PlayError as e:
        sys.exit(f'Google Play a refusé l\'envoi : {e}')
    if status == 'draft':
        print('[play] envoyé en brouillon (app pas encore publiée) :',
              f'Play Console > Tester et publier > « {args.track} ».')
    else:
        print(f'[play] envoyé : {version} ({build}) sur la piste « {args.track} »,',
              'proposé aux testeurs après traitement.')


if __name__ == '__main__':
    main()
