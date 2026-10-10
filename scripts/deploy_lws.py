#!/usr/bin/env python3
"""Envoie le site web Telima (app/build/web) sur l'hébergement LWS par SFTP.

Prérequis (une seule fois) :
    pip install paramiko

Identifiants : à définir sur votre PC, jamais dans le projet ni dans une conversation.
    setx LWS_HOST  "sftp.exemple.lws.fr"
    setx LWS_USER  "votre_identifiant"
    setx LWS_PASS  "votre_mot_de_passe"          (ou LWS_KEY = chemin d'une clé privée)
    setx LWS_DIR   "/htdocs"                      (dossier du site, par défaut « . »)
    setx LWS_PORT  "22"                           (facultatif)
Puis ouvrez un NOUVEAU terminal (les variables ne sont lues qu'au démarrage du terminal).

Utilisation :
    python scripts/deploy_lws.py            # simulation : liste ce qui serait envoyé
    python scripts/deploy_lws.py --yes      # envoie réellement les fichiers
    python scripts/deploy_lws.py --yes --htaccess   # envoie aussi une règle .htaccess

Le script :
  - remplace __SUPABASE_URL__ et __SUPABASE_ANON_KEY__ dans index.html et telecharger/index.html
    (valeurs lues dans app/env.json) ;
  - n'envoie que les fichiers absents ou de taille différente ;
  - ne supprime jamais rien sur le serveur ;
  - avec --htaccess, sauvegarde d'abord l'éventuel .htaccess existant en .htaccess.bak.
"""
import argparse
import json
import os
import posixpath
import sys
from pathlib import Path

try:
    import paramiko
except ImportError:
    sys.exit("Installez d'abord paramiko :  pip install paramiko")

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "app" / "build" / "web"
ENV = ROOT / "app" / "env.json"
TEMPLATED = {"index.html", "telecharger/index.html"}

HTACCESS = """# Telima : réécriture pour l'application web, MIME, compression et cache
<IfModule mod_mime.c>
  AddType application/wasm .wasm
  AddType application/json .json
</IfModule>
<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/css text/javascript application/javascript application/json application/wasm image/svg+xml
</IfModule>
<IfModule mod_headers.c>
  <FilesMatch "\\.(js|wasm|otf|ttf|png|webp|ico)$">
    Header set Cache-Control "public, max-age=604800"
  </FilesMatch>
  <FilesMatch "(index\\.html|version\\.json|flutter_bootstrap\\.js|sw\\.js)$">
    Header set Cache-Control "no-cache"
  </FilesMatch>
</IfModule>
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteCond %{REQUEST_URI} !^/\\.well-known/
  RewriteRule ^ index.html [L]
</IfModule>
"""


def content(rel: str, supabase: dict) -> bytes:
    data = (WEB / rel).read_bytes()
    if rel in TEMPLATED:
        text = data.decode("utf-8")
        text = text.replace("__SUPABASE_URL__", supabase["SUPABASE_URL"])
        text = text.replace("__SUPABASE_ANON_KEY__", supabase["SUPABASE_ANON_KEY"])
        data = text.encode("utf-8")
    return data


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--yes", action="store_true", help="envoyer réellement (sinon simulation)")
    ap.add_argument("--htaccess", action="store_true", help="envoyer aussi un .htaccess (sauvegarde l'ancien)")
    args = ap.parse_args()

    if not WEB.is_dir():
        sys.exit(f"Dossier introuvable : {WEB}\nCompilez d'abord : flutter build web --release --dart-define-from-file=env.json")
    supabase = json.loads(ENV.read_text(encoding="utf-8-sig"))

    host, user = os.environ.get("LWS_HOST"), os.environ.get("LWS_USER")
    password, key = os.environ.get("LWS_PASS"), os.environ.get("LWS_KEY")
    base = os.environ.get("LWS_DIR") or "."
    port = int(os.environ.get("LWS_PORT") or "22")
    if not (host and user and (password or key)):
        sys.exit("Variables manquantes : LWS_HOST, LWS_USER et LWS_PASS (ou LWS_KEY). Voir l'en-tête du script.")

    files = sorted(
        p.relative_to(WEB).as_posix()
        for p in WEB.rglob("*")
        if p.is_file() and p.name != ".last_build_id"
    )

    transport = paramiko.Transport((host, port))
    if key:
        transport.connect(username=user, pkey=paramiko.RSAKey.from_private_key_file(key))
    else:
        transport.connect(username=user, password=password)
    sftp = paramiko.SFTPClient.from_transport(transport)

    def mkdirs(path: str) -> None:
        parts, cur = path.split("/"), ""
        for part in parts:
            if not part:
                cur = "/"
                continue
            cur = posixpath.join(cur, part) if cur else part
            try:
                sftp.stat(cur)
            except IOError:
                sftp.mkdir(cur)

    todo = []
    for rel in files:
        data = content(rel, supabase)
        remote = posixpath.join(base, rel)
        try:
            same = sftp.stat(remote).st_size == len(data)
        except IOError:
            same = False
        if not same:
            todo.append((rel, remote, data))

    print(f"{len(files)} fichiers locaux, {len(todo)} à envoyer.")
    for rel, _, data in todo:
        print(f"  {'envoi' if args.yes else 'à envoyer'} : {rel} ({len(data) / 1024:.0f} Ko)")

    if args.yes:
        for rel, remote, data in todo:
            mkdirs(posixpath.dirname(remote))
            with sftp.open(remote, "wb") as fh:
                fh.write(data)
        if args.htaccess:
            ht = posixpath.join(base, ".htaccess")
            try:
                sftp.stat(ht)
                sftp.rename(ht, ht + ".bak")
                print("Ancien .htaccess sauvegardé en .htaccess.bak")
            except IOError:
                pass
            with sftp.open(ht, "wb") as fh:
                fh.write(HTACCESS.encode("utf-8"))
            print(".htaccess envoyé.")
        print("Terminé.")
    else:
        print("Simulation seulement. Relancez avec --yes pour envoyer.")
    sftp.close()
    transport.close()


if __name__ == "__main__":
    main()
