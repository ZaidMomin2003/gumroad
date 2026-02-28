import { defineConfig, loadEnv } from 'vite';
import { resolve } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');

  return {
    appType: 'mpa',
    build: {
      rollupOptions: {
        input: {
          main: resolve(__dirname, 'index.html'),
          terms: resolve(__dirname, 'terms.html'),
          privacy: resolve(__dirname, 'privacy.html'),
          support: resolve(__dirname, 'support.html'),
          developer: resolve(__dirname, 'developer.html'),
          docs: resolve(__dirname, 'docs.html'),
          success: resolve(__dirname, 'success-v1-x8fk2m9s7q5p4r3w.html'),
          cancel: resolve(__dirname, 'cancel.html'),
          affiliate: resolve(__dirname, 'affiliate.html'),
          millionmails: resolve(__dirname, 'millionmails.html'),
          error: resolve(__dirname, '404.html'),
          cleanie: resolve(__dirname, 'CleanieAI.html'),
          infrastructure: resolve(__dirname, 'infrastructure.html'),
          saasstarter: resolve(__dirname, 'saas-starter.html'),
        },
      },
    },
    plugins: [
      {
        name: 'api-middleware',
        configureServer(server) {
          server.middlewares.use(async (req, res, next) => {
            // 1. Handle CleanieAI Chat API locally
            if (req.url === '/api/chat' && req.method === 'POST') {
              let body = '';
              req.on('data', chunk => { body += chunk; });
              req.on('end', async () => {
                try {
                  const { messages } = JSON.parse(body);
                  const rollingMessages = messages.slice(-8);
                  const GROQ_API_KEY = env.GROQ_API || env.GROQ_API_KEY;

                  if (!GROQ_API_KEY) {
                    res.statusCode = 500;
                    res.end(JSON.stringify({ error: 'Local GROQ_API not found' }));
                    return;
                  }

                  const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
                    method: 'POST',
                    headers: {
                      'Authorization': `Bearer ${GROQ_API_KEY}`,
                      'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                      model: 'llama-3.3-70b-versatile',
                      messages: [
                        {
                          role: 'system', content: `You are CleanieAI, the official deployment assistant for Cleanmails.
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

Always start with: "Welcome! Don't worry if you've never done this before. Let's start with Step 1: GitHub."` },
                        ...rollingMessages
                      ],
                      temperature: 0.2,
                    }),
                  });

                  const data = await groqResponse.json();
                  res.setHeader('Content-Type', 'application/json');
                  res.end(JSON.stringify(data));
                } catch (e) {
                  res.statusCode = 500;
                  res.end(JSON.stringify({ error: e.message }));
                }
              });
              return;
            }

            // 2. Handle MPA Route Mapping
            const url = req.url.split('?')[0];
            if (url !== '/' && !url.includes('.') && !url.startsWith('/@') && !url.startsWith('/node_modules') && !url.startsWith('/api')) {
              const routeMap = {
                '/terms': '/terms.html',
                '/privacy': '/privacy.html',
                '/support': '/support.html',
                '/developer': '/developer.html',
                '/docs': '/docs.html',
                '/success': '/success-v1-x8fk2m9s7q5p4r3w.html',
                '/cancel': '/cancel.html',
                '/affiliate': '/affiliate.html',
                '/millionmails': '/millionmails.html',
                '/CleanieAI': '/CleanieAI.html',
                '/infrastructure': '/infrastructure.html',
                '/saas-starter': '/saas-starter.html'
              };

              if (routeMap[url]) {
                req.url = routeMap[url];
              } else {
                req.url = '/404.html';
              }
            }
            next();
          });
        },
      },
    ],
  };
});
