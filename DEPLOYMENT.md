# Production Deployment Guide

This guide walks through deploying the Election Assistant to production with security, performance, and reliability best practices.

---

## Pre-Deployment Checklist

```bash
# 1. Run full test suite
npm test -- --ci --coverage

# 2. Lint code
npm run lint

# 3. Check dependencies
npm audit

# 4. Build and test build
npm run build
npm run build && npm start

# 5. Test accessibility
npm run a11y:test

# 6. Performance audit
npm run lighthouse
```

---

## Environment Configuration

### Create `.env.production`

```bash
# Google OAuth
REACT_APP_GOOGLE_CLIENT_ID=xxxxxx.apps.googleusercontent.com
REACT_APP_GOOGLE_SHEET_ID=your-sheet-id

# API endpoints
REACT_APP_API_BASE_URL=https://api.election-assistant.com
REACT_APP_ENVIRONMENT=production

# Monitoring
REACT_APP_SENTRY_DSN=https://xxxxx@xxxxx.ingest.sentry.io/xxxxx
REACT_APP_GA_ID=G-XXXXXXXXXX

# Feature flags
REACT_APP_GOOGLE_SYNC_ENABLED=true
REACT_APP_CALENDAR_INTEGRATION_ENABLED=true
```

### Secrets Management

**Never commit secrets!**

1. **Use environment variable services**
   - Vercel: Settings → Environment Variables
   - GitHub Actions: Settings → Secrets
   - AWS: Systems Manager Parameter Store
   - Azure: Key Vault

2. **Example (GitHub Actions)**
   ```yaml
   # .github/workflows/deploy.yml
   env:
     REACT_APP_GOOGLE_CLIENT_ID: ${{ secrets.GOOGLE_CLIENT_ID }}
     REACT_APP_SENTRY_DSN: ${{ secrets.SENTRY_DSN }}
   ```

3. **Example (Vercel)**
   ```bash
   vercel env add REACT_APP_GOOGLE_CLIENT_ID
   # Prompts for value, stores securely
   ```

---

## Google Services Production Setup

### 1. Google Cloud Console Setup

```bash
# Step 1: Create project
1. Go to https://console.cloud.google.com
2. Click "Select a Project"
3. New Project → "Election Assistant"
4. Wait for creation (~2 min)

# Step 2: Enable APIs
1. Search "Google Drive API" → Enable
2. Search "Google Calendar API" → Enable
3. Search "Google Sheets API" → Enable

# Step 3: Create OAuth credentials
1. APIs & Services → Credentials
2. Create Credentials → OAuth Client ID
3. Application type: Web application
4. Add Authorized redirect URIs:
   - https://election-assistant.example.com
   - https://election-assistant.example.com/callback
   - https://www.election-assistant.example.com
5. Create
6. Download JSON, save securely
```

### 2. OAuth Consent Screen

```bash
# Set up user consent
1. OAuth consent screen (left menu)
2. User type: External (for initial testing)
3. Add required scopes:
   - https://www.googleapis.com/auth/drive.file
   - https://www.googleapis.com/auth/calendar.events
   - https://www.googleapis.com/auth/spreadsheets.readonly
4. Add test users (your email)
5. Publish (after testing)
```

### 3. Application Implementation

```javascript
// src/services/GoogleServices.js
import { google } from 'googleapis';

class ProductionGoogleServices {
  constructor() {
    this.drive = null;
    this.calendar = null;
    this.sheets = null;
  }

  async initialize() {
    // Load Google API script
    return new Promise((resolve) => {
      const script = document.createElement('script');
      script.src = 'https://apis.google.com/js/api.js';
      script.onload = () => {
        gapi.load('client', async () => {
          await gapi.client.init({
            apiKey: process.env.REACT_APP_GOOGLE_API_KEY,
            clientId: process.env.REACT_APP_GOOGLE_CLIENT_ID,
            scope: [
              'https://www.googleapis.com/auth/drive.file',
              'https://www.googleapis.com/auth/calendar.events',
              'https://www.googleapis.com/auth/spreadsheets.readonly'
            ].join(' ')
          });
          
          this.drive = gapi.client.drive;
          this.calendar = gapi.client.calendar;
          this.sheets = gapi.client.sheets;
          
          resolve();
        });
      };
      document.body.appendChild(script);
    });
  }

  async authenticate() {
    const auth2 = gapi.auth2.getAuthInstance();
    
    if (!auth2.isSignedIn.get()) {
      return auth2.signIn();
    }
    
    return auth2.currentUser.get();
  }

  async saveLearningPath(data) {
    const user = gapi.auth2.getAuthInstance().currentUser.get();
    
    if (!user.isSignedIn()) {
      throw new Error('User not authenticated');
    }

    const metadata = {
      name: 'election-learning-' + Date.now() + '.json',
      mimeType: 'application/json'
    };

    const file = new Blob([JSON.stringify(data)], { type: 'application/json' });
    
    const form = new FormData();
    form.append('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }));
    form.append('file', file);

    return fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + user.getAuthResponse().id_token
      },
      body: form
    }).then(r => r.json());
  }

  async addToCalendar(eventData) {
    const user = gapi.auth2.getAuthInstance().currentUser.get();
    
    if (!user.isSignedIn()) {
      throw new Error('User not authenticated');
    }

    return gapi.client.calendar.events.insert({
      calendarId: 'primary',
      resource: {
        summary: eventData.title,
        description: eventData.description,
        start: {
          dateTime: eventData.date,
          timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone
        },
        reminders: {
          useDefault: false,
          overrides: [
            { method: 'email', minutes: 24 * 60 },
            { method: 'popup', minutes: 30 }
          ]
        }
      }
    });
  }
}

export default ProductionGoogleServices;
```

---

## Security Hardening

### 1. HTTP Security Headers

```javascript
// vercel.json or server headers config
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "X-Content-Type-Options",
          "value": "nosniff"
        },
        {
          "key": "X-Frame-Options",
          "value": "DENY"
        },
        {
          "key": "X-XSS-Protection",
          "value": "1; mode=block"
        },
        {
          "key": "Referrer-Policy",
          "value": "strict-origin-when-cross-origin"
        },
        {
          "key": "Permissions-Policy",
          "value": "geolocation=(), microphone=(), camera=()"
        },
        {
          "key": "Content-Security-Policy",
          "value": "default-src 'self'; script-src 'self' apis.google.com cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline'; font-src 'self' fonts.googleapis.com; frame-ancestors 'none'; upgrade-insecure-requests"
        }
      ]
    }
  ]
}
```

### 2. HTTPS/SSL Configuration

```bash
# Vercel: Automatic HTTPS with auto-renewal
# GitHub Pages: Automatic HTTPS
# Self-hosted: Use Let's Encrypt with Certbot

# For self-hosted:
sudo certbot certonly --standalone -d election-assistant.example.com
# Renews automatically with systemd timer
```

### 3. Rate Limiting

```javascript
// Backend middleware (Node.js/Express)
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests, please try again later.'
});

app.use('/api/', limiter);
```

### 4. Input Validation

```javascript
// src/utils/validation.js
export function sanitizeInput(input) {
  if (typeof input !== 'string') return '';
  
  // Remove potentially dangerous characters
  return input
    .replace(/[<>]/g, '')
    .replace(/javascript:/gi, '')
    .substring(0, 1000); // Max length
}

export function validateEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

export function validateDate(date) {
  return !isNaN(Date.parse(date));
}
```

### 5. Content Security Policy

```javascript
// In server middleware or vercel.json
const cspHeader = `
  default-src 'self';
  script-src 'self' apis.google.com cdnjs.cloudflare.com;
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https:;
  font-src 'self' fonts.googleapis.com;
  connect-src 'self' googleapis.com www.googleapis.com;
  frame-ancestors 'none';
  form-action 'self';
  base-uri 'self';
  upgrade-insecure-requests;
`;
```

---

## Deployment Strategies

### Option 1: Vercel (Recommended)

```bash
# Install Vercel CLI
npm i -g vercel

# Login
vercel login

# Link project
vercel link

# Configure environment variables
vercel env add REACT_APP_GOOGLE_CLIENT_ID
# (Repeat for all secrets)

# Deploy
vercel deploy --prod

# Automatic:
# - HTTPS with auto-renewal
# - Global CDN
# - Auto-scaling
# - Zero-config database
```

**vercel.json Configuration**

```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "build",
  "env": {
    "REACT_APP_GOOGLE_CLIENT_ID": "@google_client_id",
    "REACT_APP_SENTRY_DSN": "@sentry_dsn"
  },
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=3600, must-revalidate"
        }
      ]
    }
  ],
  "rewrites": [
    {
      "source": "/:path*",
      "destination": "/index.html"
    }
  ]
}
```

### Option 2: GitHub Pages

```bash
# Install gh-pages
npm install gh-pages --save-dev

# Add deploy script to package.json
"deploy": "npm run build && gh-pages -d build"

# Deploy
npm run deploy
```

**GitHub Actions Auto-Deploy**

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Node
        uses: actions/setup-node@v2
        with:
          node-version: '18'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run tests
        run: npm test -- --ci
      
      - name: Build
        run: npm run build
      
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./build
```

### Option 3: Docker to Cloud Run

```dockerfile
# Dockerfile
FROM node:18-alpine as builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:18-alpine
WORKDIR /app
RUN npm i -g serve
COPY --from=builder /app/build ./build
EXPOSE 3000
CMD ["serve", "-s", "build", "-l", "3000"]
```

```bash
# Build and deploy to Google Cloud Run
docker build -t election-assistant:latest .
docker tag election-assistant:latest gcr.io/PROJECT_ID/election-assistant:latest
docker push gcr.io/PROJECT_ID/election-assistant:latest

gcloud run deploy election-assistant \
  --image gcr.io/PROJECT_ID/election-assistant:latest \
  --platform managed \
  --region us-central1 \
  --set-env-vars REACT_APP_GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
```

---

## Monitoring & Analytics

### 1. Error Tracking (Sentry)

```javascript
// src/index.js
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: process.env.REACT_APP_SENTRY_DSN,
  environment: process.env.REACT_APP_ENVIRONMENT,
  tracesSampleRate: 0.1,
  beforeSend(event) {
    // Don't send personal data
    if (event.request) {
      delete event.request.cookies;
      delete event.request.headers;
    }
    return event;
  }
});

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <Sentry.ErrorBoundary fallback={<div>Error loading app</div>}>
    <App />
  </Sentry.ErrorBoundary>
);
```

### 2. Performance Monitoring (Web Vitals)

```javascript
// src/index.js
import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals';

// Send metrics to analytics
getCLS(console.log);
getFID(console.log);
getFCP(console.log);
getLCP(console.log);
getTTFB(console.log);
```

### 3. Google Analytics

```html
<!-- public/index.html -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXXXXXX"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'G-XXXXXXXXXX');
</script>
```

```javascript
// Track events
window.gtag?.('event', 'select_role', {
  user_role: selectedRole
});

window.gtag?.('event', 'expand_timeline', {
  timeline_item: itemId
});
```

### 4. Application Monitoring (PM2)

```yaml
# ecosystem.config.js
module.exports = {
  apps: [{
    name: 'election-assistant',
    script: 'npm',
    args: 'start',
    instances: 'max',
    exec_mode: 'cluster',
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/log/election-assistant-error.log',
    out_file: '/var/log/election-assistant-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss'
  }]
};
```

```bash
# Start with PM2
pm2 start ecosystem.config.js
pm2 monit  # Monitor
pm2 logs   # View logs
```

---

## Backup & Disaster Recovery

### 1. Database Backups (if using)

```bash
# Daily automated backups
0 2 * * * mongodump --uri="mongodb+srv://..." --out=/backups/$(date +\%Y-\%m-\%d)

# Test restore monthly
mongorestore --uri="mongodb+srv://..." /backups/YYYY-MM-DD
```

### 2. Google Drive Backups

```javascript
// Automatic backup of user data
setInterval(async () => {
  const userData = {
    role: selectedRole,
    completedItems: completedItems,
    timestamp: new Date().toISOString()
  };
  
  await googleAPI.saveLearningPath(userData);
  console.log('Backup completed');
}, 24 * 60 * 60 * 1000); // Daily
```

### 3. Code Repository Backups

```bash
# Mirror to secondary repo
git remote add backup https://github.com/backup/election-assistant.git
git push backup main

# Daily via cron
0 3 * * * cd /home/git/election-assistant && git push backup main
```

---

## Scaling & Performance

### 1. CDN Configuration

```javascript
// vercel.json or nginx config
{
  "headers": [
    {
      "source": "/(.*\.(js|css|png|jpg|svg|woff|woff2))",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    },
    {
      "source": "/",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=3600, must-revalidate"
        }
      ]
    }
  ]
}
```

### 2. Image Optimization

```javascript
// Use next/image or similar
import Image from 'next/image';

<Image
  src="/election-icon.svg"
  alt="Election icon"
  width={24}
  height={24}
  priority
/>
```

### 3. Code Splitting

```javascript
// React lazy loading for future features
const VotingLocationFinder = React.lazy(() => import('./features/VotingLocationFinder'));

<Suspense fallback={<div>Loading...</div>}>
  <VotingLocationFinder />
</Suspense>
```

---

## Maintenance & Updates

### 1. Dependency Updates

```bash
# Check for updates
npm outdated

# Update safely
npm update

# Update with breaking changes (carefully)
npm install package@latest

# Audit after updates
npm audit
```

### 2. Security Patches

```bash
# Automated updates with dependabot
# Add to .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: daily
    pull-requests:
      auto-merge:
        enabled: true
```

### 3. Monitoring Updates

```bash
# Weekly security scan
npm audit --audit-level=moderate

# Monthly dependency audit
npm list | grep "WARN"
```

---

## Troubleshooting

### Common Issues

**Issue: Google OAuth fails in production**
```
Solution: 
1. Check redirect URIs match exactly
2. Ensure OAuth consent screen is published
3. Verify Client ID is correct
4. Check HTTPS is enabled
```

**Issue: Performance degrades over time**
```
Solution:
1. Check memory usage: pm2 monit
2. Restart application: pm2 restart app
3. Check database indexes
4. Clear CDN cache
```

**Issue: High error rate**
```
Solution:
1. Check Sentry dashboard for patterns
2. Review application logs
3. Check Google API quota
4. Verify database connectivity
```

---

## Post-Deployment Checklist

- ✅ HTTPS working and valid certificate
- ✅ Security headers present (CSP, X-Frame-Options, etc.)
- ✅ Google OAuth functioning
- ✅ Analytics tracking working
- ✅ Error tracking (Sentry) receiving errors
- ✅ Performance metrics acceptable (< 3s load time)
- ✅ Accessibility audit passing
- ✅ All tests passing in production
- ✅ Monitoring and alerts configured
- ✅ Backup system working
- ✅ Team trained on deployment process
- ✅ Runbook documented for on-call engineers

---

## Support & Documentation

- Production Runbook: [link]
- Incident Response Plan: [link]
- Team Wiki: [link]
- Status Page: https://status.election-assistant.com

---

**Last Updated:** 2024
**Maintained By:** Election Assistant Team
