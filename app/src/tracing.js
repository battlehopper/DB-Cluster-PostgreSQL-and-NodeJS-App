'use strict';

const tracer = require('dd-trace').init({
  logInjection: true,
  runtimeMetrics: true,
  profiling: process.env.DD_PROFILING_ENABLED === 'true',
  appsec: process.env.DD_APPSEC_ENABLED === 'true',
  env: process.env.DD_ENV,
  service: process.env.DD_SERVICE,
  version: process.env.DD_VERSION,
  dbmPropagationMode: process.env.DD_DBM_PROPAGATION_MODE || 'full',
});

// Obrigatorio para Calling Services no DBM (propaga service/env/version no SQL)
tracer.use('pg', {
  dbmPropagationMode: process.env.DD_DBM_PROPAGATION_MODE || 'full',
});

module.exports = tracer;
