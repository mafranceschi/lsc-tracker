# LSC Tracker 🚀

Analizador de logs de servicio para @ElBajoRoleplay.

## Estructura

```
lsc-tracker/
├── .env                  ← tu configuración (crearlo desde .env.example)
├── .env.example          ← plantilla
├── docker-compose.yml
├── frontend/
│   └── index.html
└── backend/
    ├── Dockerfile
    ├── package.json
    └── server.js
```

## Instalación rápida

```bash
# 1. Copiar el .env
cp .env.example .env

# 2. Editar según necesidad
#    ENABLE_DB=false  → solo visualización, sin guardar nada
#    ENABLE_DB=true   → guarda cada análisis, purga > 30 días

# 3. Levantar
docker compose up -d --build

# 4. Abrir en el navegador
# http://localhost:3000
```

## Variables de entorno (.env)

| Variable         | Valores        | Default | Descripción                              |
|------------------|----------------|---------|------------------------------------------|
| `ENABLE_DB`      | `true`/`false` | `false` | Activar persistencia con SQLite          |
| `PORT`           | número         | `3000`  | Puerto del servidor                      |
| `RETENTION_DAYS` | número         | `30`    | Días de retención de registros en la DB  |

## Comandos útiles

```bash
docker compose up -d          # levantar en background
docker compose down           # detener
docker compose logs -f        # ver logs en tiempo real
docker compose up -d --build  # reconstruir tras cambios
```

## Notas

- La base de datos SQLite se guarda en un **volumen Docker** (`lsc-data`),
  por lo que persiste aunque elimines y recrees el contenedor.
- La purga de registros antiguos se ejecuta **automáticamente** en cada
  análisis y consulta al historial.
- Si `ENABLE_DB=false`, la pestaña "Historial" está deshabilitada y
  nada se escribe en disco.
