# Replicar las métricas de WHOOP desde el dato crudo — research

> Síntesis de investigación (2026-06-14) sobre cómo derivar SpO₂, frecuencia
> respiratoria, etapas de sueño y VFC a partir de las señales crudas que la
> WHOOP 4.0 emite por BLE (PPG rojo/IR, acelerómetro, termistor de piel,
> intervalos latido-a-latido). Objetivo: saber qué es replicable con literatura
> abierta y datasets públicos, y con qué esfuerzo.

## TL;DR — la pieza que lo desbloquea todo

El sensor capta lo mismo para nosotros que para WHOOP. La diferencia es el
**procesado** (señal + calibración + modelos ML + bases personales), y casi todo
está publicado. **La pieza clave es la serie latido-a-latido (intervalos RR /
IBI)**, no el bpm promediado: de ella salen VFC, frecuencia respiratoria y buena
parte de las etapas de sueño.

El proyecto comunitario **`whoof`** ya documentó el protocolo BLE de la WHOOP y
sitúa HR, intervalo RR, SpO₂ y temp. piel en los bytes 0–19 del stream de 96
bytes. Los bytes 20–91 (probablemente la **forma de onda PPG cruda** + giroscopio)
siguen **sin decodificar** por la comunidad — esa es la única frontera real.

## Ranking de viabilidad

| Métrica | Dificultad | ¿Calibración? | Resultado realista |
|---|---|---|---|
| Frecuencia respiratoria | Baja | No | MAE ~1,5–2,5 rpm en sueño |
| VFC / FC reposo "bien hechas" | Baja-media | No | Igual que WHOOP (metodología publicada) |
| Etapas de sueño (modelo propio) | Media-alta | Necesita datasets etiquetados | 4 clases κ≈0,50–0,60 |
| SpO₂ absoluto | Alta | Sí (oxímetro de referencia) | Sin calibrar: solo tendencia/desaturaciones |

---

## 1. Frecuencia respiratoria (lo más fácil, sin calibración)

**Método.** Tres señales del PPG llevan info respiratoria: RIIV (variación de
intensidad/baseline), RIAV (variación de amplitud), RIFV (variación de frecuencia
= arritmia sinusal respiratoria, RSA, sobre la serie IBI). La **fusión** de las
tres gana claramente. Camino estándar: ventana deslizante de 32–64 s, paso-banda
0,1–0,5 Hz, pico del espectro (Welch PSD). La RSA sobre IBI sola ya es un buen
baseline y es lo que usan los wearables de consumo.

**Toolboxes / papers.**
- **RRest** (peterhcharlton/RRest) — 314 algoritmos benchmarkeados (MATLAB).
- **Charlton et al. 2018**, *Front. Physiology*, "Extracting Instantaneous
  Respiratory Rate from Multiple PPG Respiratory-Induced Variations" (open
  access) — blueprint de implementación (fusión condicionada por picos: bias
  0,28 rpm, LoA −3,6/+4,2 en dedo).
- **Charlton et al. 2016**, *Physiol. Meas.* — evaluación de 314 algoritmos.
- **NeuroKit2** (`pip install neurokit2`) — `ecg_rsp()` (métodos charlton2016,
  sarkar2015…); RSA vía `hrv_frequency()`. **HeartPy** para picos PPG → IBI.
- **Karlen Smart Fusion 2013** (*IEEE TBME*) — baseline reimplementable (RMSE ~3).
- **Duong et al. 2024** (arXiv:2401.05469) — CNN sobre PPG+IMU de smartwatch,
  MAE 1,85 rpm en vida libre (mejor resultado wrist, requiere entrenamiento).

**Precisión esperada en sueño:** MAE ~1,5–2,5 rpm para la media nocturna. Sin
calibración por usuario (solo se afinan parámetros con datasets de población).

## 2. VFC / FC en reposo (fácil-media, metodología publicada)

**Pipeline estándar** (NeuroKit2, Makowski et al. 2021, *Behavior Research
Methods*):
1. Paso-banda PPG 0,5–8 Hz.
2. Detección de picos → IBI (ms).
3. Corrección de artefactos (`nk.signal_fixpeaks()`, método Kubios): descartar
   IBI <300 ms o >2000 ms; marcar diferencias adyacentes >250 ms. (PPG necesita
   rechazo más agresivo que ECG por artefacto de movimiento.)
4. Calcular RMSSD, SDNN.

**Metodología que WHOOP publica.** VFC = **RMSSD ponderada hacia el sueño profundo
del final de la noche**; recuperación combina FC reposo + VFC + frec. respiratoria
+ rendimiento de sueño; FC reposo = mínimo durante el sueño. La literatura
respalda que la RMSSD en sueño profundo (SWS) es la más estable
(Leicht et al., PMC5767731). Otras toolboxes: **HeartPy**, **pyHRV**, Kubios.

**Validación WHOOP** (para contraste): Miller et al. 2022 (*Sensors*) ICC=0,99 vs
ECG; Bellenger et al. 2021 (*Sensors*).

## 3. Etapas de sueño — modelo propio (media-alta, máximo impacto)

Arregla el sueño profundo que el heurístico actual detecta mal.

**Datasets públicos (PSG etiquetada).**
- **Walch et al.** — PhysioNet `sleep-accel`, Apple Watch (accel muñeca + HR PPG),
  31 sujetos, etiquetas Wake/N1/N2/N3/REM. **Acceso libre e inmediato.**
- **MESA Sleep** — NSRR (sleepdata.org/datasets/mesa), ~2.237 sujetos, PSG + 7 días
  de actigrafía de muñeca + ECG + SpO₂. Registro NSRR (~1 día de aprobación).
- **SHHS** — NSRR, 3.295 sujetos, PSG domiciliaria (sin actigrafía de muñeca; útil
  para VFC del ECG).
- **Sleep-EDF** (PhysioNet) — libre, EEG/EOG/EMG (sin PPG; para benchmark).

**Modelos y techo de precisión (4 clases).**
- Walch et al. 2019 (*Sleep*): RF/XGBoost sobre accel+HR, κ=0,44, 68,6%.
- Sundararajan et al. 2021 (*Sci. Reports*): RF actigrafía, sleep/wake F1=74%.
- "It Is All in the Wrist" 2021 (PMC8253894): PPG+accel, κ=0,62.
- **SleepPPG-Net 2022** (IEEE JBHI, `mad-lab-fau/SleepPPG-Net`): CNN residual sobre
  PPG crudo, **κ=0,68–0,75** — estado del arte sin EEG.

**Repo base:** **`ojwalch/sleep_classifiers`** (scikit-learn, Apple Watch HR+accel,
4 clases y binario). Adaptador directo para nuestras señales.

**Realista:** con HR + **IBI** + movimiento, 4 clases κ≈0,50–0,60 (~72–76%). El
salto de κ=0,44 → 0,68 viene de usar **features de VFC del IBI por epoch de 30 s**
(RMSSD, LF/HF, pNN50), no solo el bpm. Sueño profundo (N3) recuperable del IBI a
~65–70% sensibilidad (autonomía: HR bajo, VFC alta, LF/HF bajo). N1 es casi
irrecuperable sin EEG.

## 4. SpO₂ (la más difícil; honestamente no sin mini-calibración)

**Algoritmo.** Ratio de ratios: `R = (AC_red/DC_red)/(AC_IR/DC_IR)`, luego curva
empírica (lineal `SpO₂ ≈ 110 − 25·R` o cuadrática). Física: Beer-Lambert,
absorción invertida de Hb/HbO₂ a 660 nm (rojo) vs 940 nm (IR).

**Por qué no transfiere una curva genérica al wrist:** tolerancia de longitud de
onda del LED (±10–15 nm desplaza R), geometría de **reflectancia** (no transmisión
como en el dedo), anatomía de la muñeca (sin arteria fiable bajo la correa,
pulsación venosa, baja perfusión), y **tono de piel** (melanina a 660 nm sesga el
SpO₂ al alza). Chan et al. 2021 (PMC8699050): calibración por sujeto obligatoria
incluso en esternón.

**Precisión wrist publicada:** Adam et al. 2025 (arXiv:2505.20846) RMSE 3,2% en
muñeca con 30% de rechazo de datos; 2,0% en brazo. Empatica EmbracePlus
(PMC10726006) ARMS 2,4% pero en clínica sin movimiento.

**Repos:** `prithusuresh/Reflectance-SPO2` (Vijayarangan et al. 2020, MAE 1,81%,
requiere datos etiquetados), `CoVital-Project/Spo2_evaluation`,
`Protocentral/AFE4490_Oximeter`, `mintisan/awesome-ppg`.

**Veredicto.** Sin referencia: solo **tendencia relativa / detección de
desaturaciones** (caídas de 3–5% en R, reales y detectables sin calibrar). Para %
absoluto ±2%: hace falta un oxímetro de dedo (~30€) y una regresión personal
R→SpO₂ + rechazo de movimiento. Reportar el índice de perfusión (AC/DC) como gate
de calidad es más honesto que un % falso.

---

## Proyectos de ingeniería inversa de WHOOP (referencia)

| Repo | Qué lograron |
|---|---|
| `madhursatija/whoof` | El más completo. 73 comandos + 100+ eventos en `docs/PROTOCOL.md`. GATT `61080000-8d6d-82b8-614a-1c8cb0f8dcc6`. Frame `[0xAA][cmd][len:LE16][payload][CRC32:LE]` (poly `0x04C11DB7`). Bytes 0–19 decodificados (HR, RR, SpO₂, temp). Bytes 20–91 desconocidos. |
| `bWanShiTong/reverse-engineering-whoop` | Un comando de lectura confirmado; atascado en el checksum. |
| `christianmeurer/whoop-reader` | Confirma UUIDs y bytes 1–6 (HR, RR, SpO₂, temp). |
| `NoopApp/noop` | Companion offline multiplataforma, SQLite local. |
| `johnmiddleton12/my-whoop` | App iOS nativa + servidor self-hosted. |

## Recomendación de orden

1. **Verificar que capturamos el IBI/RR** (gate de todo lo demás).
2. **Frecuencia respiratoria por instante** (resultado real, sin calibración).
3. **Modelo de etapas de sueño** (proyecto grande, máximo valor).
4. **SpO₂**: dejar en tendencia relativa hasta tener oxímetro de referencia.

## Fuentes

- Adam et al. 2025, arXiv:2505.20846 — SpO₂ reflectancia wrist.
- Vijayarangan et al. 2020, PubMed 33018006 — SpO₂ data-driven.
- Chan et al. 2021, PMC8699050 — SpO₂ esternón, calibración por sujeto.
- Charlton et al. 2016/2018 — respiración desde PPG (RRest, Frontiers).
- Karlen et al. 2013 — Smart Fusion.
- Duong et al. 2024, arXiv:2401.05469 — CNN respiración wrist.
- Walch et al. 2019, *Sleep* — staging Apple Watch (`ojwalch/sleep_classifiers`).
- Sundararajan et al. 2021, *Sci. Reports* — staging actigrafía.
- "It Is All in the Wrist" 2021, PMC8253894.
- SleepPPG-Net 2022, IEEE JBHI (`mad-lab-fau/SleepPPG-Net`).
- Miller et al. 2022 / Bellenger et al. 2021, *Sensors* — validación WHOOP.
- Makowski et al. 2021 — NeuroKit2.
- Leicht et al., PMC5767731 — RMSSD en SWS.
- Datasets: PhysioNet sleep-accel, NSRR MESA/SHHS, Sleep-EDF.
