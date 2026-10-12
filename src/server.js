const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();

// Configuration from environment variables
const PORT = process.env.PORT || 3000;
const PR_NUMBER = process.env.PR_NUMBER || null;
const GIT_SHA = (process.env.GIT_SHA || process.env.GITHUB_SHA || 'local-dev').substring(0, 7);
const APP_ENV = process.env.APP_ENV || (PR_NUMBER ? `preview-pr-${PR_NUMBER}` : 'development');
const APP_VERSION = process.env.APP_VERSION || '1.0.0';
const FEATURE_NAME = process.env.FEATURE_NAME || (PR_NUMBER ? `Feature Branch for PR #${PR_NUMBER}` : 'Core Platform Baseline');
const THEME_NAME = process.env.THEME_NAME || (PR_NUMBER ? (parseInt(PR_NUMBER, 10) % 2 === 0 ? 'emerald' : 'cyan') : 'indigo');
const BASE_PATH = (process.env.BASE_PATH || (PR_NUMBER ? `/pr-${PR_NUMBER}` : '')).replace(/\/+$/, '');

const startTime = Date.now();

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl} ${res.statusCode} - ${duration}ms`);
  });
  next();
});

// JSON body parser
app.use(express.json());

// Main router
const router = express.Router();

// Helper to render index.html with runtime replacements
function renderIndexHtml(req) {
  const filePath = path.join(__dirname, 'public', 'index.html');
  let html = fs.readFileSync(filePath, 'utf8');

  // Detect prefix from X-Forwarded-Prefix header or environment BASE_PATH
  const forwardedPrefix = req.headers['x-forwarded-prefix'] || '';
  const effectiveBasePath = forwardedPrefix || BASE_PATH || '';
  const baseHref = effectiveBasePath ? `${effectiveBasePath}/` : '/';

  // Replace placeholders
  html = html
    .replace(/__BASE_HREF__/g, baseHref)
    .replace(/__APP_TITLE__/g, 'Ephemeral PR Preview Environments')
    .replace(/__APP_VERSION__/g, APP_VERSION)
    .replace(/__APP_ENV__/g, APP_ENV)
    .replace(/__PR_NUMBER__/g, PR_NUMBER ? `#${PR_NUMBER}` : 'None (Main/Local)')
    .replace(/__PR_RAW__/g, PR_NUMBER || '')
    .replace(/__GIT_SHA__/g, GIT_SHA)
    .replace(/__FEATURE_NAME__/g, FEATURE_NAME)
    .replace(/__THEME_NAME__/g, THEME_NAME)
    .replace(/__SERVER_PORT__/g, PORT.toString())
    .replace(/__BASE_PATH__/g, effectiveBasePath || '/');

  return html;
}

// Health check endpoint
router.get('/health', (req, res) => {
  const uptimeSeconds = (Date.now() - startTime) / 1000;
  res.status(200).json({
    status: 'UP',
    timestamp: new Date().toISOString(),
    uptimeSeconds: Math.floor(uptimeSeconds),
    version: APP_VERSION,
    environment: APP_ENV,
    prNumber: PR_NUMBER ? parseInt(PR_NUMBER, 10) : null,
    commitSha: GIT_SHA,
    feature: FEATURE_NAME,
    theme: THEME_NAME,
    port: parseInt(PORT, 10),
    basePath: BASE_PATH || '/'
  });
});

// Detailed system info endpoint
router.get('/api/info', (req, res) => {
  res.status(200).json({
    appName: 'Ephemeral PR Preview Environments',
    version: APP_VERSION,
    environment: APP_ENV,
    prNumber: PR_NUMBER,
    commitSha: GIT_SHA,
    feature: FEATURE_NAME,
    theme: THEME_NAME,
    nodeVersion: process.version,
    platform: process.platform,
    pid: process.pid,
    memoryUsage: process.memoryUsage(),
    requestHeaders: {
      host: req.headers.host,
      forwardedProto: req.headers['x-forwarded-proto'],
      forwardedPrefix: req.headers['x-forwarded-prefix'],
      userAgent: req.headers['user-agent']
    }
  });
});

// Root endpoint rendering the responsive UI
router.get('/', (req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(renderIndexHtml(req));
});

// Static assets
router.use(express.static(path.join(__dirname, 'public'), { index: false }));

// Mount router on root
app.use('/', router);

// Mount router on BASE_PATH if set (e.g. /pr-42) to support both stripped and unstripped proxies
if (BASE_PATH && BASE_PATH !== '/') {
  app.use(BASE_PATH, router);
}

// 404 handler
app.use((req, res) => {
  if (req.accepts('html')) {
    res.status(404).send(`
      <!DOCTYPE html>
      <html>
      <head><title>404 Not Found - PR Preview</title><style>body{font-family:sans-serif;padding:40px;background:#0f172a;color:#f8fafc;text-align:center;}a{color:#38bdf8;}</style></head>
      <body>
        <h1>404 - Route Not Found</h1>
        <p>The path <code>${req.originalUrl}</code> was not found on this preview environment.</p>
        <p><a href="${BASE_PATH ? BASE_PATH + '/' : '/'}">Return to Preview Home</a></p>
      </body>
      </html>
    `);
  } else {
    res.status(404).json({ error: 'Not Found', path: req.originalUrl });
  }
});

// Start listener only when run directly
if (require.main === module) {
  const server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`====================================================`);
    console.log(`🚀 Preview Application Running`);
    console.log(`   Port:        ${PORT}`);
    console.log(`   Environment: ${APP_ENV}`);
    console.log(`   PR Number:   ${PR_NUMBER || 'N/A'}`);
    console.log(`   Commit SHA:  ${GIT_SHA}`);
    console.log(`   Base Path:   ${BASE_PATH || '/'}`);
    console.log(`   Theme:       ${THEME_NAME}`);
    console.log(`   Health Check: http://localhost:${PORT}${BASE_PATH}/health`);
    console.log(`====================================================`);
  });

  // Graceful shutdown
  const handleShutdown = (signal) => {
    console.log(`\nReceived ${signal}. Gracefully shutting down...`);
    server.close(() => {
      console.log('HTTP server closed. Exiting process.');
      process.exit(0);
    });
  };

  process.on('SIGTERM', () => handleShutdown('SIGTERM'));
  process.on('SIGINT', () => handleShutdown('SIGINT'));
}

module.exports = app;
