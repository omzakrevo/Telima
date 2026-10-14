#!/usr/bin/env python3
"""Publie un APK dans « Mises à jour appli » (bucket telima-releases + table telima.app_releases).

Variables : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, VERSION_NAME, VERSION_N (numéro après le +, moins 2000),
NOTES, MANDATORY (true/false), APK (chemin du fichier).
"""
import json
import os
import urllib.request
from urllib.parse import urlparse

u = urlparse(os.environ["SUPABASE_URL"].strip())
base = f"{u.scheme}://{u.netloc}"
key = os.environ["SUPABASE_SERVICE_ROLE_KEY"].strip()
n = int(os.environ["VERSION_N"])
path = f"android/{n}/app-release.apk"
apk = open(os.environ["APK"], "rb").read()
print(f"APK : {len(apk) // 1024} Ko")
req = urllib.request.Request(
    f"{base}/storage/v1/object/telima-releases/{path}", data=apk, method="POST",
    headers={"apikey": key, "Authorization": f"Bearer {key}",
             "Content-Type": "application/vnd.android.package-archive", "x-upsert": "true"})
urllib.request.urlopen(req, timeout=600).read()
row = {"platform": "android", "version_name": os.environ["VERSION_NAME"], "version_code": n,
       "apk_universal_path": path, "notes": os.environ.get("NOTES") or None,
       "mandatory": os.environ.get("MANDATORY") == "true", "is_published": True}
req = urllib.request.Request(
    f"{base}/rest/v1/app_releases?on_conflict=platform,version_code", data=json.dumps(row).encode(), method="POST",
    headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json",
             "Content-Profile": "telima", "Prefer": "resolution=merge-duplicates,return=minimal"})
urllib.request.urlopen(req, timeout=60).read()
print(f"Version {os.environ['VERSION_NAME']} (numéro {n}) publiée dans « Mises à jour appli ».")
