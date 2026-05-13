require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const path    = require('path');
const fs      = require('fs');

const app       = express();
const PORT      = process.env.PORT || 3000;
const ENABLE_DB = process.env.ENABLE_DB === 'true';
const API_KEY   = process.env.API_KEY   || '';

// Validar RETENTION_DAYS — si es inválido, usar 30 y avisar
let RETENTION_DAYS = parseInt(process.env.RETENTION_DAYS || '30', 10);
if (!Number.isFinite(RETENTION_DAYS) || RETENTION_DAYS < 1) {
  console.warn(`[CONFIG] RETENTION_DAYS inválido ("${process.env.RETENTION_DAYS}"), usando 30.`);
  RETENTION_DAYS = 30;
}

// Validar GOAL_HOURS — si es inválido, usar 12 y avisar
let GOAL_HOURS = parseFloat(process.env.GOAL_HOURS || '12');
if (!Number.isFinite(GOAL_HOURS) || GOAL_HOURS <= 0) {
  console.warn(`[CONFIG] GOAL_HOURS inválido ("${process.env.GOAL_HOURS}"), usando 12.`);
  GOAL_HOURS = 12;
}

let MAX_LOG_MB = parseFloat(process.env.MAX_LOG_MB || '10');
if (!Number.isFinite(MAX_LOG_MB) || MAX_LOG_MB <= 0) {
  console.warn(`[CONFIG] MAX_LOG_MB inválido ("${process.env.MAX_LOG_MB}"), usando 10.`);
  MAX_LOG_MB = 10;
}
const RAW_TEXT_MAX_BYTES = MAX_LOG_MB * 1024 * 1024;

app.use(express.json({ limit: `${Math.ceil(MAX_LOG_MB * 2)}mb` }));
app.use(express.static(path.join(__dirname, '../frontend')));

// ══════════════════════════════════════════════════════════════
//  AUTH MIDDLEWARE — solo activo si API_KEY está definida en .env
// ══════════════════════════════════════════════════════════════
function auth(req, res, next) {
  if (!API_KEY) return next();
  const provided = req.headers['x-api-key'] || req.query.apiKey;
  if (provided !== API_KEY) return res.status(401).json({ error: 'No autorizado' });
  next();
}

// ══════════════════════════════════════════════════════════════
//  DB SETUP
// ══════════════════════════════════════════════════════════════
let db = null;

if (ENABLE_DB) {
  const Database = require('better-sqlite3');
  const dataDir  = path.join(__dirname, 'data');
  const dbPath   = path.join(dataDir, 'lsc.db');

  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

  db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  db.exec(`
    CREATE TABLE IF NOT EXISTS logs (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      saved_at   TEXT NOT NULL,
      raw_text   TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS agents (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      log_id       INTEGER NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
      identifier   TEXT    NOT NULL,
      name         TEXT    NOT NULL,
      total_mins   REAL    NOT NULL,
      UNIQUE (log_id, identifier)
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      agent_id   INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      log_id     INTEGER NOT NULL,
      tipo       TEXT    NOT NULL,
      mins       REAL    NOT NULL
    );

    CREATE TABLE IF NOT EXISTS empleados (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre     TEXT NOT NULL,
      identifier TEXT,
      rango      TEXT NOT NULL DEFAULT 'experimentado',
      created_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_logs_saved_at     ON logs(saved_at);
    CREATE INDEX IF NOT EXISTS idx_agents_log_id     ON agents(log_id);
    CREATE INDEX IF NOT EXISTS idx_agents_identifier ON agents(identifier);
    CREATE INDEX IF NOT EXISTS idx_sessions_agent_id ON sessions(agent_id);
    CREATE INDEX IF NOT EXISTS idx_empleados_rango   ON empleados(rango);
  `);

  console.log(`[DB] SQLite activo · ${dbPath} · retención ${RETENTION_DAYS}d · WAL ON · FK ON`);
} else {
  console.log('[DB] Desactivada (ENABLE_DB=false)');
}

// ══════════════════════════════════════════════════════════════
//  PURGE — throttled: se ejecuta máximo una vez por hora
// ══════════════════════════════════════════════════════════════
const PURGE_INTERVAL_MS = 60 * 60 * 1000;
let lastPurgeAt = 0;

function purge() {
  if (!db) return;
  const now = Date.now();
  if (now - lastPurgeAt < PURGE_INTERVAL_MS) return;
  lastPurgeAt = now;
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - RETENTION_DAYS);
  const { changes } = db.prepare('DELETE FROM logs WHERE saved_at < ?').run(cutoff.toISOString());
  if (changes > 0) console.log(`[DB] Purga: ${changes} log(s) > ${RETENTION_DAYS}d eliminados`);
}

// ══════════════════════════════════════════════════════════════
//  SAVE — transacción atómica: todo o nada
// ══════════════════════════════════════════════════════════════
function saveLog(rawText, agents) {
  purge();

  const now         = new Date().toISOString();
  const stmtLog     = db.prepare('INSERT INTO logs (saved_at, raw_text) VALUES (?, ?)');
  const stmtAgent   = db.prepare('INSERT INTO agents (log_id, identifier, name, total_mins) VALUES (?, ?, ?, ?)');
  const stmtSession = db.prepare('INSERT INTO sessions (agent_id, log_id, tipo, mins) VALUES (?, ?, ?, ?)');

  return db.transaction(() => {
    const logId = stmtLog.run(now, rawText).lastInsertRowid;
    for (const agent of agents) {
      const agentId = stmtAgent.run(logId, agent.identifier, agent.name, agent.totalMins).lastInsertRowid;
      for (const s of agent.sessions) {
        stmtSession.run(agentId, logId, s.tipo, s.mins);
      }
    }
    return logId;
  })();
}

// ══════════════════════════════════════════════════════════════
//  GET HISTORY — un JOIN en lugar de N+1 queries individuales
// ══════════════════════════════════════════════════════════════
function getHistory() {
  purge();

  const rows = db.prepare(`
    SELECT
      l.id        AS log_id,
      l.saved_at,
      a.id        AS agent_id,
      a.identifier,
      a.name,
      a.total_mins,
      s.id        AS session_id,
      s.tipo,
      s.mins      AS session_mins
    FROM (SELECT id, saved_at FROM logs ORDER BY saved_at DESC LIMIT 100) l
    JOIN      agents   a ON a.log_id   = l.id
    LEFT JOIN sessions s ON s.agent_id = a.id
    ORDER BY l.saved_at DESC, a.total_mins DESC, s.id ASC
  `).all();

  const logsMap = new Map();
  for (const row of rows) {
    if (!logsMap.has(row.log_id)) {
      logsMap.set(row.log_id, { id: row.log_id, savedAt: row.saved_at, agentsMap: new Map() });
    }
    const log = logsMap.get(row.log_id);
    if (!log.agentsMap.has(row.agent_id)) {
      log.agentsMap.set(row.agent_id, {
        identifier: row.identifier,
        name:       row.name,
        totalMins:  row.total_mins,
        sessions:   [],
      });
    }
    if (row.session_id !== null) {
      log.agentsMap.get(row.agent_id).sessions.push({ tipo: row.tipo, mins: row.session_mins });
    }
  }

  return Array.from(logsMap.values()).map(log => ({
    id:      log.id,
    savedAt: log.savedAt,
    agents:  Array.from(log.agentsMap.values()),
  }));
}

function countLogs() {
  return db.prepare('SELECT COUNT(*) AS n FROM logs').get().n;
}

// ══════════════════════════════════════════════════════════════
//  ROUTES
// ══════════════════════════════════════════════════════════════
app.get('/api/status', (_req, res) => {
  res.json({ dbEnabled: ENABLE_DB, retentionDays: RETENTION_DAYS, authRequired: !!API_KEY, goalHours: GOAL_HOURS });
});

app.post('/api/logs', auth, (req, res) => {
  const { rawText, agents } = req.body;

  if (!rawText || !Array.isArray(agents) || agents.length === 0) {
    return res.status(400).json({ error: 'rawText y agents[] son requeridos' });
  }

  if (Buffer.byteLength(rawText, 'utf8') > RAW_TEXT_MAX_BYTES) {
    return res.status(413).json({ error: `rawText excede el límite de ${Math.round(RAW_TEXT_MAX_BYTES / 1024)}KB` });
  }

  for (const a of agents) {
    if (!a.identifier || !a.name || typeof a.totalMins !== 'number' || !Array.isArray(a.sessions)) {
      return res.status(400).json({ error: 'Agente con estructura inválida', agent: a });
    }
    for (const s of a.sessions) {
      if (!s.tipo || typeof s.mins !== 'number') {
        return res.status(400).json({ error: 'Sesión con estructura inválida', session: s });
      }
    }
  }

  if (!ENABLE_DB) return res.json({ saved: false, message: 'DB desactivada' });

  try {
    const logId     = saveLog(rawText, agents);
    const totalLogs = countLogs();
    console.log(`[DB] Log #${logId} guardado · ${agents.length} agente(s)`);
    res.json({ saved: true, logId, totalLogs });
  } catch (err) {
    console.error('[DB] Error al guardar:', err.message);
    if (err.message && err.message.includes('UNIQUE')) {
      return res.status(409).json({ error: 'Agente duplicado en el mismo log' });
    }
    res.status(500).json({ error: 'Error interno al guardar' });
  }
});

app.get('/api/logs', auth, (_req, res) => {
  if (!ENABLE_DB) return res.json({ dbEnabled: false, logs: [] });
  try {
    res.json({ dbEnabled: true, logs: getHistory() });
  } catch (err) {
    console.error('[DB] Error al leer:', err.message);
    res.status(500).json({ error: 'Error interno al leer historial' });
  }
});

// ══════════════════════════════════════════════════════════════
//  EMPLEADOS
// ══════════════════════════════════════════════════════════════
const RANGOS_VALIDOS = ['experimentado', 'ingeniero', 'subjefe', 'jefe', 'director'];

app.get('/api/empleados', auth, (_req, res) => {
  if (!ENABLE_DB) return res.json({ empleados: [] });
  try {
    const rows = db.prepare('SELECT * FROM empleados ORDER BY created_at ASC').all();
    res.json({ empleados: rows });
  } catch (err) {
    console.error('[DB] Error al leer empleados:', err.message);
    res.status(500).json({ error: 'Error interno al leer empleados' });
  }
});

app.post('/api/empleados', auth, (req, res) => {
  const { nombre, identifier, rango } = req.body;
  if (!nombre || !nombre.trim()) return res.status(400).json({ error: 'nombre es requerido' });
  const rangoFinal = rango && RANGOS_VALIDOS.includes(rango) ? rango : 'experimentado';
  if (!ENABLE_DB) return res.status(503).json({ error: 'DB desactivada' });
  try {
    const now = new Date().toISOString();
    const result = db.prepare(
      'INSERT INTO empleados (nombre, identifier, rango, created_at) VALUES (?, ?, ?, ?)'
    ).run(nombre.trim(), identifier ? identifier.trim() : null, rangoFinal, now);
    const empleado = db.prepare('SELECT * FROM empleados WHERE id = ?').get(result.lastInsertRowid);
    console.log(`[DB] Empleado #${empleado.id} creado: ${empleado.nombre} (${empleado.rango})`);
    res.json({ empleado });
  } catch (err) {
    console.error('[DB] Error al crear empleado:', err.message);
    res.status(500).json({ error: 'Error interno al crear empleado' });
  }
});

app.put('/api/empleados/:id', auth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!Number.isFinite(id)) return res.status(400).json({ error: 'ID inválido' });
  const { nombre, identifier, rango } = req.body;
  if (!ENABLE_DB) return res.status(503).json({ error: 'DB desactivada' });
  try {
    const existing = db.prepare('SELECT * FROM empleados WHERE id = ?').get(id);
    if (!existing) return res.status(404).json({ error: 'Empleado no encontrado' });
    const nuevoNombre     = nombre     ? nombre.trim()     : existing.nombre;
    const nuevoIdentifier = identifier !== undefined ? (identifier ? identifier.trim() : null) : existing.identifier;
    const nuevoRango      = rango && RANGOS_VALIDOS.includes(rango) ? rango : existing.rango;
    db.prepare('UPDATE empleados SET nombre = ?, identifier = ?, rango = ? WHERE id = ?')
      .run(nuevoNombre, nuevoIdentifier, nuevoRango, id);
    const updated = db.prepare('SELECT * FROM empleados WHERE id = ?').get(id);
    res.json({ empleado: updated });
  } catch (err) {
    console.error('[DB] Error al actualizar empleado:', err.message);
    res.status(500).json({ error: 'Error interno al actualizar empleado' });
  }
});

app.delete('/api/empleados/:id', auth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!Number.isFinite(id)) return res.status(400).json({ error: 'ID inválido' });
  if (!ENABLE_DB) return res.status(503).json({ error: 'DB desactivada' });
  try {
    const { changes } = db.prepare('DELETE FROM empleados WHERE id = ?').run(id);
    if (changes === 0) return res.status(404).json({ error: 'Empleado no encontrado' });
    res.json({ deleted: true, id });
  } catch (err) {
    console.error('[DB] Error al eliminar empleado:', err.message);
    res.status(500).json({ error: 'Error interno al eliminar empleado' });
  }
});

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, '../frontend/index.html'));
});

// ══════════════════════════════════════════════════════════════
//  START
// ══════════════════════════════════════════════════════════════
app.listen(PORT, () => {
  console.log(`\n🚀 LSC Tracker en http://localhost:${PORT}`);
  console.log(`   DB:        ${ENABLE_DB ? '✅ activa' : '❌ desactivada'}`);
  if (ENABLE_DB) console.log(`   Retención: ${RETENTION_DAYS} días`);
  console.log(`   Objetivo:  ${GOAL_HOURS}h semanales por agente`);
  console.log(`   Límite log: ${MAX_LOG_MB}MB`);
  console.log(`   Auth:      ${API_KEY ? '✅ API_KEY activa' : '❌ sin protección'}\n`);
});
