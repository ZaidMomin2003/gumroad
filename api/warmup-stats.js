// Warmup Pool Coordinator — Get pool stats + per-mailbox stats
// GET /api/warmup-stats?instance_id=xxx
// Returns pool-level stats and per-mailbox health for this instance

import { getDb } from './_warmup-db.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET only' });

  const { instance_id } = req.query;
  if (!instance_id) return res.status(400).json({ error: 'instance_id required' });

  const db = getDb();
  const activeMailboxes = db.data.mailboxes.filter(m => m.is_active);
  const myMailboxes = activeMailboxes.filter(m => m.instance_id === instance_id);

  // Pool-level stats
  const poolStats = {
    total_mailboxes: activeMailboxes.length,
    total_instances: new Set(activeMailboxes.map(m => m.instance_id)).size,
    total_domains: new Set(activeMailboxes.map(m => m.email.split('@')[1])).size,
  };

  // Per-mailbox stats from tasks (last 30 days)
  const today = new Date().toISOString().split('T')[0];
  const mailboxStats = {};

  for (const mb of myMailboxes) {
    const sentTasks = db.data.tasks.filter(t => t.sender_email === mb.email);
    const recvTasks = db.data.tasks.filter(t => t.receiver_email === mb.email);

    const totalSent = sentTasks.filter(t => t.status !== 'pending').length;
    const totalReceived = recvTasks.filter(t => ['received', 'opened', 'replied'].includes(t.status)).length;
    const totalReplied = recvTasks.filter(t => t.status === 'replied').length;

    // Day-by-day breakdown (last 30 days)
    const days = [];
    for (let i = 29; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const dateStr = d.toISOString().split('T')[0];

      const daySent = sentTasks.filter(t => t.date === dateStr && t.status !== 'pending').length;
      const dayRecv = recvTasks.filter(t => t.date === dateStr && ['received', 'opened', 'replied'].includes(t.status)).length;
      const dayOpened = recvTasks.filter(t => t.date === dateStr && ['opened', 'replied'].includes(t.status)).length;
      const dayReplied = recvTasks.filter(t => t.date === dateStr && t.status === 'replied').length;

      // Inbox rate: received / (sent to this mailbox that day)
      const daySentToMe = db.data.tasks.filter(t => t.receiver_email === mb.email && t.date === dateStr && t.status !== 'pending').length;
      const inboxRate = daySentToMe > 0 ? Math.round((dayRecv / daySentToMe) * 100) : 0;

      if (daySent > 0 || dayRecv > 0) {
        days.push({ date: dateStr, sent: daySent, received: dayRecv, opened: dayOpened, replied: dayReplied, inbox_rate: inboxRate });
      }
    }

    // Calculate rates
    const sentTotal = sentTasks.length;
    const inboxRate = sentTotal > 0 ? Math.round((totalReceived / sentTotal) * 100) : 0;
    const spamRate = sentTotal > 0 ? Math.max(0, 100 - inboxRate) : 0;
    const replyRate = totalReceived > 0 ? Math.round((totalReplied / totalReceived) * 100) : 0;

    // Health score (weighted: inbox 60%, reply 30%, consistency 10%)
    const healthScore = Math.min(100, Math.round(inboxRate * 0.6 + replyRate * 0.3 + Math.min(totalSent, 50) * 0.2));

    mailboxStats[mb.email] = {
      total_sent: totalSent,
      total_received: totalReceived,
      inbox_rate: inboxRate,
      spam_rate: spamRate,
      reply_rate: replyRate,
      health_score: healthScore,
      last_30_days: days,
      sent_today: sentTasks.filter(t => t.date === today && t.status !== 'pending').length,
      received_today: recvTasks.filter(t => t.date === today && ['received', 'opened', 'replied'].includes(t.status)).length,
    };
  }

  return res.status(200).json({ pool_stats: poolStats, mailbox_stats: mailboxStats });
}
