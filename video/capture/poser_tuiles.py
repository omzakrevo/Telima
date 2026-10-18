"""Pose les vraies tuiles OpenStreetMap sous les cartes des captures (flutter test ne charge pas les tuiles).

Utilisation : python3 poser_tuiles.py <dossier des captures> <fichier des lignes CARTE>
Chaque ligne « CARTE <nom> <lat> <lng> <zoom> <gauche> <haut> <largeur> <hauteur> » (pixels logiques) est produite par
livreur_commande_shots_test.dart. Le fond gris de flutter_map (#E0E0E0) est remplacé par les tuiles ; marqueurs et tracés restent.
"""
import io
import math
import subprocess
import sys

import numpy as np
from PIL import Image

DPR = 3
BG = np.array([0xE0, 0xE0, 0xE0])
_cache = {}


def tile(z, x, y):
    k = (z, x, y)
    if k not in _cache:
        data = subprocess.run(['curl', '-sS', '-A', 'telima-video/1.0 (capture promo)',
                               f'https://tile.openstreetmap.org/{z}/{x}/{y}.png'], capture_output=True, check=True).stdout
        _cache[k] = Image.open(io.BytesIO(data)).convert('RGB')
    return _cache[k]


def world(lat, lng, z):
    n = 256 * 2 ** z
    x = (lng + 180) / 360 * n
    s = math.sin(math.radians(lat))
    y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n
    return x, y


def render(lat, lng, zoom, w, h):
    """Image de la carte w×h (pixels logiques) rendue en pixels physiques (×DPR), comme flutter_map."""
    zi = round(zoom)
    cx, cy = world(lat, lng, zi)
    scale = 2 ** (zoom - zi)  # taille logique d'un pixel de tuile
    hw, hh = w / 2 / scale, h / 2 / scale  # demi-taille en pixels de tuile
    x0, y0, x1, y1 = cx - hw, cy - hh, cx + hw, cy + hh
    tx0, ty0, tx1, ty1 = int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)
    mosaic = Image.new('RGB', ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            mosaic.paste(tile(zi, tx, ty), ((tx - tx0) * 256, (ty - ty0) * 256))
    box = (x0 - tx0 * 256, y0 - ty0 * 256, x1 - tx0 * 256, y1 - ty0 * 256)
    return mosaic.resize((round(w * DPR), round(h * DPR)), Image.LANCZOS, box=box)


def main(shots, lines):
    done = set()
    for line in open(lines, encoding='utf-8'):
        if 'CARTE' not in line:
            continue
        parts = line.split('CARTE', 1)[1].split()
        name = parts[0]
        lat, lng, zoom, left, top, w, h = map(float, parts[1:8])
        if (name, left, top) in done:
            continue
        done.add((name, left, top))
        path = f'{shots}/{name}.png'
        img = np.array(Image.open(path).convert('RGB')).astype(np.int16)
        L, T = round(left * DPR), round(top * DPR)
        W, H = round(w * DPR), round(h * DPR)
        region = img[T:T + H, L:L + W]
        osm = np.array(render(lat, lng, zoom, w, h)).astype(np.int16)[:region.shape[0], :region.shape[1]]
        # proximité du gris de fond : 1 = fond pur, 0 = élément dessiné (marqueur, tracé) ; transition douce sur les bords
        d = np.abs(region - BG).max(axis=2)
        a = np.clip(1 - d / 14.0, 0, 1)[..., None]
        img[T:T + H, L:L + W] = (osm * a + region * (1 - a)).round().astype(np.int16)
        Image.fromarray(img.clip(0, 255).astype(np.uint8)).save(path)
        print('tuiles posées :', name)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
