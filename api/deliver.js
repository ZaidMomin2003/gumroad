import axios from "axios";
import crypto from "crypto";

export default async function handler(req, res) {
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

    // 1. SECURITY: Verify Razorpay Signature
    const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
    const signature = req.headers['x-razorpay-signature'];
    const body = JSON.stringify(req.body);

    const expectedSignature = crypto
        .createHmac('sha256', secret)
        .update(body)
        .digest('hex');

    if (signature !== expectedSignature) {
        console.error("Invalid Signature");
        return res.status(401).send('Invalid Signature');
    }

    // 2. EXTRACT CUSTOMER INFO
    const payment = req.body.payload.payment.entity;

    // We look for the GitHub username in the notes (sent from your Razorpay custom field)
    const githubUsername = payment.notes?.github_username || payment.notes?.["GitHub Username"] || payment.notes?.github;

    if (!githubUsername) {
        console.error("No GitHub Username found in payment notes. Ensure you added the custom field in Razorpay.");
        return res.status(400).send('Missing GitHub Username');
    }

    try {
        // 3. INVITE TO GITHUB REPO (Automated)
        // GitHub sends an email notification automatically when this is triggered
        console.log(`Inviting ${githubUsername} to ${process.env.GITHUB_REPO}...`);

        await axios.put(
            `https://api.github.com/repos/${process.env.GITHUB_REPO}/collaborators/${githubUsername}`,
            { permission: 'pull' }, // 'pull' = read access only
            {
                headers: {
                    'Authorization': `token ${process.env.GITHUB_TOKEN}`,
                    'Accept': 'application/vnd.github.v3+json'
                }
            }
        );

        console.log(`✅ Success! Invitation sent to ${githubUsername}`);
        return res.status(200).json({ status: 'success', message: 'Invitation sent' });

    } catch (error) {
        console.error("GitHub Invitation Error:", error.response?.data || error.message);
        return res.status(500).json({
            status: 'error',
            message: 'Failed to send GitHub invitation',
            details: error.response?.data?.message || error.message
        });
    }
}
