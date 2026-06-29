# TestFlight + servidor remoto + varias personas

Guía operativa para distribuir OpenWhoop vía TestFlight con un servidor compartido (sin Docker en el Mac).

## Decisión de hosting

| Opción | Cuándo | Coste |
|--------|--------|-------|
| **Homelab + Cloudflare Tunnel** (p. ej. `jpserver`) | Ya tienes máquina 24/7 en casa | ~€0 |
| **Hetzner CX22** | Independencia del Mac/casa, backups en VPS | ~€4,5/mes |

En ambos casos: mismo [`server/docker-compose.yml`](../server/docker-compose.yml) en el host remoto. El iPhone solo ve `https://whoop.tudominio.com`.

Runbook detallado: [task-10-hetzner-hosting.md](plans/task-10-hetzner-hosting.md)

## 1. Desplegar servidor remoto

```bash
# En el VPS (Ubuntu + Docker)
git clone <repo> ~/my-whoop
cd ~/my-whoop/server
cp .env.example .env   # editar WHOOP_API_KEY, WHOOP_DB_PASSWORD, SUGARWOD_*, DATA_ROOT
export DATA_ROOT=/srv/whoop-data
mkdir -p /srv/whoop-data/whoop/{db,raw}
docker compose up -d --build
curl -sS localhost:8770/healthz
```

Cloudflare Tunnel → `https://whoop.tudominio.com` → `localhost:8770` (no abrir 8770 al mundo).

Actualizar código en el VPS:

```bash
cd ~/my-whoop && ./scripts/deploy-remote.sh
```

## 2. Migrar tu histórico (opcional)

```bash
# Desde el Mac
rsync -avz --progress ~/whoop-data/whoop/ user@<host>:/srv/whoop-data/whoop/
# En el VPS
cd ~/my-whoop/server && docker compose restart whoop-db whoop-ingest
```

La segunda persona **no** migra datos: elige un identificador nuevo en el onboarding de la app.

## 3. Verificar desde el Mac

`ios/OpenWhoop/Config/Secrets.xcconfig`:

```xcconfig
WHOOP_BASE_URL = https:/$()/whoop.tudominio.com
WHOOP_API_KEY = <misma clave que server/.env>
WHOOP_DEVICE_ID = my-whoop
```

```bash
./scripts/verify-server.sh
./scripts/verify-server.sh --sync-prvn
```

## 4. App iOS — multi-usuario

Cada instalación:

1. Onboarding → **identificador único** (minúsculas, números, guiones).
2. URL y clave API vienen del build TestFlight si están en `Secrets.xcconfig`.
3. Ajustes → Servidor para revisar o probar conexión.

**No compartas el mismo identificador** entre personas.

## 5. TestFlight

### Requisitos

- Cuenta Apple Developer de pago ($99/año).
- App Store Connect → app con tu bundle id (p. ej. `com.tuempresa.openwhoop`).

### Archive

```bash
cd ios && xcodegen generate
```

En Xcode: **Product → Archive** (Release) → **Distribute App** → App Store Connect.

Incrementa `CURRENT_PROJECT_VERSION` en [`ios/project.yml`](../ios/project.yml) en cada subida.

### Testers

| Tipo | Quién | Notas |
|------|-------|-------|
| Internal | Cuentas en tu equipo Developer | Sin beta review |
| External | Cualquier email | Beta App Review + URL política de privacidad |

### Instrucciones para la otra persona

1. Instalar **TestFlight** y aceptar la invitación.
2. Abrir OpenWhoop → elegir **identificador único** (no el tuyo).
3. Pestaña **Device** → emparejar WHOOP 4.0.
4. Esperar sync; métricas en Hoy/Sueño/Actividad.

### Privacidad (testers externos)

Publica una página breve: datos de salud en tu servidor, BLE, micrófono del check-in matutino, sin venta a terceros.

## 6. Seguridad

- Una API key compartida en el IPA es extraíble; válido para círculo de confianza.
- Aislamiento real entre usuarios = **device_id distinto** por instalación.
