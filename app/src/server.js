'use strict';

// Datadog APM deve ser o primeiro import
require('./tracing');

const express = require('express');
const db = require('./db');

const app = express();
const port = Number(process.env.PORT || 3000);
const instanceId = process.env.INSTANCE_ID || 'api-unknown';

app.use(express.json());

app.get('/health', async (_req, res) => {
  try {
    await db.ping();
    res.json({
      status: 'ok',
      instance: instanceId,
      db: 'connected',
    });
  } catch (err) {
    res.status(503).json({
      status: 'degraded',
      instance: instanceId,
      db: 'unreachable',
      error: err.message,
    });
  }
});

app.get('/ready', async (_req, res) => {
  try {
    await db.ping();
    res.status(200).send('ready');
  } catch {
    res.status(503).send('not ready');
  }
});

app.get('/api/status', async (_req, res) => {
  const info = await db.getClusterInfo();
  res.json({
    service: 'movida-reservas-api',
    instance: instanceId,
    cluster: info,
  });
});

app.get('/api/reservas', async (_req, res) => {
  const rows = await db.listReservas();
  res.json({ instance: instanceId, count: rows.length, data: rows });
});

app.post('/api/reservas', async (req, res) => {
  const { cliente, veiculo, dias } = req.body || {};
  if (!cliente || !veiculo) {
    return res.status(400).json({ error: 'cliente e veiculo sao obrigatorios' });
  }
  const row = await db.createReserva(cliente, veiculo, Number(dias) || 1);
  res.status(201).json({ instance: instanceId, reserva: row });
});

app.get('/api/metrics/load', async (_req, res) => {
  // Endpoint util para gerar trafego sintetico em demos
  const iterations = Number(process.env.LOAD_ITERATIONS || 5);
  const results = [];
  for (let i = 0; i < iterations; i += 1) {
    results.push(await db.getClusterInfo());
  }
  res.json({ instance: instanceId, queries: results.length, samples: results });
});

app.use((err, _req, res, _next) => {
  console.error(`[${instanceId}]`, err);
  res.status(500).json({ error: err.message, instance: instanceId });
});

async function bootstrap() {
  await db.initSchema();
  app.listen(port, '0.0.0.0', () => {
    console.log(`[${instanceId}] API ouvindo em :${port} | DB via ${process.env.PGHOST}:${process.env.PGPORT}`);
  });
}

bootstrap().catch((err) => {
  console.error('Falha ao iniciar API:', err);
  process.exit(1);
});
