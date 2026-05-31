const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const API_URL = (process.env.API_URL || 'http://localhost:8080').replace(/\/$/, '');

// Read the raw request body into a Buffer (used when proxying writes).
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

// Reverse-proxy everything under /api to the Go API service so the browser
// talks to a single origin (no CORS juggling in the client).
app.use(async (req, res, next) => {
  if (!req.path.startsWith('/api/')) return next();

  const target = API_URL + req.originalUrl;
  const headers = { ...req.headers };
  delete headers.host;
  delete headers['content-length'];

  const hasBody = !['GET', 'HEAD'].includes(req.method);
  let body;
  if (hasBody) {
    body = await readBody(req);
  }

  try {
    const upstream = await fetch(target, {
      method: req.method,
      headers,
      body: hasBody ? body : undefined,
    });

    res.status(upstream.status);
    const contentType = upstream.headers.get('content-type');
    if (contentType) res.set('Content-Type', contentType);

    const buf = Buffer.from(await upstream.arrayBuffer());
    res.send(buf);
  } catch (err) {
    console.error(`Proxy error -> ${target}:`, err.message);
    res.status(502).json({ error: 'Bad gateway: API service is unreachable' });
  }
});

// Static frontend.
app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, () => {
  console.log(`KMS web running at http://localhost:${PORT}`);
  console.log(`Proxying /api -> ${API_URL}`);
});
