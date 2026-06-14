#!/usr/bin/env bash
# Ejecuta un script de este directorio dentro de la imagen whoop-ingest, que ya
# trae numpy/scipy/scikit-learn/neurokit2/pandas. No instala nada en el host ni
# toca el container en ejecución (usa --rm, one-off).
#
#   ./run.sh train_baseline.py --folds 10
#   ./run.sh sleep_dataset.py            # (no hace nada por sí solo)
#
# La descarga del dataset se hace en el HOST (necesita red): python3 download_walch.py
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${SLEEP_MODEL_IMAGE:-server-whoop-ingest:latest}"
exec docker run --rm -v "$DIR":/work -w /work "$IMAGE" python3 "$@"
