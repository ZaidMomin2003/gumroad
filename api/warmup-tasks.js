// Warmup Pool Coordinator — Get tasks for an instance
// GET /api/warmup-tasks?instance_id=xxx&hour=10
// Returns assignments for the current time window

import { getDb } from './_warmup-db.js';
import { generateEmail } from './_warmup-templates.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET only' });

  const { instance_id } = req.query;
  if (!instance_id) return res.status(400).json({ error: 'instance_id required' });

  const db = getDb();
  const today = new Date().toISOString().split('T')[0];

  // Get this instance's active mailboxes
  const myMailboxes = db.data.mailboxes.filter(m => m.instance_id === instance_id && m.is_active);
  if (myMailboxes.length === 0) {
    return res.status(200).json({ tasks: [] });
  }

  // Get all OTHER active mailboxes (the pool targets)
  const otherMailboxes = db.data.mailboxes.filter(m => m.instance_id !== instance_id && m.is_active);
  if (otherMailboxes.length === 0) {
    return res.status(200).json({ tasks: [], message: 'No other mailboxes in pool yet' });
  }

  // Check if we already generated tasks for today
  let todayTasks = db.data.tasks.filter(t => t.date === today && t.sender_instance === instance_id);

  if (todayTasks.length === 0) {
    // Generate tasks for today — each of our mailboxes gets assigned targets from the pool
    todayTasks = [];

    for (const sender of myMailboxes) {
      // Determine quota based on warmup day (simplified — instance tracks this, we just cap at 20)
      const quota = Math.min(20, Math.max(2, myMailboxes.length <= 3 ? 5 : 10));

      // Get recent targets to avoid repeats (last 7 days)
      const recentTargets = new Set(
        db.data.tasks
          .filter(t => t.sender_email === sender.email && daysDiff(t.date, today) < 7)
          .map(t => t.receiver_email)
      );

      // Shuffle pool targets and pick ones we haven't emailed recently
      const shuffled = [...otherMailboxes].sort(() => Math.random() - 0.5);
      const targets = shuffled
        .filter(t => !recentTargets.has(t.email) && t.email !== sender.email)
        .slice(0, quota);

      for (const target of targets) {
        const email = generateEmail();
        const task = {
          id: `${today}-${sender.email}-${target.email}`.replace(/[^a-z0-9-@.]/gi, ''),
          date: today,
          sender_email: sender.email,
          sender_instance: instance_id,
          receiver_email: target.email,
          receiver_instance: target.instance_id,
          subject: email.subject,
          body: email.body,
          reply_body: email.reply,
          status: 'pending', // pending → sent → received → replied
          created_at: new Date().toISOString(),
        };
        todayTasks.push(task);
        db.data.tasks.push(task);
      }
    }

    // Trim old tasks (keep last 14 days only)
    db.data.tasks = db.data.tasks.filter(t => daysDiff(t.date, today) < 14);
    db.write();
  }

  // Return only pending tasks (not yet sent)
  const pending = todayTasks.filter(t => t.status === 'pending');

  return res.status(200).json({ tasks: pending });
}

function daysDiff(dateStr1, dateStr2) {
  const d1 = new Date(dateStr1);
  const d2 = new Date(dateStr2);
  return Math.abs(Math.floor((d2 - d1) / (1000 * 60 * 60 * 24)));
}
