'use strict';

const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3000;

// ── Security middleware ───────────────────────────────────────
// helmet sets secure HTTP headers (X-Frame-Options, CSP, HSTS, etc.)
app.use(helmet());

// ── Logging ──────────────────────────────────────────────────
app.use(morgan('combined'));

// ── Body parsing ─────────────────────────────────────────────
app.use(express.json({ limit: '10kb' }));  // Limit body size to prevent DoS

// ── Routes ───────────────────────────────────────────────────
app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    message: 'DevSecOps Demo App',
    version: process.env.APP_VERSION || '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', uptime: process.uptime() });
});

app.get('/api/users', (req, res) => {
  // Simulated data — no real DB in this demo
  res.json([
    { id: 1, name: 'Alice', role: 'admin' },
    { id: 2, name: 'Bob', role: 'user' },
  ]);
});

// ── 404 handler ──────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// ── Error handler ────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error(err.stack);
  // Never expose stack traces to the client in production
  res.status(500).json({ error: 'Internal server error' });
});

// ── Start ─────────────────────────────────────────────────────
if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on port ${PORT}`);
  });
}

module.exports = app; // Export for tests
