// ============================================
// REDIS SSE BRIDGE
// Pont entre n8n, Redis et les widgets SSE
// ============================================

import express from 'express';
import { createClient } from 'redis';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

// ============================================
// REDIS CLIENTS
// ============================================

const redis = createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379')
  }
});

const pubClient = redis.duplicate();
const subClient = redis.duplicate();

// Gestion des erreurs
redis.on('error', (err) => console.error('❌ Redis Client Error:', err));
pubClient.on('error', (err) => console.error('❌ Redis Pub Client Error:', err));
subClient.on('error', (err) => console.error('❌ Redis Sub Client Error:', err));

// Connexion
await redis.connect();
await pubClient.connect();
await subClient.connect();

console.log('✅ Connected to Redis');

// ============================================
// SSE CLIENTS MANAGEMENT
// ============================================

const sseClients = new Set();

// Ajoute un client SSE
function addClient(res) {
  sseClients.add(res);
  console.log(`➕ Client SSE ajouté (total: ${sseClients.size})`);
}

// Retire un client SSE
function removeClient(res) {
  sseClients.delete(res);
  console.log(`➖ Client SSE retiré (total: ${sseClients.size})`);
}

// Broadcast vers tous les clients SSE
function broadcastToClients(message) {
  console.log(`📡 Broadcasting to ${sseClients.size} clients:`, message.substring(0, 100));

  const deadClients = [];

  sseClients.forEach((client) => {
    try {
      client.write(message);
    } catch (error) {
      console.error('❌ Error sending to client:', error.message);
      deadClients.push(client);
    }
  });

  // Nettoie les clients morts
  deadClients.forEach(client => removeClient(client));
}

// ============================================
// REDIS PUB/SUB LISTENER
// ============================================

const CHANNEL = 'grist-realtime-interventions';

await subClient.subscribe(CHANNEL, (message) => {
  console.log(`📨 Message received on ${CHANNEL}:`, message.substring(0, 100));

  // Format SSE standard
  const sseMessage = `data: ${message}\n\n`;

  // Broadcast vers tous les clients connectés
  broadcastToClients(sseMessage);
});

console.log(`👂 Listening on Redis channel: ${CHANNEL}`);

// ============================================
// HTTP ENDPOINTS
// ============================================

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    uptime: process.uptime(),
    clients: sseClients.size,
    redis: 'connected',
    timestamp: new Date().toISOString()
  });
});

// SSE Stream endpoint
app.get('/sse-stream', (req, res) => {
  // Configuration SSE headers
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('X-Accel-Buffering', 'no'); // Pour Nginx

  // Ajoute le client
  addClient(res);

  // Message de connexion initial
  res.write(`data: ${JSON.stringify({
    type: 'connected',
    timestamp: new Date().toISOString(),
    message: 'Connexion SSE établie'
  })}\n\n`);

  // Heartbeat toutes les 30 secondes
  const heartbeatInterval = setInterval(() => {
    try {
      res.write(': heartbeat\n\n');
    } catch (e) {
      clearInterval(heartbeatInterval);
      removeClient(res);
    }
  }, 30000);

  // Nettoyage à la déconnexion
  req.on('close', () => {
    clearInterval(heartbeatInterval);
    removeClient(res);
  });
});

// Publish endpoint (pour n8n)
app.post('/redis/publish', async (req, res) => {
  try {
    const { channel, message } = req.body;

    if (!channel || !message) {
      return res.status(400).json({
        success: false,
        error: 'Missing channel or message'
      });
    }

    const messageStr = typeof message === 'string' ? message : JSON.stringify(message);

    await pubClient.publish(channel, messageStr);

    console.log(`📤 Published to ${channel}:`, messageStr.substring(0, 100));

    res.json({
      success: true,
      channel,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Publish error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// SETEX endpoint (pour n8n)
app.post('/redis/setex', async (req, res) => {
  try {
    const { key, value, ttl } = req.body;

    if (!key || !value || !ttl) {
      return res.status(400).json({
        success: false,
        error: 'Missing key, value or ttl'
      });
    }

    const valueStr = typeof value === 'string' ? value : JSON.stringify(value);

    await redis.setEx(key, parseInt(ttl), valueStr);

    console.log(`💾 SETEX ${key} (TTL: ${ttl}s):`, valueStr.substring(0, 100));

    res.json({
      success: true,
      key,
      ttl,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ SETEX error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET endpoint (pour lire une clé)
app.get('/redis/get/:key', async (req, res) => {
  try {
    const { key } = req.params;
    const value = await redis.get(key);

    if (!value) {
      return res.status(404).json({
        success: false,
        error: 'Key not found'
      });
    }

    res.json({
      success: true,
      key,
      value: value,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ GET error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// KEYS endpoint (pour lister les clés)
app.get('/redis/keys/:pattern', async (req, res) => {
  try {
    const { pattern } = req.params;
    const keys = await redis.keys(pattern);

    res.json({
      success: true,
      pattern,
      keys,
      count: keys.length,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ KEYS error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ============================================
// SERVER START
// ============================================

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log('');
  console.log('🚀 ======================================');
  console.log('🚀 Redis SSE Bridge Started!');
  console.log('🚀 ======================================');
  console.log('');
  console.log(`📡 SSE endpoint:     http://localhost:${PORT}/sse-stream`);
  console.log(`📤 Publish endpoint: POST http://localhost:${PORT}/redis/publish`);
  console.log(`💾 SetEx endpoint:   POST http://localhost:${PORT}/redis/setex`);
  console.log(`❤️  Health endpoint:  http://localhost:${PORT}/health`);
  console.log('');
  console.log(`👂 Redis channel:    ${CHANNEL}`);
  console.log(`🔌 Connected clients: ${sseClients.size}`);
  console.log('');
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('🛑 SIGTERM received, shutting down gracefully...');

  // Ferme les clients SSE
  sseClients.forEach(client => {
    try {
      client.end();
    } catch (e) {
      // Ignore
    }
  });

  // Ferme Redis
  await redis.quit();
  await pubClient.quit();
  await subClient.quit();

  process.exit(0);
});
