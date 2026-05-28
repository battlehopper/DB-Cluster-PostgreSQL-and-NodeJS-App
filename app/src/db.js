'use strict';

// Instrumentacao Datadog deve carregar ANTES do modulo pg
require('./tracing');

const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.PGHOST || 'haproxy-db',
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || 'movida',
  user: process.env.PGUSER || 'movida_app',
  password: process.env.PGPASSWORD || 'movida_secret',
  max: Number(process.env.PGPOOL_MAX || 10),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// Protocolo simples: comentarios DBM (dddbs/ddps) aparecem no pg_stat_statements
function withSimpleQueryMode(text, values) {
  if (typeof text === 'string') {
    return { text, values, queryMode: 'simple' };
  }
  if (text && typeof text === 'object') {
    return { ...text, queryMode: text.queryMode || 'simple' };
  }
  return text;
}

const originalQuery = pool.query.bind(pool);
pool.query = (text, values, callback) => {
  if (typeof callback === 'function') {
    return originalQuery(withSimpleQueryMode(text, values), callback);
  }
  return originalQuery(withSimpleQueryMode(text, values));
};

async function ping() {
  const client = await pool.connect();
  try {
    await client.query({ text: 'SELECT 1', queryMode: 'simple' });
  } finally {
    client.release();
  }
}

async function initSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS reservas (
      id SERIAL PRIMARY KEY,
      cliente VARCHAR(120) NOT NULL,
      veiculo VARCHAR(80) NOT NULL,
      dias INTEGER NOT NULL DEFAULT 1,
      criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function getClusterInfo() {
  const result = await pool.query(`
    SELECT
      current_database() AS database,
      inet_server_addr()::text AS backend_host,
      inet_server_port() AS backend_port,
      pg_is_in_recovery() AS is_replica,
      NOW() AS queried_at
  `);
  return result.rows[0];
}

async function listReservas() {
  const result = await pool.query(
    'SELECT id, cliente, veiculo, dias, criado_em FROM reservas ORDER BY id DESC LIMIT 50'
  );
  return result.rows;
}

async function createReserva(cliente, veiculo, dias) {
  const result = await pool.query(
    `INSERT INTO reservas (cliente, veiculo, dias)
     VALUES ($1, $2, $3)
     RETURNING id, cliente, veiculo, dias, criado_em`,
    [cliente, veiculo, dias]
  );
  return result.rows[0];
}

module.exports = {
  pool,
  ping,
  initSchema,
  getClusterInfo,
  listReservas,
  createReserva,
};
