#!/usr/bin/env python3
"""Baseline RandomForest de etapas de sueño (4 clases) con validación por sujeto.

Honestidad: la validación es GroupKFold POR SUJETO (ningún epoch del sujeto de
test aparece en train) → estima generalización real, no fuga por epoch. Se
reporta κ de Cohen, accuracy, F1 macro y matriz de confusión 4 clases.

Uso (dentro de la imagen whoop-ingest, ver run.sh):
    python3 train_baseline.py [--folds N] [--trees N] [--data DIR]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from sleep_dataset import CLASS_NAMES, build_dataset

HERE = Path(__file__).resolve().parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(HERE / "data"))
    ap.add_argument("--folds", type=int, default=10)
    ap.add_argument("--trees", type=int, default=300)
    ap.add_argument("--out", default=str(HERE / "outputs"))
    args = ap.parse_args()

    # Imports pesados aquí para que --help no requiera sklearn.
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import (classification_report, cohen_kappa_score,
                                 confusion_matrix, f1_score)
    from sklearn.model_selection import GroupKFold
    import joblib

    data_dir = Path(args.data)
    print(f"Cargando dataset desde {data_dir} …")
    X, y, groups, feature_cols = build_dataset(data_dir)
    n_subj = len(np.unique(groups))
    print(f"  {len(X)} epochs · {len(feature_cols)} features · {n_subj} sujetos")
    dist = {CLASS_NAMES[c]: int((y == c).sum()) for c in range(len(CLASS_NAMES))}
    print(f"  distribución de clases: {dist}")

    folds = min(args.folds, n_subj)
    gkf = GroupKFold(n_splits=folds)
    oof = np.full(len(y), -1, dtype=int)  # predicciones out-of-fold

    for k, (tr, te) in enumerate(gkf.split(X, y, groups), 1):
        clf = RandomForestClassifier(
            n_estimators=args.trees,
            class_weight="balanced",
            min_samples_leaf=5,
            n_jobs=-1,
            random_state=42,
        )
        clf.fit(X.iloc[tr], y[tr])
        oof[te] = clf.predict(X.iloc[te])
        print(f"  fold {k}/{folds}: "
              f"κ={cohen_kappa_score(y[te], oof[te]):.3f}  "
              f"acc={(oof[te] == y[te]).mean():.3f}")

    kappa = cohen_kappa_score(y, oof)
    acc = float((oof == y).mean())
    f1m = f1_score(y, oof, average="macro")
    cm = confusion_matrix(y, oof, labels=list(range(len(CLASS_NAMES))))

    print("\n=== Resultado global (out-of-fold, por sujeto) ===")
    print(f"  κ de Cohen : {kappa:.3f}")
    print(f"  accuracy   : {acc:.3f}")
    print(f"  F1 macro   : {f1m:.3f}")
    print("\n  matriz de confusión (filas=real, cols=predicho):")
    header = "        " + "".join(f"{c:>8}" for c in CLASS_NAMES)
    print(header)
    for i, row in enumerate(cm):
        print(f"  {CLASS_NAMES[i]:>6}" + "".join(f"{v:8d}" for v in row))
    print("\n" + classification_report(y, oof, target_names=CLASS_NAMES,
                                       digits=3, zero_division=0))

    # Modelo final sobre TODOS los datos + importancias + métricas.
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    final = RandomForestClassifier(
        n_estimators=args.trees, class_weight="balanced",
        min_samples_leaf=5, n_jobs=-1, random_state=42)
    final.fit(X, y)
    joblib.dump({"model": final, "feature_cols": feature_cols,
                 "class_names": CLASS_NAMES}, out_dir / "rf_baseline.joblib")

    imp = sorted(zip(feature_cols, final.feature_importances_),
                 key=lambda t: -t[1])[:12]
    print("Top features:", ", ".join(f"{n}={v:.3f}" for n, v in imp))

    metrics = {
        "kappa": kappa, "accuracy": acc, "f1_macro": f1m,
        "n_epochs": int(len(X)), "n_subjects": int(n_subj),
        "class_distribution": dist,
        "confusion_matrix": cm.tolist(),
        "top_features": imp,
    }
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2))
    print(f"\nGuardado modelo y métricas en {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
