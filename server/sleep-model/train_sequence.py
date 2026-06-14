#!/usr/bin/env python3
"""Fase 3 — suavizado temporal HMM/Viterbi sobre las posteriores del RF.

El baseline RF predice cada epoch de forma independiente, así que Deep y REM se
derraman a Light (las etapas "saltan" de un epoch al siguiente de un modo que la
fisiología no permite). Aquí imponemos continuidad temporal sin red neuronal:

  - emisión   = posterior del RF convertida a verosimilitud  p(x|s) ∝ p(s|x)/p(s)
  - transición= matriz A 4x4 aprendida de las secuencias PSG (solo del train fold)
  - decodificación = Viterbi por noche (secuencia contigua de 30 s por sujeto)

Todo se mide out-of-fold por sujeto (GroupKFold) → sin fuga, comparable 1:1 con
el baseline. Reporta κ crudo (argmax RF) vs κ suavizado (Viterbi).

Uso (dentro de la imagen whoop-ingest, ver run.sh):
    python3 train_sequence.py [--folds N] [--trees N] [--data DIR]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from sleep_dataset import CLASS_NAMES, build_dataset

HERE = Path(__file__).resolve().parent
N_CLASSES = len(CLASS_NAMES)
_EPS = 1e-9


def _subject_blocks(groups: np.ndarray) -> list[tuple[int, int]]:
    """Índices [inicio, fin) de cada bloque contiguo de sujeto (orden preservado)."""
    blocks = []
    start = 0
    for i in range(1, len(groups) + 1):
        if i == len(groups) or groups[i] != groups[start]:
            blocks.append((start, i))
            start = i
    return blocks


def _learn_transitions(y: np.ndarray, groups: np.ndarray):
    """Matriz de transición A (fila=estado t, col=estado t+1) e inicial π,
    aprendidas SOLO de las secuencias dadas (las del train fold). Add-one."""
    A = np.ones((N_CLASSES, N_CLASSES), dtype=float)  # suavizado de Laplace
    pi = np.ones(N_CLASSES, dtype=float)
    prior = np.ones(N_CLASSES, dtype=float)
    for s, e in _subject_blocks(groups):
        seq = y[s:e]
        pi[seq[0]] += 1
        for c in range(N_CLASSES):
            prior[c] += int((seq == c).sum())
        for a, b in zip(seq[:-1], seq[1:]):
            A[a, b] += 1
    A /= A.sum(axis=1, keepdims=True)
    pi /= pi.sum()
    prior /= prior.sum()
    return A, pi, prior


def _viterbi(log_emit: np.ndarray, log_A: np.ndarray, log_pi: np.ndarray) -> np.ndarray:
    """Viterbi clásico. log_emit: (T, S). Devuelve la secuencia de estados (T,)."""
    T, S = log_emit.shape
    delta = np.full((T, S), -np.inf)
    psi = np.zeros((T, S), dtype=int)
    delta[0] = log_pi + log_emit[0]
    for t in range(1, T):
        # scores[i, j] = delta[t-1, i] + log_A[i, j]
        scores = delta[t - 1][:, None] + log_A
        psi[t] = np.argmax(scores, axis=0)
        delta[t] = scores[psi[t], np.arange(S)] + log_emit[t]
    path = np.zeros(T, dtype=int)
    path[-1] = int(np.argmax(delta[-1]))
    for t in range(T - 2, -1, -1):
        path[t] = psi[t + 1, path[t + 1]]
    return path


def _smooth_fold(proba: np.ndarray, te_groups: np.ndarray,
                 A: np.ndarray, pi: np.ndarray, prior: np.ndarray) -> np.ndarray:
    """Aplica Viterbi por noche (bloque de sujeto) a las posteriores del fold de test."""
    log_A = np.log(A + _EPS)
    log_pi = np.log(pi + _EPS)
    # El RF ya está balanceado (class_weight="balanced"): sus posteriores asumen
    # prior uniforme, así que la emisión es la posterior directa. NO dividir por
    # el prior real → eso sería doble corrección (infla Deep/REM, hunde Light).
    # La "pegajosidad" del sueño la aporta la matriz de transición A.
    log_emit_all = np.log(proba + _EPS)
    out = np.empty(len(proba), dtype=int)
    for s, e in _subject_blocks(te_groups):
        out[s:e] = _viterbi(log_emit_all[s:e], log_A, log_pi)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(HERE / "data"))
    ap.add_argument("--folds", type=int, default=10)
    ap.add_argument("--trees", type=int, default=300)
    ap.add_argument("--out", default=str(HERE / "outputs"))
    args = ap.parse_args()

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
    dist = {CLASS_NAMES[c]: int((y == c).sum()) for c in range(N_CLASSES)}
    print(f"  distribución de clases: {dist}")

    folds = min(args.folds, n_subj)
    gkf = GroupKFold(n_splits=folds)
    oof_raw = np.full(len(y), -1, dtype=int)     # argmax RF (igual que baseline)
    oof_hmm = np.full(len(y), -1, dtype=int)     # tras Viterbi

    for k, (tr, te) in enumerate(gkf.split(X, y, groups), 1):
        clf = RandomForestClassifier(
            n_estimators=args.trees, class_weight="balanced",
            min_samples_leaf=5, n_jobs=-1, random_state=42)
        clf.fit(X.iloc[tr], y[tr])
        proba = clf.predict_proba(X.iloc[te])    # (n_te, 4), columnas = clf.classes_
        # Reordena columnas a 0..3 por si alguna clase faltara en el fold.
        full = np.zeros((proba.shape[0], N_CLASSES))
        for j, c in enumerate(clf.classes_):
            full[:, int(c)] = proba[:, j]

        oof_raw[te] = full.argmax(axis=1)
        # Transiciones aprendidas SOLO del train fold (sin fuga).
        A, pi, prior = _learn_transitions(y[tr], groups[tr])
        oof_hmm[te] = _smooth_fold(full, groups[te], A, pi, prior)

        print(f"  fold {k}/{folds}: "
              f"κ_raw={cohen_kappa_score(y[te], oof_raw[te]):.3f}  "
              f"κ_hmm={cohen_kappa_score(y[te], oof_hmm[te]):.3f}")

    def _report(tag: str, pred: np.ndarray) -> dict:
        kappa = cohen_kappa_score(y, pred)
        acc = float((pred == y).mean())
        f1m = f1_score(y, pred, average="macro")
        cm = confusion_matrix(y, pred, labels=list(range(N_CLASSES)))
        print(f"\n=== {tag} (out-of-fold, por sujeto) ===")
        print(f"  κ de Cohen : {kappa:.3f}")
        print(f"  accuracy   : {acc:.3f}")
        print(f"  F1 macro   : {f1m:.3f}")
        print("\n  matriz de confusión (filas=real, cols=predicho):")
        print("        " + "".join(f"{c:>8}" for c in CLASS_NAMES))
        for i, row in enumerate(cm):
            print(f"  {CLASS_NAMES[i]:>6}" + "".join(f"{v:8d}" for v in row))
        print("\n" + classification_report(y, pred, target_names=CLASS_NAMES,
                                           digits=3, zero_division=0))
        return {"kappa": kappa, "accuracy": acc, "f1_macro": f1m,
                "confusion_matrix": cm.tolist()}

    m_raw = _report("RF crudo (argmax)", oof_raw)
    m_hmm = _report("RF + HMM/Viterbi", oof_hmm)
    print(f"\n>>> Δκ por suavizado temporal: {m_hmm['kappa'] - m_raw['kappa']:+.3f}")

    # Artefactos para Fase 4: RF final + matriz de transición global.
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    final = RandomForestClassifier(
        n_estimators=args.trees, class_weight="balanced",
        min_samples_leaf=5, n_jobs=-1, random_state=42)
    final.fit(X, y)
    A, pi, prior = _learn_transitions(y, groups)
    joblib.dump({"model": final, "feature_cols": feature_cols,
                 "class_names": CLASS_NAMES,
                 "transition": A, "initial": pi, "prior": prior},
                out_dir / "rf_hmm.joblib")

    metrics = {
        "raw": m_raw, "hmm": m_hmm,
        "delta_kappa": m_hmm["kappa"] - m_raw["kappa"],
        "n_epochs": int(len(X)), "n_subjects": int(n_subj),
        "class_distribution": dist,
        "transition_matrix": A.tolist(),
    }
    (out_dir / "metrics_sequence.json").write_text(json.dumps(metrics, indent=2))
    print(f"\nGuardado modelo y métricas en {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
