// Warmup Pool Coordinator — Report task status
// POST /api/warmup-report
// Body: { instance_id, reports: [{ sender_email, receiver_email, status, date }] }

import { getDb } from './_warmup-db.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const { instance_id, reports } = req.body;
  if (!instance_id || !Array.isArray(reports)) {
    return res.status(400).json({ error: 'instance_id and reports[] required' });
  }

  const db = getDb();
  let updated = 0;

  for (const report of reports) {
    const { sender_email, receiver_email, status, date } = report;
    if (!sender_email || !receiver_email || !status) continue;

    const taskDate = date || new Date().toISOString().split('T')[0];

    // Find the matching task
    const task = db.data.tasks.find(t =>
      t.sender_email === sender_email &&
      t.receiver_email === receiver_email &&
      t.date === taskDate
    );

    if (task) {
      // Only allow forward progression: pending → sent → received → replied
      const statusOrder = { pending: 0, sent: 1, received: 2, opened: 3, replied: 4 };
      if ((statusOrder[status] || 0) > (statusOrder[task.status] || 0)) {
        task.status = status;
        task[`${status}_at`] = new Date().toISOString();
        updated++;
      }
    }
  }

  if (updated > 0) db.write();

  return res.status(200).json({ updated });
}
