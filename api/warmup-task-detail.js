// Warmup Pool Coordinator — Get a specific task's reply body
// GET /api/warmup-task-detail?sender=x@y.com&receiver=a@b.com&date=2025-07-01
// Used by receiving instances to fetch the reply template for auto-reply

import { getDb } from './_warmup-db.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET only' });

  const { sender, receiver, date } = req.query;
  if (!sender || !receiver) {
    return res.status(400).json({ error: 'sender and receiver required' });
  }

  const db = getDb();
  const taskDate = date || new Date().toISOString().split('T')[0];

  const task = db.data.tasks.find(t =>
    t.sender_email === sender &&
    t.receiver_email === receiver &&
    t.date === taskDate
  );

  if (!task) {
    return res.status(404).json({ error: 'Task not found' });
  }

  return res.status(200).json({
    reply_body: task.reply_body,
    subject: task.subject,
    sender_email: task.sender_email,
  });
}
