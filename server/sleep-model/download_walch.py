#!/usr/bin/env python3
"""Descarga el dataset Walch (PhysioNet sleep-accel 1.0.0) y lo extrae en data/.

Open-access, sin credenciales. ~577 MB comprimido. El zip extrae las carpetas
motion/ heart_rate/ labels/ steps/ con un fichero por sujeto:
  labels/{id}_labeled_sleep.txt   epoch_seg(múltiplo de 30)  código_etapa
  heart_rate/{id}_heartrate.txt   t_seg,bpm
  motion/{id}_acceleration.txt    t_seg,x,y,z  (g)
Los tiempos comparten el reloj del PSG (las etiquetas empiezan en 0).

Uso:  python3 download_walch.py            # descarga + extrae
      python3 download_walch.py --skip-download   # solo re-extrae el zip ya bajado
"""
from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path
from urllib.request import urlopen

ZIP_URL = "https://physionet.org/content/sleep-accel/get-zip/1.0.0/"
HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
ZIP_PATH = DATA_DIR / "sleep-accel-1.0.0.zip"
# Subcarpetas que necesitamos del zip (steps/ no se usa en el baseline).
WANTED = ("labels", "heart_rate", "motion")


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Descargando {url}\n  → {dest}")
    with urlopen(url) as resp:  # noqa: S310 (URL fija de PhysioNet)
        total = int(resp.headers.get("Content-Length", 0))
        done = 0
        chunk = 1 << 20  # 1 MiB
        with open(dest, "wb") as fh:
            while True:
                buf = resp.read(chunk)
                if not buf:
                    break
                fh.write(buf)
                done += len(buf)
                if total:
                    pct = 100 * done / total
                    sys.stdout.write(
                        f"\r  {done/1e6:7.1f} / {total/1e6:.1f} MB ({pct:5.1f}%)"
                    )
                    sys.stdout.flush()
    print("\n  descarga completa.")


def extract(zip_path: Path, out_dir: Path) -> None:
    print(f"Extrayendo en {out_dir} (solo {', '.join(WANTED)}/) …")
    with zipfile.ZipFile(zip_path) as zf:
        members = zf.namelist()
        # El zip anida todo bajo una carpeta raíz tipo "sleep-accel-1.0.0/".
        n = 0
        for m in members:
            parts = Path(m).parts
            if len(parts) < 2:
                continue
            sub = parts[1]  # carpeta tras la raíz
            if sub not in WANTED or m.endswith("/"):
                continue
            target = out_dir / Path(*parts[1:])  # quita la carpeta raíz
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(m) as src, open(target, "wb") as dst:
                dst.write(src.read())
            n += 1
            if n % 20 == 0:
                sys.stdout.write(f"\r  {n} ficheros extraídos")
                sys.stdout.flush()
    print(f"\n  listo: {n} ficheros en {out_dir}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-download", action="store_true",
                    help="no bajar; reutilizar el zip ya presente")
    args = ap.parse_args()

    if not args.skip_download:
        download(ZIP_URL, ZIP_PATH)
    elif not ZIP_PATH.exists():
        print(f"ERROR: --skip-download pero no existe {ZIP_PATH}", file=sys.stderr)
        return 1

    extract(ZIP_PATH, DATA_DIR)

    for sub in WANTED:
        d = DATA_DIR / sub
        n = len(list(d.glob("*.txt"))) if d.exists() else 0
        print(f"  {sub}/: {n} ficheros")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
