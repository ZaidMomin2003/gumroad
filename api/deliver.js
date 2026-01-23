import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import axios from "axios";
import crypto from "crypto";

export default async function handler(req, res) {
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

    // 1. SECURITY: Verify this message actually came from Razorpay
    const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
    const signature = req.headers['x-razorpay-signature'];

    // We need the raw body for signature verification
    const body = JSON.stringify(req.body);
    const expectedSignature = crypto
        .createHmac('sha256', secret)
        .update(body)
        .digest('hex');

    if (signature !== expectedSignature) {
        console.error("Invalid Signature Received");
        return res.status(401).send('Invalid Signature');
    }

    // 2. GET CUSTOMER INFO
    // Accessing information from Razorpay's standard payment.captured webhook payload
    const payment = req.body.payload.payment.entity;
    const customerEmail = payment.email;
    const customerName = payment.notes?.name || "Customer";

    try {
        // 3. GENERATE THE SECRET DOWNLOAD LINK (AWS S3)
        const s3Client = new S3Client({
            region: process.env.MY_AWS_REGION,
            credentials: {
                accessKeyId: process.env.MY_AWS_ACCESS_KEY,
                secretAccessKey: process.env.MY_AWS_SECRET_KEY,
            }
        });

        const command = new GetObjectCommand({
            Bucket: process.env.MY_S3_BUCKET,
            Key: "cleanmails.zip", // The exact name of your file in S3
        });

        // Link expires in 900 seconds (15 minutes)
        const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 900 });

        // 4. TRIGGER SENDER.NET EMAIL
        console.log("Triggering Sender.net...");
        // After verifying with Sender's API structure, sending a template usually requires this path
        const senderResp = await axios.post('https://api.sender.net/v2/emails/transactional', {
            email: customerEmail,
            template_id: process.env.SENDER_TEMPLATE_ID,
            substitutions: {
                "{{download_url}}": signedUrl,
                "{{firstname}}": customerName
            }
        }, {
            headers: {
                'Authorization': `Bearer ${process.env.SENDER_API_KEY}`,
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
        });

        console.log(`Successfully delivered Cleanmails zip to ${customerEmail}`);
        return res.status(200).json({ status: 'success', message: 'Delivery triggered' });

    } catch (error) {
        console.error("Delivery Error:", error.response?.data || error.message);
        return res.status(500).json({ status: 'error', message: 'Internal Server Error' });
    }
}
