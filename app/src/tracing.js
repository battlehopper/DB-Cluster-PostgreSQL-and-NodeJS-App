'use strict';

const tracer = require('dd-trace').init({
  logInjection: true,
  runtimeMetrics: true,
  profiling: process.env.DD_PROFILING_ENABLED === 'true',
  appsec: process.env.DD_APPSEC_ENABLED === 'true',
});

module.exports = tracer;
