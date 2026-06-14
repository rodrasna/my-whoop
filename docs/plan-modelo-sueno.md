# Plan — modelo propio de etapas de sueño

> Objetivo: sustituir el hipnograma heurístico actual (que detecta mal el sueño
> profundo) por un modelo entrenado contra polisomnografía (PSG) de laboratorio,
> usando las señales que ya capturamos de la WHOOP 4.0: **HR (1 Hz), serie IBI/RR
> completa, acelerómetro (gravity)**. Ver research general en
> [metricas-research.md](metricas-research.md).

## Por qué es viable

Ya persistimos la pieza clave: la **serie latido-a-latido (`rrInterval`)**, no solo
el bpm. El salto de calidad de los modelos publicados (κ=0,44 → 0,68) viene
precisamente de calcular **features de VFC por epoch de 30 s** a partir del IBI, no
del HR promediado. El sueño profundo (N3) es recuperable a ~65–70% de sensibilidad
desde la autonomía cardíaca (HR bajo, VFC alta, LF/HF bajo) — justo lo que el
heurístico no capta.

**Expectativa realista:** 4 clases (Wake/Light/Deep/REM) κ≈0,50–0,60, ~72–76% de
acierto vs PSG. No es clínico, pero es un salto grande frente al heurístico. N1 es
casi irrecuperable sin EEG; REM y N3 sí son aprendibles.

## Datasets (PSG etiquetada)

| Dataset | Sujetos | Señales | Acceso | Uso |
|---|---|---|---|---|
| **Walch et al.** (PhysioNet `sleep-accel`) | 31 | Apple Watch: accel muñeca + HR PPG | Libre, inmediato | Arranque + domain adaptation (es lo más parecido a nuestro hardware) |
| **MESA Sleep** (NSRR) | ~2.237 | PSG + actigrafía muñeca + ECG + SpO₂ | Registro NSRR (~1 día) | Entrenamiento principal (volumen + ECG→HRV) |
| **SHHS** (NSRR) | 3.295 | PSG domiciliaria, ECG | Registro NSRR | Aumentar datos de VFC (sin accel muñeca) |

Empezar por **Walch** (descarga directa) para montar el pipeline end-to-end, luego
escalar con **MESA**.

## Features por epoch de 30 s

Alineados a la rejilla de etapas PSG (30 s). Por epoch:

- **Cardíacas (del IBI):** RMSSD, SDNN, pNN50, LF, HF, LF/HF, HR medio, HR mín.
  Ventanas solapadas (p. ej. ±2 min) para contexto.
- **Movimiento (del acelerómetro):** actividad (varianza/ZCR de la magnitud),
  proporción de inmovilidad, "tiempo desde último movimiento".
- **Temporales:** tiempo transcurrido desde el inicio del sueño (prior de
  arquitectura: N3 al principio, REM hacia el final).
- **Contexto secuencial:** medias móviles y deltas de las anteriores.

## Modelo

1. **Baseline:** Random Forest / XGBoost por epoch (como Walch 2019,
   `ojwalch/sleep_classifiers`). Rápido, interpretable, κ≈0,45–0,55.
2. **Mejora secuencial:** CNN-LSTM o TCN sobre la secuencia de epochs para imponer
   continuidad temporal (las etapas no saltan aleatoriamente). κ≈0,55–0,60.
3. **Techo (si decodificamos la onda PPG cruda, bytes 20–91):** **SleepPPG-Net**
   (`mad-lab-fau/SleepPPG-Net`), κ=0,68–0,75. Requiere PPG crudo que hoy no
   decodificamos — proyecto aparte.

## Pipeline de entrenamiento (offline, Python)

1. Descargar Walch (+ MESA). Parsear PSG annotations → etiquetas por epoch de 30 s.
2. Extraer IBI + accel de cada sujeto; calcular features por epoch (NeuroKit2 /
   scipy para VFC).
3. Split por sujeto (no por epoch) para evitar fuga. Validación cruzada por sujeto.
4. Entrenar RF baseline; medir κ de Cohen y matriz de confusión 4 clases.
5. Iterar a modelo secuencial. Exportar a **Core ML** (o reglas/árbol portables) o
   servir desde el servidor.

## Integración en la app

Dos opciones (decidir según dónde viva el cómputo):

- **Servidor (recomendado):** job que, tras la ingesta nocturna, calcula el
  hipnograma desde el IBI+accel almacenados y lo escribe en `sleepSession.stagesJSON`
  (mismo formato que consume hoy `HypnogramView`). Cero cambios en iOS.
- **On-device:** modelo Core ML; más complejo, sin dependencia de servidor.

El formato de salida debe ser el `stagesJSON` actual (segmentos `{start, end,
stage}`) para reutilizar `HypnogramView` y el desglose de etapas tal cual.

## Validación honesta

- Reportar κ y matriz de confusión, no solo "accuracy".
- Mantener el aviso de que es aproximación, no grado clínico.
- Comparar contra el heurístico actual en las noches ya registradas para confirmar
  la mejora real en sueño profundo.

## Fases sugeridas

1. Pipeline E2E con Walch + RF baseline (medir κ).
2. Escalar con MESA + features de VFC más ricas.
3. Modelo secuencial (CNN-LSTM/TCN).
4. Integración servidor → `stagesJSON`.
5. (Opcional, grande) decodificar PPG crudo → SleepPPG-Net.
