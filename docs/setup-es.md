# OpenWhoop — Guía de instalación en iPhone (español)

Guía paso a paso para instalar **OpenWhoop** en un **iPhone físico** y recolectar datos de un **WHOOP 4.0** sin suscripción oficial. El servidor Docker es **opcional** (fase 2).

> **Hardware soportado:** WHOOP 4.0 únicamente. Otras generaciones usan protocolos BLE distintos.

---

## Estado del repo (checklist)

Tras ejecutar el setup parcial, verifica que tengas esto:

| Elemento | Estado esperado | Comando de verificación |
|---|---|---|
| `Secrets.xcconfig` (gitignored) | Copiado desde el ejemplo, con placeholders | `ls ios/OpenWhoop/Config/Secrets.xcconfig` |
| `OpenWhoop.xcodeproj` (gitignored) | Generado por XcodeGen | `ls ios/OpenWhoop.xcodeproj` |
| `Info.plist` (gitignored) | Generado por XcodeGen | `ls ios/OpenWhoop/Info.plist` |
| XcodeGen | Instalado vía Homebrew | `xcodegen --version` |
| **Xcode completo** | **Requerido para compilar en iPhone** | `xcodebuild -version` |
| `scripts/setup-ios.sh` | Script de setup automatizado | `./scripts/setup-ios.sh` |

### Lo que falta para el primer build en iPhone

1. **Instalar Xcode** desde la App Store (no basta con Command Line Tools).
2. Aceptar la licencia y seleccionar Xcode como herramienta activa:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```
3. Abrir el proyecto en Xcode y configurar **Signing & Capabilities** con tu Apple ID.
4. Conectar el iPhone por USB (o Wi-Fi debugging) y ejecutar en dispositivo físico.

> **No uses el simulador iOS** para probar BLE: CoreBluetooth no funciona con el strap en simulador.

---

## Setup rápido (repetible)

Desde la raíz del repo:

```bash
./scripts/setup-ios.sh
```

El script:
- Instala XcodeGen si falta (`brew install xcodegen`)
- Crea `Secrets.xcconfig` desde el template si no existe
- Regenera `ios/OpenWhoop.xcodeproj` con `xcodegen generate`

---

## 1. Instalar Xcode

1. Abre la **App Store** → busca **Xcode** → Instalar (~12 GB).
2. Abre Xcode una vez para que instale componentes adicionales.
3. En terminal:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -version   # debe mostrar Xcode 15+ o 16+
   ```

---

## 2. Configurar firma (Apple ID gratuito)

Cuenta gratuita de desarrollador: la app expira a los **7 días** y hay que reinstalarla desde Xcode. No requiere pagar el programa de desarrollador ($99/año).

1. Abre el proyecto:
   ```bash
   open ios/OpenWhoop.xcodeproj
   ```
2. En Xcode: selecciona el target **OpenWhoop** → pestaña **Signing & Capabilities**.
3. Marca **Automatically manage signing**.
4. En **Team**, elige tu Apple ID personal (añádelo en Xcode → Settings → Accounts si no aparece).
5. Si el Bundle Identifier `com.openwhoop.OpenWhoop` está ocupado, cámbialo a algo único, por ejemplo `com.tunombre.openwhoop`.
6. Confirma que aparece la capability **Background Modes → Uses Bluetooth LE accessories** (ya configurada en `project.yml`).

### Capabilities ya incluidas

- `bluetooth-central` — recolección en background
- `NSBluetoothAlwaysUsageDescription` — permiso Bluetooth
- Restauración de estado BLE (`CBCentralManagerOptionRestoreIdentifierKey`)

---

## 3. Compilar e instalar en iPhone

### Requisitos del iPhone

- **iOS 16.0+** (deployment target del proyecto)
- Bluetooth activado
- Cable USB (recomendado la primera vez) o Wi-Fi debugging configurado

### Pasos en Xcode

1. Conecta el iPhone y desbloquéalo.
2. Si es la primera vez: en el iPhone, confía en el ordenador (**Confiar en este ordenador**).
3. En Xcode, selecciona tu iPhone como destino (no "Any iOS Device" ni simulador).
4. Pulsa **Run** (⌘R).
5. En el iPhone: **Ajustes → General → VPN y gestión de dispositivos** → confía en tu certificado de desarrollador.

### Build por línea de comandos (alternativa)

Cuando Xcode esté instalado y tengas tu Team ID:

```bash
cd ios
xcodebuild -project OpenWhoop.xcodeproj \
  -scheme OpenWhoop \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

Para instalar en un dispositivo conectado, es más sencillo usar Xcode GUI la primera vez (resuelve provisioning automáticamente).

---

## 4. Modo local sin servidor (confirmado)

Con los placeholders por defecto en `Secrets.xcconfig`:

```
WHOOP_BASE_URL = https://whoop.example.com
WHOOP_API_KEY = replace-me
WHOOP_DEVICE_ID = my-whoop
```

`AppConfig.uploaderConfig()` devuelve **`nil`** y la app **no intenta subir ni descargar** del servidor:

- No se crea `Uploader` ni `ServerSync` en `BLEManager.bootstrapStore()`
- La recolección BLE, decodificación y almacenamiento local **funcionan igual**
- Los datos se guardan en SQLite (GRDB) en el sandbox de la app

### Qué funciona sin servidor

| Funcionalidad | Sin servidor |
|---|---|
| Conexión BLE + bonding | ✅ |
| HR en vivo + batería (pestaña Device) | ✅ |
| Sync histórico del strap (type-47 offload) | ✅ |
| Persistencia de streams decodificados (HR, RR, eventos, batería…) | ✅ |
| Background BLE (`bluetooth-central`) | ✅ |
| Recovery, Strain, Sleep, HRV, RHR (pestañas Today/Sleep/Trends) | ❌ vacías |
| Gráficos de HR históricos en Trends | ❌ requieren servidor |
| Workouts detectados | ❌ requieren servidor |

Las métricas derivadas (recovery, strain, sueño, HRV agregado) las calcula el **servidor Python** (`server/ingest`). El iPhone solo las **cachea** tras un `ServerSync.pullDerived()`. Sin servidor, las pestañas Today/Sleep/Trends mostrarán el estado vacío — es comportamiento esperado, no un fallo de BLE.

La pestaña **Device** es tu consola principal en modo local: conexión, HR, batería, estado de sync del strap y contador `stored: N samples`.

---

## 5. Primera conexión BLE (pestaña Device)

1. Saca el WHOOP 4.0 del cargador (en el dock a veces no anuncia BLE).
2. Abre OpenWhoop → pestaña **Device**.
3. Concede permiso **Bluetooth** cuando iOS lo pida (elige **Permitir siempre** si aparece).
4. La app escanea automáticamente el servicio WHOOP (`61080001-…`).
5. Tras conectar, ejecuta el **bonding** (un write confirmado a la característica de comando).
6. Verifica los chips de estado:
   - **LINK** → Connected (verde)
   - **BOND** → Bonded (verde)
   - **BATT** → porcentaje de batería
7. En la sección Live deberías ver HR en tiempo real.
8. El contador de almacenamiento (`stored: X samples`) debe subir tras unos minutos de sync histórico.

### Si no conecta

- Reinicia Bluetooth en el iPhone.
- Asegúrate de que el strap no está emparejado con otra app (desvincula en Ajustes → Bluetooth si aparece).
- Pon el strap en la muñeca o muévelo — algunos sensores solo activan logging on-wrist.
- Si ves "WHOOP may need a reboot": ponlo en el cargador unos segundos para reiniciar el firmware.

### Bonding en iOS

A diferencia de Bluefy (navegador WebBLE), OpenWhoop usa **CoreBluetooth nativo** con `bluetooth-central` en background. El bonding se dispara con un write confirmado — no necesitas emparejar manualmente en Ajustes de iOS.

---

## 6. Qué esperar en cada pestaña (sin servidor)

### Device (principal en fase 1)

- Estado de conexión, bonding, batería
- HR en vivo, último sync, alertas de batería
- Controles de sync manual, haptics (experimental)
- Log de eventos BLE
- Resumen de almacenamiento local

### Today

- Recovery ring, Strain, Sleep, HRV, RHR → **vacíos** hasta configurar servidor
- Si el strap está conectado, verás chips de HR/batería en vivo en la parte inferior

### Sleep / Trends

- **Vacías** sin servidor (no hay `dailyMetric` ni `sleepSession` en caché local)
- Tras configurar servidor y dejar sincronizar, se llenan con datos calculados en el Mac/servidor

### Persistencia

Cierra la app completamente y vuelve a abrirla:
- El contador `stored: N samples` en Device debe mantenerse o crecer
- La base de datos GRDB vive en el sandbox de la app (`StorePaths.defaultDatabasePath()`)

---

## 7. Recolección en background

La app declara `UIBackgroundModes: bluetooth-central` y usa restauración de estado de `CBCentralManager`.

Comportamiento esperado:
- Con la app en segundo plano, iOS puede mantener la conexión BLE un tiempo limitado
- Al volver al primer plano, la app re-sincroniza si hace falta (timer periódico de backfill cada ~15 min mientras conectada+bonded)
- No esperes recolección 24/7 idéntica a la app oficial sin servidor — iOS gestiona agresivamente el background BLE, pero la re-sincronización al abrir la app compensa

Para maximizar recolección:
- Mantén Bluetooth activado
- Abre la app al menos una vez al día (re-firma cada 7 días con cuenta gratuita)
- Deja el strap fuera del cargador y en la muñeca

---

## 8. Fase 2 — Servidor Docker (opcional)

Solo cuando el build iOS funcione y quieras métricas derivadas + dashboard.

### En el Mac (hub)

**Opción A — script automatizado (recomendado):**

```bash
./scripts/setup-server.sh
```

Genera `server/.env` con claves aleatorias en el primer run (no sobrescribe si ya existe),
crea `~/whoop-data`, levanta los contenedores, espera el healthcheck e imprime la línea
`WHOOP_BASE_URL` con la IP LAN del Mac lista para pegar en `Secrets.xcconfig`.

**Opción B — manual:**

```bash
cd server
cp .env.example .env
# Edita .env: WHOOP_API_KEY (clave fuerte, p.ej. openssl rand -hex 24), WHOOP_DB_PASSWORD
export DATA_ROOT=/ruta/persistente/whoop-data   # ej. ~/whoop-data
docker compose up -d --build
```

> **Colima:** si usas Colima en lugar de Docker Desktop, arranca el daemon antes con
> `colima start` (si no, verás "Cannot connect to the Docker daemon").

Verifica: `curl -s http://localhost:8770/healthz` → `{"status":"ok"}`
Dashboard: `http://localhost:8770` (y `http://<ip-lan-del-mac>:8770` desde otros equipos en la LAN).

### Actualizar Secrets.xcconfig (en el iPhone build)

Edita el archivo gitignored `ios/OpenWhoop/Config/Secrets.xcconfig`:

```
WHOOP_BASE_URL = http:/$()/192.168.1.X:8770
WHOOP_API_KEY = tu-clave-del-env
WHOOP_DEVICE_ID = my-whoop
```

> Usa la **IP LAN** del Mac, no `localhost` (el iPhone no puede alcanzar localhost del Mac).
> El truco `http:/$()/` evita que xcconfig interprete `//` como comentario.

Regenera y recompila:

```bash
cd ios && xcodegen generate
# Rebuild en Xcode → Run en iPhone
```

### Qué cambia con servidor

- `Uploader` sube streams decodificados al servidor
- `ServerSync` descarga métricas derivadas → llenan Today/Sleep/Trends
- Dashboard en `http://<mac-ip>:8770`

---

## 9. Troubleshooting

| Problema | Solución |
|---|---|
| `xcodebuild: error: tool 'xcodebuild' requires Xcode` | Instala Xcode completo desde App Store |
| Signing failed / No profiles | Xcode → Signing → Automatically manage signing + Team |
| App expirada tras 7 días | Vuelve a Run desde Xcode (cuenta gratuita) |
| Bluetooth permission denied | Ajustes → OpenWhoop → Bluetooth → Activar |
| LINK disconnected constantemente | Strap lejos, batería baja, o reinicio necesario |
| `stored: 0 samples` tras minutos | Verifica BOND verde; espera sync histórico (puede tardar varios min) |
| Today vacío con servidor | Comprueba IP LAN, API key, que Docker esté up, pull-to-refresh en Today |
| `Cannot connect to the Docker daemon` | Arranca el daemon: `colima start` (Colima) o abre Docker Desktop |
| iPhone no alcanza el servidor | Mismo Wi-Fi; permite el puerto 8770 en el firewall del Mac (Ajustes → Red → Firewall); verifica `curl http://<ip-lan>:8770/healthz` desde otro equipo |
| La IP del Mac cambió | El router reasignó DHCP: actualiza `WHOOP_BASE_URL` en `Secrets.xcconfig`, `xcodegen generate`, rebuild. (Opcional: reserva IP fija en el router) |
| Recovery muestra "Pending" | Normal los primeros ~4 días: el cálculo necesita una **baseline** de varias noches de HRV/RHR antes de dar un %. Strain y sueño sí aparecen desde la primera noche |
| API key mismatch (401 en logs ingest) | La `WHOOP_API_KEY` de `Secrets.xcconfig` debe ser idéntica a la de `server/.env` |

---

## 10. Criterios de éxito

### Fase 1 (local, sin servidor)

- [ ] OpenWhoop instalada en iPhone físico
- [ ] Conecta a WHOOP 4.0 fuera del cargador
- [ ] HR en vivo + batería visibles en pestaña Device
- [ ] `stored: N samples` crece tras sync
- [ ] Datos persisten tras cerrar y reabrir la app
- [ ] (Opcional) Background: re-sincroniza al volver a la app

### Fase 2 (con servidor)

- [ ] Docker compose up en Mac
- [ ] `Secrets.xcconfig` con IP LAN + API key
- [ ] Today/Sleep/Trends muestran recovery, strain, sueño
- [ ] Dashboard accesible en `:8770`

---

## Referencias en el repo

| Archivo | Contenido |
|---|---|
| `ios/OpenWhoop/BLE/BLEManager.swift` | Motor BLE, bonding, background |
| `ios/OpenWhoop/Config/AppConfig.swift` | Config servidor opcional |
| `FINDINGS.md` | Protocolo BLE WHOOP 4.0 |
| `docs/specs/2026-05-23-openwhoop-ios-app-design.md` | Diseño de la app |
| `server/README.md` | Despliegue del servidor |
| `scripts/setup-ios.sh` | Setup automatizado iOS |

---

## Comparación con WHOOP oficial (trial)

Durante tus 2 meses de trial oficial, puedes comparar:
- **HR en vivo**: debería ser muy similar (misma fuente BLE)
- **Recovery/Strain/Sleep**: algoritmos distintos — OpenWhoop usa los del servidor open-source, no la nube WHOOP
- **SpO₂ / temperatura de piel**: no disponibles por BLE local (WHOOP los calcula en su nube)

No esperes paridad 1:1; el objetivo es **propiedad de tus datos** y recolección local continua.

---

## TestFlight + servidor remoto (varias personas)

Guía operativa: [testflight-remote-server.md](testflight-remote-server.md)
