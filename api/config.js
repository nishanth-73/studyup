'use strict';

const fs = require('node:fs');
const path = require('node:path');

// Vercel serverless function: GET /api/config
// Returns public client configuration (Supabase URL & anon publishable key).
// Never returns service-role keys or secrets.

let envFallback = {};
try {
  const envPath = path.join(__dirname, '..', '.env');
  if (fs.existsSync(envPath)) {
    const lines = fs.readFileSync(envPath, 'utf8').split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const idx = trimmed.indexOf('=');
      if (idx !== -1) {
        const k = trimmed.substring(0, idx).trim();
        const v = trimmed.substring(idx + 1).trim();
        envFallback[k] = v;
      }
    }
  }
} catch (_) {}

module.exports = (req, res) => {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'public, max-age=3600');

  const supabaseUrl =
    process.env.SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL ||
    envFallback.SUPABASE_URL ||
    '';
  const supabaseAnonKey =
    process.env.SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    envFallback.SUPABASE_ANON_KEY ||
    '';

  return res.status(200).json({
    supabaseUrl,
    supabaseAnonKey,
  });
};

