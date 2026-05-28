'use strict';

const tracer = require('dd-trace').init({
  logInjection: true,
  runtimeMetrics: true,
  profiling: process.env.DD_PROFILING_ENABLED === 'true',
  appsec: process.env.DD_APPSEC_ENABLED === 'true',
  // Correlaciona APM <-> DBM (queries vistas no host do LB + no real)
  dbmPropagationMode: process.env.DD_DBM_PROPAGATION_MODE || 'full',
});

module.exports = tracer;
