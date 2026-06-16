# Task 10 — Servidor online (Hetzner CX22 + Cloudflare Tunnel)

> **Estado:** Pendiente · **Última actualización:** 2026-06-16  
> **Objetivo:** Dejar de depender del Mac/Colima local para `whoop-ingest` + TimescaleDB; stack Docker 24/7 accesible desde el iPhone vía HTTPS.

---

## 1. Resumen ejecutivo

| Concepto | Valor |
|----------|-------|
| **VPS recomendado** | Hetzner **CX22**: 2 vCPU AMD, 4 GB RAM, 40 GB SSD |
| **Coste** | ~**€4,49/mes** + IVA (precio orientativo Hetzner 2026) |
| **HTTPS** | **Cloudflare Tunnel** (plan Free, €0) |
| **Dominio** | Opcional ~€10/año (o subdominio de uno existente) |
| **Stack** | Igual que local: `server/docker-compose.yml` |

### ¿Hetzner vs Raspberry en casa?

| | **Hetzner CX22** | **Pi 5 + NVMe en casa** |
|--|------------------|-------------------------|
| Coste mensual | ~€4,5 | ~€1 luz |
| iPhone fuera de casa | Siempre alcanzable | Solo si tunnel + fibra OK |
| Pi-hole / adblock | No (otra máquina) | Misma Pi posible |
| Mantenimiento | Bajo | Medio (updates, discos) |
| **Recomendación homelab** | **Whoop + DB aquí** | Pi-hole, DNS, LAN |

Si ya tienes servicios en casa (filtrado ads, etc.), **no mezcles** el stack Whoop con Pi-hole en la misma Pi sin NVMe y sin asumir cortes de luz: separar roles.

---

## 2. Qué se despliega

```text
Internet
   │
   ▼
Cloudflare Edge (TLS)
   │
   ▼ cloudflared (túnel, en VPS)
   │
   ▼ localhost:8770
docker compose
   ├── whoop-ingest (FastAPI)
   └── whoop-db (TimescaleDB, solo red interna)
```

Volúmenes en host:

```text
/srv/whoop-data/
  whoop/db/     → Postgres data
  whoop/raw/    → archivos .zst
```

---

## 3. Requisitos previos

- [ ] Cuenta Hetzner Cloud
- [ ] Cuenta Cloudflare (dominio añadido o comprado)
- [ ] Copia de `~/whoop-data` o `DATA_ROOT` actual del Mac
- [ ] `.env` del servidor con secretos (no commitear)
- [ ] `Secrets.xcconfig` en iOS con URL pública

---

## 4. Provisión VPS (paso a paso)

### 4.1 Crear servidor

1. Hetzner Cloud → Add Server.
2. **Location:** Helsinki o Nuremberg (latencia EU).
3. **Image:** Ubuntu 24.04 LTS.
4. **Type:** CX22 (4 GB).
5. **SSH key:** la tuya.
6. **Firewall Hetzner (opcional):** solo 22/tcp desde tu IP; **no** abrir 5432 ni 8770 al mundo (tunnel basta).

### 4.2 Bootstrap

```bash
ssh root@<VPS_IP>

apt update && apt upgrade -y
apt install -y docker.io docker-compose-plugin git

mkdir -p /srv/whoop-data/whoop/{db,raw}
adduser whoop --disabled-password
usermod -aG docker whoop
```

### 4.3 Código y env

```bash
su - whoop
git clone <tu-repo> ~/my-whoop
cd ~/my-whoop/server
cp .env.example .env
# Editar:
#   WHOOP_API_KEY=...
#   WHOOP_DB_PASSWORD=...
#   DATA_ROOT=/srv/whoop-data
#   SUGARWOD_EMAIL=...
#   SUGARWOD_PASSWORD=...
#   SUGARWOD_TRACK=PRVN Español

export DATA_ROOT=/srv/whoop-data
docker compose up -d --build
curl -sS localhost:8770/healthz   # {"status":"ok"}
```

---

## 5. Migración de datos desde Mac

```bash
# En el Mac (parar compose local para consistencia opcional)
rsync -avz --progress ~/whoop-data/whoop/ whoop@<VPS_IP>:/srv/whoop-data/whoop/

# En VPS
cd ~/my-whoop/server && docker compose restart whoop-db whoop-ingest
```

Verificar:

```bash
curl -sS -H "Authorization: Bearer $WHOOP_API_KEY" \
  "http://localhost:8770/v1/devices"
```

---

## 6. Cloudflare Tunnel (gratis)

### 6.1 Instalar cloudflared en VPS

```bash
# Ver docs Cloudflare: package cloudflared para Ubuntu
cloudflared tunnel login
cloudflared tunnel create whoop
```

### 6.2 Config `~/.cloudflared/config.yml`

```yaml
tunnel: <TUNNEL_UUID>
credentials-file: /home/whoop/.cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: whoop.tudominio.com
    service: http://localhost:8770
  - service: http_status:404
```

### 6.3 DNS

```bash
cloudflared tunnel route dns whoop whoop.tudominio.com
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

### 6.4 Comprobar

```bash
curl -sS https://whoop.tudominio.com/healthz
```

**Coste tunnel:** €0 en plan Free. No necesitas abrir puertos en el router de casa.

---

## 7. iOS

`ios/OpenWhoop/Config/Secrets.xcconfig` (gitignored):

```xcconfig
WHOOP_BASE_URL = https:/$()/whoop.tudominio.com
WHOOP_API_KEY = <misma que WHOOP_API_KEY del servidor>
```

```bash
cd ios && xcodegen generate
# Rebuild e instalar en iPhone
```

---

## 8. Backups

### 8.1 Postgres diario

```bash
# /etc/cron.d/whoop-backup
0 4 * * * whoop docker exec whoop-db pg_dump -U whoop whoop | gzip > /srv/whoop-data/backups/whoop-$(date +\%F).sql.gz
find /srv/whoop-data/backups -mtime +14 -delete
```

### 8.2 Raw archives

- Opcional: `rclone` a S3/Wasabi semanal (centavos por GB).
- Para 1 usuario, 40 GB SSD basta años.

---

## 9. Operaciones

| Tarea | Comando |
|-------|---------|
| Actualizar imagen | `cd ~/my-whoop/server && git pull && docker compose up -d --build` |
| Logs ingest | `docker logs -f whoop-ingest` |
| Logs DB | `docker logs whoop-db` |
| Espacio disco | `df -h /srv/whoop-data` |
| Reinicio seguro | `docker compose restart` |

### Watchtower (opcional)

Auto-pull imágenes base — solo si aceptas reinicios automáticos.

---

## 10. Seguridad

| Item | Acción |
|------|--------|
| Postgres | Solo red Docker `whoop-db`, nunca público |
| API writes | Bearer `WHOOP_API_KEY` (ya implementado) |
| Read API | Hoy sin auth en LAN; **en producción** mantener tunnel + no publicar dashboard sin auth o añadir Basic Auth en cloudflared |
| Secretos | `.env` chmod 600; no en git |
| SSH | Solo clave, sin password root |

---

## 11. Coste total estimado (año 1)

| Item | EUR/año |
|------|---------|
| CX22 | ~€54 |
| Dominio | ~€10 |
| Cloudflare | €0 |
| Electricidad Mac apagado | ahorro |
| **Total** | **~€65/año** |

Comparación EC2 t4g.medium equivalente: ~€350+/año.

---

## 12. Criterios de aceptación

1. iPhone sincroniza HR/RR con el VPS (no Mac encendido).
2. `https://whoop.tudominio.com/healthz` OK desde 4G.
3. PRVN sync SugarWOD funciona con credenciales en `.env` del VPS.
4. Tras migración, histórico de workouts/sueño visible en app.
5. Backup `pg_dump` restaurable en entorno de prueba.

---

## 13. Relación con Task 08 y 09

| Tarea | En VPS |
|-------|--------|
| 08 Stress | `compute_stress` corre en ingest; necesita VPS o Mac 24/7 |
| 09 Coach + LLM | API en mismo host; LLM local Ollama opcional en CX22 (4 GB justos — mejor API externa) |

**Orden sugerido:** 10 (infra) puede hacerse antes o en paralelo con 08; sin servidor estable, 08 solo avanza en local.

---

## 14. Checklist de despliegue (copiar/pegar)

- [ ] VPS CX22 creado
- [ ] Docker + compose up
- [ ] rsync DATA_ROOT
- [ ] healthz local OK
- [ ] cloudflared + DNS
- [ ] healthz HTTPS OK
- [ ] Secrets.xcconfig actualizado
- [ ] iPhone sync verificado
- [ ] cron backup
- [ ] Apagar stack local Mac (opcional)

---

## Changelog

| Fecha | Nota |
|-------|------|
| 2026-06-16 | Documento inicial — Hetzner + Cloudflare + homelab split |
