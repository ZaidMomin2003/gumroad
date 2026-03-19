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

  try {
    // Determine whether to use Live or Test environment based on the key prefix
    const isTest = DODO_PRIVATE_KEY.startsWith('test_');
    const apiUrl = isTest 
      ? 'https://test.dodopayments.com/licenses/activate'
      : 'https://live.dodopayments.com/licenses/activate';

    const dodoResponse = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        license_key: license_key,
        name: instance_name || 'Cleanmails Instance',
      })
    });

    const data = await dodoResponse.json();

    if (dodoResponse.status === 201 || (dodoResponse.ok && data.id)) {
      // The key is valid and successfully activated/verified!
      return res.status(200).json({
        valid: true,
        message: 'License is valid and securely activated.',
        license_data: data
      });
    } else {
      // Dodo indicates invalid, expired, or max activations reached
      return res.status(dodoResponse.status === 404 ? 404 : 401).json({
        valid: false,
        message: data.detail || data.message || 'Invalid or revoked license key.'
      });
    }

  } catch (error) {
    console.error('License verification failed:', error);
    return res.status(500).json({ error: 'Internal server error verifying license.' });
  }
}
