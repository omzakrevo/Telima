#!/usr/bin/env python3
"""Découpe l'APK universel de Telima en APK légers par type de processeur (moins de 50 Mo chacun).

Pourquoi : le forfait gratuit de Supabase refuse les fichiers de plus de 50 Mo (Admin > Mises à jour appli).
L'APK universel fait environ 75 Mo ; chaque APK par processeur en fait 23 à 27.

Utilisation (après `shorebird release android --artifact apk ...` ou `flutter build apk --release`) :
    python scripts/split_apk.py
    python scripts/split_apk.py chemin/vers/app-release.apk --out C:/Users/vous/Downloads

Résultat : Telima-<version>-<build>-arm64.apk (téléphones récents) et ...-arm32.apk (anciens téléphones).
Le code de l'application (libapp.so) n'est pas modifié : les correctifs Shorebird continuent de fonctionner.
La signature utilise la clé de l'application (app/android/app/telima-signing.jks) : l'installation par-dessus
l'ancienne version reste possible. Variables facultatives : TELIMA_STORE_PASSWORD, TELIMA_KEY_ALIAS, TELIMA_KEY_PASSWORD
(mêmes valeurs par défaut que app/android/app/build.gradle.kts).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
ABIS = {"arm64": "arm64-v8a", "arm32": "armeabi-v7a"}


def build_tools() -> Path:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or str(
        Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "Android" / "Sdk")
    bt = Path(sdk) / "build-tools"
    versions = sorted((p for p in bt.glob("*") if (p / ("zipalign.exe" if os.name == "nt" else "zipalign")).exists()),
                      key=lambda p: [int(x) for x in re.findall(r"\d+", p.name)])
    if not versions:
        sys.exit(f"Android build-tools introuvables dans {bt}. Installez-les avec Android Studio (SDK Manager).")
    return versions[-1]


def version_label() -> str:
    m = re.search(r"^version:\s*([0-9.]+)\+(\d+)", (APP / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    return f"{m.group(1)}-{m.group(2)}" if m else "app"


def strip_abis(src: Path, keep_abi: str, dst: Path) -> None:
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w") as zout:
        for info in zin.infolist():
            name = info.filename
            if name.startswith("META-INF/") and name.endswith((".SF", ".RSA", ".DSA", ".EC", ".MF")):
                continue  # ancienne signature, on resigne
            if name.startswith("lib/") and not name.startswith(f"lib/{keep_abi}/"):
                continue
            zout.writestr(info, zin.read(name), compress_type=info.compress_type)


def run(cmd: list[str]) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, shell=False)
    if r.returncode != 0:
        sys.exit(f"Échec : {' '.join(cmd[:2])}\n{r.stdout}\n{r.stderr}")
    return r.stdout


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("apk", nargs="?", default=str(APP / "build/app/outputs/flutter-apk/app-release.apk"))
    ap.add_argument("--out", default=str(Path.home() / "Downloads"))
    ap.add_argument("--keystore", default=str(APP / "android/app/telima-signing.jks"))
    args = ap.parse_args()

    src, out = Path(args.apk), Path(args.out)
    if not src.is_file():
        sys.exit(f"APK introuvable : {src}")
    if not Path(args.keystore).is_file():
        sys.exit(f"Clé de signature introuvable : {args.keystore}")
    out.mkdir(parents=True, exist_ok=True)

    bt = build_tools()
    exe = ".exe" if os.name == "nt" else ""
    bat = ".bat" if os.name == "nt" else ""
    zipalign, apksigner = str(bt / f"zipalign{exe}"), str(bt / f"apksigner{bat}")
    store_pw = os.environ.get("TELIMA_STORE_PASSWORD", "android")
    alias = os.environ.get("TELIMA_KEY_ALIAS", "androiddebugkey")
    key_pw = os.environ.get("TELIMA_KEY_PASSWORD", "android")
    label = version_label()

    with zipfile.ZipFile(src) as z:
        present = {n.split("/")[1] for n in z.namelist() if n.startswith("lib/") and n.count("/") >= 2}
    print(f"APK source : {src.name} ({src.stat().st_size / 1048576:.1f} Mo), processeurs présents : {', '.join(sorted(present))}")

    with tempfile.TemporaryDirectory() as tmp:
        for short, abi in ABIS.items():
            if abi not in present:
                print(f"  {short} : absent de l'APK, ignoré")
                continue
            raw, aligned = Path(tmp) / f"{short}-raw.apk", Path(tmp) / f"{short}-aligned.apk"
            dst = out / f"Telima-{label}-{short}.apk"
            strip_abis(src, abi, raw)
            run([zipalign, "-f", "-P", "16", "4", str(raw), str(aligned)])
            run([apksigner, "sign", "--ks", args.keystore, "--ks-key-alias", alias,
                 "--ks-pass", f"pass:{store_pw}", "--key-pass", f"pass:{key_pw}", "--out", str(dst), str(aligned)])
            run([apksigner, "verify", str(dst)])
            Path(str(dst) + ".idsig").unlink(missing_ok=True)  # fichier annexe inutile ici
            size = dst.stat().st_size / 1048576
            flag = "OK" if size < 50 else "ATTENTION : dépasse 50 Mo"
            print(f"  {short} : {dst} ({size:.1f} Mo) signé et vérifié · {flag}")
    print("Terminé. Publiez ces fichiers dans Admin > Mises à jour appli (un fichier par type de téléphone).")


if __name__ == "__main__":
    main()
