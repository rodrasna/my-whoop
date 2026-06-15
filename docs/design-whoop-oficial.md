# Referencia visual — app oficial WHOOP (capturas usuario, jun 2026)

Documento de paridad UX para OpenWhoop. **No copiar marca/logos WHOOP** — solo layout, jerarquía y tokens.

## Paleta (aproximada)

| Token | Hex | Uso |
|---|---|---|
| Fondo app | `#000000` | Negro puro |
| Superficie card | `#1C1C1E` | Tarjetas |
| Texto primario | `#FFFFFF` | Valores grandes |
| Texto secundario | `#8A8F98` | Labels, fechas |
| Sueño (anillo) | `#5AA9E6` | Anillo calificación sueño |
| Esfuerzo (anillo) | `#0093E7` | Strain ring / barras |
| Recuperación verde | `#16EC06` | ≥67% |
| Recuperación amarillo | `#FFDE00` | 34–66% |
| Recuperación rojo | `#FF0026` | ≤33% |
| SWS / Profundo | `#E25FD0` | Etapa sueño |
| REM | `#9B6DFF` | Etapa sueño |
| Ligero | `#7FA6E8` | Etapa sueño |
| Despierto | `#6E727E` | Etapa sueño |
| Banner calibración | `#2D1B33` + magenta `#E25FD0` | Progreso noches |
| Barras semanales | `#0093E7` | Tendencias 7 días |

## Inicio (tab principal)

### Cabecera fija
- **3 anillos pequeños** en fila: Sueño · Recuperación · Esfuerzo
- Cada anillo: arco de color + valor centro + label debajo (MAYÚSCULAS)
- Tocar anillo → pantalla detalle con **anillo grande** hero

### Panel de control (debajo)
Filas en **una sola tarjeta** con divisores:
- Icono gris + label MAYÚSCULAS izquierda
- Valor grande derecha + unidad
- Línea baseline pequeña (ej. comparación 30 días: `459` bajo `692`)

Métricas típicas: FC en reposo, VFC, calorías, pasos, zonas FC, actividad fuerza.

### Tendencias semanales
Tarjetas con:
- Título MAYÚSCULAS + chevron `>`
- Gráfico **barras 7 días** (dom–sáb + día del mes)
- **Columna vertical gris** resalta el día actual
- Valor numérico encima de la barra del día actual

### Monitor de estrés (card grande)
- Mini gráfico línea 0–3
- Banda azul + luna = periodo sueño
- Pie: "Usa WHOOP X noches para calibrar" + barra segmentada magenta

## Sueño — detalle (tap anillo Sueño)

### Hero
- Anillo **grande** azul (~82% calificación)
- Centro: `WHOOP` pequeño + `82%` enorme + `CALIFICACIÓN DEL SUEÑO`
- Carrusel 3 páginas (puntos abajo)

### Sub-métricas (tarjeta con punta hacia arriba)
Filas con barra **3 segmentos** (deficiente/naranja · suficiente/gris · óptimo/verde):
- Horas vs. lo necesario
- Regularidad del sueño
- Eficiencia del sueño
- Estrés del sueño alto

### Etapas (scroll "El sueño de anoche")
- Título + "Hoy vs. 30 días anteriores"
- Filas: círculo color + nombre + **pill %** + duración `H:MM`
- Barra: fondo **rayado diagonal** + relleno color + caja discontinua "rango típico"
- Etapas: Despierto, Ligero, Sueño Profundo (SWS), REM
- Pie: Sueño reparador (SWS+REM)

## Recuperación — detalle

- Anillo grande gris/verde + `20%` + `RECUPERACIÓN`
- Banner morado calibración (3 noches más)
- Lista métricas con icono + valor hoy + baseline 30d

## Esfuerzo — detalle

- Anillo azul + `2,8` + `ESFUERZO`
- Filas: zonas FC 1-3, 4-5, pasos, calorías, tiempo fuerza

## Navegación inferior (oficial)

`Inicio` · `Salud` · `Comunidad` · `Más` + botón circular W

OpenWhoop actual: `Hoy` · `Sueño` · `Tendencias` · `Actividad` · `Dispositivo` — OK para v1.

## Gap OpenWhoop vs oficial (prioridad)

| Pantalla | Tenemos | Falta |
|---|---|---|
| Inicio 3 anillos | ✅ TriRingHeader | Anillos más grandes; tap → detalle hero |
| Panel filas | ✅ DashboardRow sueltas | Agrupar en 1 card + baseline 30d |
| Tendencias 7d | ⚠️ Trends tab | Barras semanales en Inicio |
| Sueño hero ring | ❌ | Anillo 82% calificación |
| Etapas rayadas | ⚠️ barras simples | Fondo rayado + rango típico |
| Monitor estrés | ❌ | Fase posterior |
| Salud tab | ❌ | Fase posterior |
| Calibración banners | ⚠️ parcial | Banner morado segmentado |

## Datos (recordatorio)

La UI oficial muestra datos **de su nube**. OpenWhoop necesita sync matutino → servidor Mac → `pullDerived()`. Sin datos, los anillos muestran `—` aunque la UI sea idéntica.
