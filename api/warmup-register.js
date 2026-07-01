// Warmup Pool Coordinator — Register/Update mailboxes
// POST /api/warmup-register
// Body: { instance_id, license_key, mailboxes: [{ email, timezone, provider }] }

import { getDb } from './_warmup-db.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const { instance_id, license_key, mailboxes } = req.body;

  if (!instance_id || !license_key || !Array.isArray(mailboxes)) {
    return res.status(400).json({ error: 'instance_id, license_key, and mailboxes[] required' });
  }

  // Validate license (quick check — same approach as verify-license.js)
  const DODO_KEY = process.env.DODO_PRIVATE_KEY;
  if (!DODO_KEY) return res.status(500).json({ error: 'Server config error' });

  const isTest = DODO_KEY.startsWith('test_');
  const apiUrl = isTest
    ? 'https://test.dodopayments.com/licenses/activate'
    : 'https://live.dodopayments.com/licenses/activate';

  try {
    const licResp = await fetch(apiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ license_key, name: instance_id })
    });

    // Accept 200 or 201 as valid
    if (!licResp.ok && licResp.status !== 201) {
      return res.status(401).json({ error: 'Invalid license. Cannot join pool.' });
    }
  } catch {
    // If license server unreachable, allow (grace)
  }

  const db = getDb();
  const now = new Date().toISOString();

  // Upsert each mailbox
  for (const mb of mailboxes) {
    if (!mb.email) continue;
    const existing = db.data.mailboxes.find(m => m.email === mb.email);
    if (existing) {
      existing.instance_id = instance_id;
      existing.timezone = mb.timezone || 'UTC';
      existing.provider = mb.provider || 'smtp';
      existing.last_heartbeat = now;
      existing.is_active = true;
    } else {
      db.data.mailboxes.push({
        email: mb.email,
        instance_id,
        timezone: mb.timezone || 'UTC',
        provider: mb.provider || 'smtp',
        is_active: true,
        last_heartbeat: now,
        created_at: now,
      });
    }
  }

  // Remove any mailboxes from this instance that are no longer in the list
  const activeEmails = new Set(mailboxes.map(m => m.email));
  db.data.mailboxes = db.data.mailboxes.map(m => {
    if (m.instance_id === instance_id && !activeEmails.has(m.email)) {
      return { ...m, is_active: false };
    }
    return m;
  });

  db.write();

  const poolSize = db.data.mailboxes.filter(m => m.is_active).length;
  const instanceCount = new Set(db.data.mailboxes.filter(m => m.is_active).map(m => m.instance_id)).size;

  return res.status(200).json({
    registered: mailboxes.length,
    pool_size: poolSize,
    instance_count: instanceCount,
  });
}
