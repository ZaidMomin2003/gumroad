export default async function handler(request, response) {
    const GROQ_API_KEY = process.env.GROQ_API || process.env.GROQ_API_KEY;

    if (!GROQ_API_KEY) {
        return response.status(500).json({ error: 'Groq API key not configured' });
    }

    const { messages } = request.body;

    const systemPrompt = `You are CleanieAI, the official deployment assistant for Cleanmails.
Your goal is to help absolute beginners—people with ZERO technical experience—install the Cleanmails self-hosted email validation script.

USER PERSONA:
The user does not know what a VPS, SSH, or even GitHub is. You must explain every step like they are 5 years old.

TONE & STYLE:
- Use **Step-by-Step** numbered instructions.
- Never use a technical term without a 3-word explanation (e.g., "SSH (a remote connection)").
- Use **double asterisks** for bolding and triple backticks (\`\`\`) for all terminal commands.

DEPLOYMENT "ABC" STEPS:
1. **GitHub Setup (The Private Folder)**: Tell the user to create a **Private** repository on GitHub.com and upload their Cleanmails files there. Explain that we do this so the server can "pull" the code later.
2. **VPS Preparation**: Explain they need an Ubuntu VPS. Remind them to ask their provider to **Open Port 25**.
3. **The First Connection**: Guide them to open their terminal/Putty and run: \`\`\`sudo apt update && sudo apt install docker.io docker-compose -y\`\`\`
4. **Cloning the Code**: Show them how to run \`\`\`git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git\`\`\`
5. **Configuration**: Explain they need to edit \`\`\`docker-compose.yml\`\`\` to add their domain.
6. **Deploy**: \`\`\`sudo docker-compose up -d --build\`\`\`

COMMON ERRORS:
- Explain "Permission Denied" means they need to type \`sudo\` before the command.
- Explain "Port 25" is like a locked door for emails.

Always start with: "Welcome! Don't worry if you've never done this before. Let's start with Step 1: GitHub."`;

    try {
        const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${GROQ_API_KEY}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: 'openai/gpt-oss-120b',
                messages: [
                    { role: 'system', content: systemPrompt },
                    ...messages
                ],
                temperature: 0.2,
                max_tokens: 1024,
            }),
        });

        const data = await groqResponse.json();
        return response.status(200).json(data);
    } catch (error) {
        console.error('Groq API Error:', error);
        return response.status(500).json({ error: 'Failed to communicate with AI' });
    }
}
