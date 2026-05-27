'use strict';

const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

const jenkinsRoutes = require('./routes/jenkins');
const sonarqubeRoutes = require('./routes/sonarqube');

const app = express();
const PORT = process.env.PORT || 4010;

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Health endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    service: 'backstage-mock-server',
    version: '1.0.0',
  });
});

// Jenkins routes (at root level — Jenkins API is at /job/...)
app.use('/', jenkinsRoutes);

// SonarQube routes (prefixed with /sonarqube)
app.use('/sonarqube', sonarqubeRoutes);

// Proxy-compatible Jenkins routes (when accessed via /jenkins/api proxy)
app.use('/jenkins/api', jenkinsRoutes);

// Catch-all 404
app.use((req, res) => {
  console.warn(`[404] Unhandled: ${req.method} ${req.url}`);
  res.status(404).json({ error: 'Not found', path: req.url });
});

// Error handler
app.use((err, req, res, _next) => {
  console.error('[ERROR]', err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Mock server running on port ${PORT}`);
  console.log(`   Jenkins API : http://localhost:${PORT}/job/:jobName/api/json`);
  console.log(`   SonarQube   : http://localhost:${PORT}/sonarqube/api/measures/component`);
  console.log(`   Health      : http://localhost:${PORT}/health`);
});

module.exports = app;
