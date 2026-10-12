const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const app = require('../src/server');

test('Preview Environment Server Test Suite', async (t) => {
  await t.test('GET /health returns 200 OK and valid JSON health payload', async () => {
    const res = await request(app)
      .get('/health')
      .expect('Content-Type', /json/)
      .expect(200);

    assert.equal(res.body.status, 'UP');
    assert.ok(typeof res.body.uptimeSeconds === 'number');
    assert.ok(typeof res.body.version === 'string');
    assert.ok(typeof res.body.port === 'number');
    assert.ok(res.body.timestamp);
  });

  await t.test('GET /api/info returns runtime information', async () => {
    const res = await request(app)
      .get('/api/info')
      .expect('Content-Type', /json/)
      .expect(200);

    assert.equal(res.body.appName, 'Ephemeral PR Preview Environments');
    assert.ok(res.body.nodeVersion);
    assert.ok(res.body.platform);
  });

  await t.test('GET / returns HTML document with responsive UI template', async () => {
    const res = await request(app)
      .get('/')
      .expect('Content-Type', /text\/html/)
      .expect(200);

    assert.ok(res.text.includes('<!DOCTYPE html>'));
    assert.ok(res.text.includes('Ephemeral PR Preview'));
    assert.ok(res.text.includes('<base href='));
  });

  await t.test('GET /style.css returns stylesheet', async () => {
    const res = await request(app)
      .get('/style.css')
      .expect('Content-Type', /css/)
      .expect(200);

    assert.ok(res.text.includes('--bg-primary'));
  });

  await t.test('GET /app.js returns client script', async () => {
    const res = await request(app)
      .get('/app.js')
      .expect('Content-Type', /javascript/)
      .expect(200);

    assert.ok(res.text.includes('DOMContentLoaded'));
  });

  await t.test('GET /non-existent-route returns 404 status', async () => {
    const res = await request(app)
      .get('/non-existent-route')
      .expect(404);

    assert.ok(res.text.includes('404'));
  });
});
