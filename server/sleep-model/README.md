# Modelo de etapas de sueño — Fase 1 (baseline)

Pipeline E2E para entrenar un clasificador de etapas de sueño (4 clases:
Wake / Light / Deep / REM) contra polisomnografía, usando el dataset **Walch**
(Apple Watch + PSG, 31 sujetos). Es la fase 1 del plan en
[`../../docs/plan-modelo-sueno.md`](../../docs/plan-modelo-sueno.md).

## Por qué Walch primero

Es lo más parecido a nuestro hardware (HR de muñeca + acelerómetro) y de descarga
directa. **Limitación clave:** Walch da HR en bpm (PPG, muestreo irregular), NO la
serie IBI latido-a-latido → los features cardíacos aquí son derivados de HR, no
RMSSD/SDNN reales. La VFC rica desde IBI/ECG llega en la fase 2 con MESA. En
nuestra pulsera sí tenemos IBI completo, del que se puede derivar HR para aplicar
este mismo modelo (domain adaptation).

## Uso

```bash
# 1) Descargar el dataset (~577 MB, open-access, en el HOST: necesita red)
python3 download_walch.py

# 2) Entrenar el baseline reutilizando la imagen del servidor (sin instalar nada)
chmod +x run.sh
./run.sh train_baseline.py --folds 10
```

Salida en `outputs/`: `rf_baseline.joblib` (modelo + columnas) y `metrics.json`
(κ, accuracy, F1 macro, matriz de confusión, top features).

## Ficheros

| Fichero | Qué hace |
|---|---|
| `download_walch.py` | Descarga y extrae `motion/ heart_rate/ labels/` en `data/` |
| `sleep_dataset.py` | Features por epoch de 30 s (HR, actigrafía, temporales, contexto) + carga del dataset |
| `train_baseline.py` | RandomForest con **GroupKFold por sujeto** (sin fuga) + métricas honestas |
| `run.sh` | Lanza un script dentro de `server-whoop-ingest` (one-off, `--rm`) |

## Features por epoch (30 s)

- **HR (de bpm):** media, std, mín, máx, rango, |Δbpm| medio (proxy de variabilidad),
  HR relativo a la mediana de la noche.
- **Actigrafía (del acelerómetro):** std/media/máx de la aceleración dinámica
  (|·|−1 g), flag de inmovilidad.
- **Temporales:** tiempo desde el inicio y posición normalizada en la noche
  (prior de arquitectura del sueño).
- **Contexto:** medias móviles centradas (3/5/11 epochs) y deltas.

## Expectativa honesta

4 clases con HR+accel (sin IBI real) ≈ **κ 0,45–0,55**. N1 es casi irrecuperable
sin EEG; REM y Deep son los que más aporta el salto vs. el heurístico actual.
Se reporta κ y matriz de confusión, no solo accuracy. No es grado clínico.

## Siguientes fases

2. Escalar con **MESA** (ECG→IBI) → features de VFC reales (RMSSD/SDNN/LF/HF).
3. Modelo secuencial (CNN-LSTM/TCN) para continuidad temporal.
4. Integración servidor → escribir el hipnograma en `sleepSession.stagesJSON`.
