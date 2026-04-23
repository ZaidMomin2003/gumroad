# Cleanmails — Project Context

## What Is Cleanmails?

Cleanmails is a **self-hosted cold email infrastructure platform** sold as a one-time purchase. It positions itself as an alternative to subscription tools like Instantly.ai and Smartlead. Users deploy it on their own Linux VPS and get unlimited email validation, sender rotation, cadence automation, and spintax — with no monthly fees or usage caps.

**Domain:** [https://cleanmails.online](https://cleanmails.online)

---

## Business Model

| Tier | Price | What You Get |
|------|-------|--------------|
| Agency | $497 one-time | Full platform, unlimited usage, free setup assistance |
| SaaS Resale | $1,997 one-time | White-label rights, resell as your own SaaS |
| Infrastructure Setup | $2,999 | 5 verified domains, 50 mailboxes, 1 year hosting, 2-day delivery |
| SaaS Starter (custom build) | $3,999+ | Custom white-label SaaS, React/Next.js, 3 months support |

**Payment processing:** DodoPayments (license key activation), Razorpay (legacy/Indian payments).

**Affiliate program:** $20 per sale, payouts on the 10th and 20th of each month. Signup form stores data in Firebase Firestore.

---

## Core Product Features

1. **Email Validation Engine** — Native SMTP handshake (Port 25), 126k+ disposable domain database, catch-all detection, MX record validation, bulk CSV/XLSX processing.
2. **Sender Rotation** — Unlimited mailbox rotation across domains, built-in SMTP engine (or AWS SES / SendGrid / Gmail relay), blacklist monitoring, dedicated IP reputation.
3. **Cold Email Cadences** — Multi-step sequence automation, timing control, open/click/reply analytics, native tracking (bypasses pixel-blocking).
4. **Spintax Generator** — Multi-level nested spintax, AI-generated openers, subject line A/B rotation, dynamic personalization.
5. **CleanieAI** — AI chatbot (Groq LLaMA 3.3 70B) that walks absolute beginners through VPS deployment step-by-step.

---

## Tech Stack

### Frontend
- **HTML5** multi-page application (20+ pages)
- **CSS3** custom design system (neumorphic style, gold/black/pink palette)
- **Vanilla JavaScript** (no framework)
- **Vite** as build tool (MPA mode)
- **Firebase Firestore** for form data (affiliate signups)
- **PapaParse** for CSV parsing (email validator tool)

### Backend / APIs (Vercel Serverless)
| Endpoint | Purpose |
|----------|---------|
| `/api/chat.js` | CleanieAI chatbot — proxies to Groq API (LLaMA 3.3 70B), rolling 8-message context window |
| `/api/deliver.js` | Razorpay webhook — verifies HMAC-SHA256 signature, auto-invites buyer to private GitHub repo (read-only) |
| `/api/verify-license.js` | License validation — activates/verifies keys against DodoPayments (test + live environments) |

### Infrastructure & Deployment
- **Vercel** hosts the marketing site and serverless APIs
- **Docker / Docker-Compose** for self-hosted installations on user VPS
- **Nginx** reverse proxy + **Let's Encrypt** SSL (auto-configured by installer)
- **AWS S3** for binary/asset storage and download delivery
- **Ubuntu 22.04+** target OS

### Key Dependencies (`package.json`)
- `vite` — build tool
- `firebase` — Firestore SDK
- `axios` — HTTP client (GitHub API calls)
- `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner` — S3 binary delivery

---

## Project Structure

```
├── index.html                          # Main landing page (hero, features, pricing, FAQ)
├── style.css                           # Global design system (1,700+ lines)
├── firebase-config.js                  # Firebase/Firestore init (env vars via Vite)
├── logo.svg                            # Envelope + checkmark brand icon
│
├── api/
│   ├── chat.js                         # CleanieAI chatbot (Groq serverless function)
│   ├── deliver.js                      # Razorpay webhook → GitHub repo invite
│   └── verify-license.js              # DodoPayments license activation
│
├── public/
│   ├── install.sh                      # One-command enterprise installer script
│   └── screenshots/                    # Dashboard preview images
│
├── vite.config.js                      # MPA config, route mapping, local API middleware
├── vercel.json                         # Clean URLs enabled
├── package.json                        # Dependencies and scripts
├── .env                                # Secrets (Firebase, GitHub, Razorpay, Groq, AWS)
└── .gitignore                          # Ignores node_modules, dist, .env
```

### HTML Pages by Category

**Marketing & Landing**
- `index.html` — Main landing page with hero, feature grid, pricing, FAQ, newsletter
- `email-validation.html` — Email validation feature showcase
- `sender-rotation.html` — Sender rotation feature showcase
- `cold-email-cadence.html` — Cadence automation feature showcase
- `spintax-generator.html` — Spintax engine feature showcase
- `millionmails.html` — Resource hub / content page

**Comparison Pages**
- `cleanmails-vs-instantly.html` — Head-to-head vs Instantly.ai
- `cleanmails-vs-smartlead.html` — Head-to-head vs Smartlead.ai

**Product & Services**
- `infrastructure.html` — $2,999 enterprise infrastructure setup offering
- `saas-starter.html` — $3,999+ custom white-label SaaS build service
- `CleanieAI.html` — AI deployment assistant chatbot interface
- `docs.html` — Deployment guide with interactive installer command generator
- `developer.html` — Developer profile page (Zaid)
- `verify.html` — Free email validator web tool (80% accuracy, upsell to paid)

**Transaction Flow**
- `success.html` — Post-purchase setup instructions + installer generator
- `success-enterprise.html` — Enterprise license activation page
- `success-v1-x8fk2m9s7q5p4r3w.html` — Alternative/legacy success page
- `cancel.html` — Payment cancellation page

**Other**
- `affiliate.html` — Affiliate program signup (Firebase form)
- `support.html` — Support resources and FAQ
- `privacy.html` — Privacy policy
- `terms.html` — Terms of service (1-month money-back guarantee)
- `404.html` — Custom error page

---

## Installation Flow (End User)

The buyer receives a license key after purchase. Deployment is a single command:

```bash
curl -sSL https://cleanmails.online/install.sh | bash -s -- --key {LICENSE_KEY} --domain {YOUR_DOMAIN}
```

**What the installer does (`public/install.sh`):**
1. Parses `--key` and `--domain` arguments
2. Installs dependencies (jq, curl, unzip, nginx, certbot)
3. Activates license with DodoPayments (machine-binding via `/etc/machine-id` for anti-piracy)
4. Downloads the application binary from AWS S3 (pre-signed URL)
5. Creates a systemd service for auto-start
6. Configures Nginx reverse proxy
7. Generates Let's Encrypt SSL certificate
8. Reminds user to configure rDNS/PTR records for email deliverability

---

## Design System

| Token | Value |
|-------|-------|
| Primary | `#FFD700` (gold) |
| Accent | `#FF90E8` (pink) |
| Accent Hover | `#ff70e0` |
| Text | `#1A1A1A` |
| Background | `#FAFAFA` |
| Muted Text | `#666666` |
| Border | `3px solid #000` |
| Border Radius | `24px` (standard), `32px`–`40px` (cards) |
| Shadow | `6px 6px 0 #000` (neumorphic) |
| Font | Inter (system-ui fallback) |
| Headings | weight 800–900, letter-spacing -0.03em |

**UI patterns:** Neumorphic cards with bold black shadows, hover animations (`translate -3px -3px`), smooth transitions (`0.2s cubic-bezier`), gold accent badges, pink CTA buttons.

---

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `RAZORPAY_WEBHOOK_SECRET` | Webhook signature verification |
| `GITHUB_TOKEN` | Auto-invite buyers to private repo |
| `GITHUB_REPO` | Target repo for collaborator invites |
| `VITE_FIREBASE_*` | Firebase/Firestore config (6 vars) |
| `GROQ_API` | Groq API key for CleanieAI chatbot |
| `MY_AWS_*` | AWS S3 credentials for binary delivery |
| `MY_S3_BUCKET` | S3 bucket name |
| `DODO_PRIVATE_KEY` | DodoPayments license API key |

---

## Analytics & SEO

- **Google Analytics:** `G-QWXBBLS661`
- **Schema.org:** SoftwareApplication, FAQPage structured data
- **Open Graph + Twitter Cards** on all marketing pages
- **Product Hunt** integration badge on landing page
- **Canonical URLs** set per page

---

## Competitive Positioning

| Competitor | Their Model | Cleanmails Advantage |
|------------|-------------|---------------------|
| Instantly.ai | $97/month subscription | $497 one-time, unlimited |
| Smartlead.ai | Per-workspace fees | No workspace limits |
| ZeroBounce | $350–500/month validation | Validation included free |
| Google Workspace | $3,600/year for mailboxes | Mailboxes included |

**Key messages:** "Stop paying monthly," "Own your infrastructure," "Unlimited everything," "Private fortress," "No monthly tax."

---

## Revenue Streams

1. **Direct license sales** — $497 (Agency) / $1,997 (SaaS resale)
2. **Infrastructure setup service** — $2,999
3. **Custom SaaS builds** — $3,999+
4. **Affiliate commissions** — $20 per referral
5. **Optional white-glove setup** — $50

---

## Developer

**Zaid** — Independent developer based in India. Builds and maintains the entire platform solo. Handles support, infrastructure setup, and custom SaaS builds.

---

## Notes & Technical Debt

- Large monolithic `style.css` (1,700+ lines) — could benefit from modularization
- Some pages have extensive inline styles alongside the shared stylesheet
- No TypeScript — vanilla JS throughout
- Secrets present in `.env` file (should only live in CI/CD environment variables)
- Mixed payment providers (DodoPayments for licenses, Razorpay for legacy flow)
- No automated test suite
