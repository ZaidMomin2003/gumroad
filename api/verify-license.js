export default async function handler(req, res) {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed. Use POST.' });
  }

  // Set up CORS just in case the app is pinging it from a web browser during onboarding
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { license_key, instance_name } = req.body;

  if (!license_key) {
    return res.status(400).json({ error: 'License key is required.' });
  }

  // Your Private DodoPayments Key must be stored in Vercel Environment Variables
  const DODO_PRIVATE_KEY = process.env.DODO_PRIVATE_KEY;

  if (!DODO_PRIVATE_KEY) {
    return res.status(500).json({ error: 'Server misconfiguration: Dodo Key missing.' });
  }

  const isTest = DODO_PRIVATE_KEY.startsWith('test_');

  try {
    // Step 1: Try /licenses/validate first (idempotent, doesn't consume activations).
    // This succeeds if the key has EVER been activated before.
    const validateUrl = isTest
      ? 'https://test.dodopayments.com/licenses/validate'
      : 'https://live.dodopayments.com/licenses/validate';

    const validateResp = await fetch(validateUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ license_key }),
    });

    if (validateResp.ok) {
      const validateData = await validateResp.json();
      // Dodo validate returns the license object with status field or {valid: true}
      const isValid = validateData.valid === true ||
        validateData.status === 'active' ||
        (validateData.id && validateResp.status < 300);

      if (isValid) {
        return res.status(200).json({
          valid: true,
          message: 'License is valid.',
          license_data: validateData,
        });
      }
    }

    // Step 2: If validate didn't confirm it, try /licenses/activate.
    // This is for genuinely first-time activations where the key exists but
    // has never been activated on any instance yet.
    const activateUrl = isTest
      ? 'https://test.dodopayments.com/licenses/activate'
      : 'https://live.dodopayments.com/licenses/activate';

    const activateResp = await fetch(activateUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        license_key: license_key,
        name: instance_name || 'cold mail Instance',
      }),
    });

    const activateData = await activateResp.json();

    if (activateResp.status === 201 || (activateResp.ok && activateData.id)) {
      return res.status(200).json({
        valid: true,
        message: 'License activated successfully.',
        license_data: activateData,
      });
    }

    // Both failed — key is genuinely invalid, revoked, or max activations hit
    // on a key that validate also rejected (shouldn't normally happen).
    return res.status(401).json({
      valid: false,
      message: activateData.detail || activateData.message || 'Invalid or revoked license key.',
    });

  } catch (error) {
    console.error('License verification failed:', error);
    return res.status(500).json({ error: 'Internal server error verifying license.' });
  }
}
