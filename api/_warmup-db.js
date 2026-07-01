// Simple JSON file "database" for the warmup coordinator.
// In production, replace with Postgres/Firebase. For now this works on Vercel (ephemeral but functional).
// Data persists across invocations within the same serverless instance lifecycle.

let dbInstance = null;

const defaultData = {
  mailboxes: [],  // { email, instance_id, timezone, provider, is_active, last_heartbeat, created_at }
  tasks: [],      // { id, date, sender_email, sender_instance, receiver_email, receiver_instance, subject, body, reply_body, status, created_at }
};

class SimpleDb {
  constructor() {
    this.data = { ...defaultData, mailboxes: [], tasks: [] };
  }

  write() {
    // In-memory only — persists within the serverless instance lifecycle.
    // For persistent storage, swap this with a Firebase/Postgres write.
  }
}

export function getDb() {
  if (!dbInstance) {
    dbInstance = new SimpleDb();
  }
  return dbInstance;
}
