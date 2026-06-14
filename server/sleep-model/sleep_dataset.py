#!/usr/bin/env python3
"""Construye la matriz de features por epoch de 30 s del dataset Walch.

Walch da HR en bpm (PPG, muestreo irregular) y acelerómetro de muñeca, NO la
serie IBI latido-a-latido. Por eso aquí los features cardíacos son derivados de
HR (media/dispersión/variación), no RMSSD/SDNN reales — esos llegarán con MESA
(ECG→IBI) en la fase 2. Los features se diseñan para ser reproducibles luego en
nuestro hardware (de la WHOOP derivamos HR desde el IBI).

Etapas PSG → 4 clases:  0 Wake | 1,2 Light | 3 Deep | 5 REM  (−1 se descarta).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

EPOCH_S = 30
# código PSG → clase de 4 (índice). N1 y N2 se fusionan en "Ligero".
STAGE_MAP = {0: 0, 1: 1, 2: 1, 3: 2, 5: 3}
CLASS_NAMES = ["Wake", "Light", "Deep", "REM"]
# Umbral de inmovilidad sobre la desviación de la magnitud dinámica (g).
_IMMOBILITY_STD = 0.02
# Ventanas de contexto (en nº de epochs) para medias móviles centradas.
_CONTEXT_WINDOWS = (3, 5, 11)


def _epoch_index(t: np.ndarray) -> np.ndarray:
    return np.floor(np.asarray(t, dtype=float) / EPOCH_S).astype(np.int64)


def _load_labels(path: Path) -> pd.DataFrame:
    arr = np.loadtxt(path)
    if arr.ndim == 1:
        arr = arr.reshape(1, -1)
    df = pd.DataFrame({"t": arr[:, 0].astype(np.int64),
                       "stage_psg": arr[:, 1].astype(int)})
    df = df[df["stage_psg"].isin(STAGE_MAP)].copy()
    df["ei"] = (df["t"] // EPOCH_S).astype(np.int64)
    df["label"] = df["stage_psg"].map(STAGE_MAP).astype(int)
    return df[["ei", "label"]].drop_duplicates("ei").set_index("ei")


def _hr_epoch_features(path: Path) -> pd.DataFrame:
    hr = pd.read_csv(path, header=None, names=["t", "bpm"])
    hr = hr.dropna().sort_values("t")
    hr["ei"] = _epoch_index(hr["t"].values)
    # Variación latido-irregular: |Δbpm| entre muestras consecutivas, atribuida
    # al epoch de la muestra posterior (proxy de VFC sin IBI real).
    hr["absdiff"] = hr["bpm"].diff().abs()
    g = hr.groupby("ei")
    feat = pd.DataFrame({
        "hr_mean": g["bpm"].mean(),
        "hr_std": g["bpm"].std(),
        "hr_min": g["bpm"].min(),
        "hr_max": g["bpm"].max(),
        "hr_absdiff": g["absdiff"].mean(),
        "hr_n": g["bpm"].size(),
    })
    feat["hr_range"] = feat["hr_max"] - feat["hr_min"]
    return feat


def _motion_epoch_features(path: Path) -> pd.DataFrame:
    # motion/*.txt es separado por ESPACIOS (a diferencia de heart_rate, que usa coma).
    mo = pd.read_csv(path, header=None, names=["t", "x", "y", "z"], sep=r"\s+")
    mo = mo.dropna()
    mag = np.sqrt(mo["x"] ** 2 + mo["y"] ** 2 + mo["z"] ** 2)
    # Aceleración dinámica: quita la gravedad (≈1 g) para medir solo movimiento.
    mo = mo.assign(dyn=(mag - 1.0).abs(), ei=_epoch_index(mo["t"].values))
    g = mo.groupby("ei")
    feat = pd.DataFrame({
        "act_std": g["dyn"].std(),
        "act_mean": g["dyn"].mean(),
        "act_max": g["dyn"].max(),
        "act_n": g["dyn"].size(),
    })
    feat["immobile"] = (feat["act_std"].fillna(0.0) < _IMMOBILITY_STD).astype(float)
    return feat


def _add_context(df: pd.DataFrame, cols: list[str]) -> pd.DataFrame:
    """Medias móviles centradas + delta vs epoch anterior, sobre la rejilla densa."""
    out = df.copy()
    for c in cols:
        for w in _CONTEXT_WINDOWS:
            out[f"{c}_ma{w}"] = df[c].rolling(w, center=True, min_periods=1).mean()
        out[f"{c}_d1"] = df[c].diff()
    return out


def build_subject(subject_id: str, data_dir: Path) -> pd.DataFrame | None:
    """Devuelve un DataFrame por-epoch (features + label + subject) o None si falta algo."""
    lab_p = data_dir / "labels" / f"{subject_id}_labeled_sleep.txt"
    hr_p = data_dir / "heart_rate" / f"{subject_id}_heartrate.txt"
    mo_p = data_dir / "motion" / f"{subject_id}_acceleration.txt"
    if not (lab_p.exists() and hr_p.exists() and mo_p.exists()):
        return None

    labels = _load_labels(lab_p)
    if labels.empty:
        return None
    hr = _hr_epoch_features(hr_p)
    mo = _motion_epoch_features(mo_p)

    lo, hi = int(labels.index.min()), int(labels.index.max())
    grid = pd.RangeIndex(lo, hi + 1, name="ei")
    feat = (hr.reindex(grid).join(mo.reindex(grid)))

    base_cols = ["hr_mean", "hr_std", "hr_min", "hr_max", "hr_range",
                 "hr_absdiff", "act_std", "act_mean", "act_max", "immobile"]
    # Relleno suave de huecos antes del contexto temporal.
    feat[base_cols] = feat[base_cols].interpolate(limit_direction="both")
    feat = _add_context(feat, ["hr_mean", "hr_std", "act_std", "act_mean", "hr_absdiff"])

    # HR relativo a la mediana de la noche (ayuda a separar sueño profundo).
    feat["hr_rel"] = feat["hr_mean"] - feat["hr_mean"].median()
    # Temporales: posición en la noche desde el primer epoch etiquetado.
    n = hi - lo + 1
    feat["t_since_start"] = (feat.index - lo).astype(float)
    feat["t_norm"] = feat["t_since_start"] / max(n - 1, 1)

    feat = feat.join(labels, how="inner")  # solo epochs con etiqueta válida
    feat["subject"] = subject_id
    feat = feat.replace([np.inf, -np.inf], np.nan)
    return feat.reset_index(drop=True)


def list_subjects(data_dir: Path) -> list[str]:
    lab = data_dir / "labels"
    ids = sorted(p.name.split("_labeled_sleep.txt")[0]
                 for p in lab.glob("*_labeled_sleep.txt"))
    return ids


def build_dataset(data_dir: Path):
    """Devuelve (X: DataFrame, y: np.ndarray, groups: np.ndarray, feature_cols)."""
    frames = []
    for sid in list_subjects(data_dir):
        f = build_subject(sid, data_dir)
        if f is not None and not f.empty:
            frames.append(f)
    if not frames:
        raise SystemExit(f"No se encontraron sujetos en {data_dir}. ¿Descargaste Walch?")
    df = pd.concat(frames, ignore_index=True)

    drop = {"label", "subject"}
    feature_cols = [c for c in df.columns if c not in drop]
    # Imputación final por mediana global (RF no admite NaN).
    X = df[feature_cols].fillna(df[feature_cols].median())
    y = df["label"].to_numpy()
    groups = df["subject"].to_numpy()
    return X, y, groups, feature_cols
