# SMTP Server

> SMTP server application for sending emails to users from your prepared
> server via auto-install Bash scripts and an API gateway interface.

[Русская версия](README_RU.md)

A turn-key bundle that does three things:

1. Provisions a hardened **postfix** SMTP relay on a fresh Ubuntu VPS via
   the scripts in [`bash_utils/`](bash_utils/) (TLS via Let's Encrypt,
   DKIM via OpenDKIM).
2. Exposes a NestJS **HTTP API gateway** that accepts mail-send requests
   protected by an `x-api-key` header and relays them through the local
   postfix using **nodemailer**. The gateway is published to the public
   internet through **nginx + Let's Encrypt** as
   `https://api.example.com`.
3. Persists every send attempt to **PostgreSQL** (recipient, subject,
   status, message id, error, timestamp) for full auditability.

---

## Table of contents

- [Architecture](#architecture)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Provisioning the SMTP server (bash_utils)](#provisioning-the-smtp-server-bash_utils)
- [Publishing the API over HTTPS (nginx)](#publishing-the-api-over-https-nginx)
- [DNS records (SPF / DKIM / DMARC / PTR)](#dns-records-spf--dkim--dmarc--ptr)
- [Environment variables](#environment-variables)
- [Running the API](#running-the-api)
  - [Local (npm)](#local-npm)
  - [Docker Compose](#docker-compose)
- [API reference](#api-reference)
- [Database schema](#database-schema)
- [GitHub Actions deploy](#github-actions-deploy)
- [Project layout](#project-layout)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Architecture

```
                       +--------------------+
   HTTPS               |  Your application  |
  (x-api-key)          |  (backend / cron)  |
                       +---------+----------+
                                 |
                                 | POST https://api.example.com/api/emails/send
                                 v
+----------------------------------------------------------------+
|                            VPS                                 |
|                                                                |
|   +--------------+   :443/:80   +-----------------------+      |
|   |    nginx     | <----------- |    Public internet    |      |
|   | (LetsEncrypt)|              +-----------------------+      |
|   +------+-------+                                             |
|          | proxy_pass http://127.0.0.1:3001                    |
|          v                                                     |
|   +--------------------------+                                 |
|   |    NestJS API gateway    |                                 |
|   |  ApiKeyGuard             |                                 |
|   |  -> EmailController      |                                 |
|   |  -> EmailService -------- writes ---> +---------------+   |
|   |       |                                |  PostgreSQL  |   |
|   |       v                                |  email_logs  |   |
|   |  MailerService (nodemailer)            +---------------+   |
|   |       |                                                    |
|   |       v 127.0.0.1:25                                       |
|   |  +-----------------+      :25/:465/:587                    |
|   |  |   postfix +     | -------------------> Internet (recipients)
|   |  |   OpenDKIM      |                                       |
|   |  +-----------------+                                       |
+----------------------------------------------------------------+
```

The API process listens **only on `127.0.0.1`** in production. Nginx is
the only public-facing component, so the `x-api-key` header is always
sent over TLS.

---

## Requirements

| Component                | Version           |
| ------------------------ | ----------------- |
| Ubuntu VPS               | 22.04 LTS+        |
| Node.js                  | 20.x              |
| PostgreSQL               | 14+               |
| A registered domain name | with DNS access   |
| Open ports on the VPS    | 25, 80, 443, 465, 587 |

You also need a public IPv4 with a clean reputation and PTR (reverse DNS)
that resolves back to the SMTP host name. Without these, major providers
(Gmail, Outlook, etc.) will reject or quarantine your mail.

---

## Quick start

```bash
# 1. On the VPS, as root — install postfix, request TLS, sign DKIM
sudo bash bash_utils/setup_smtp_server.sh
sudo bash bash_utils/sign_dkim_domain.sh

# 2. Publish nginx + HTTPS for the API gateway (api.example.com)
sudo bash bash_utils/setup_api_gateway_nginx.sh

# 3. Publish DKIM TXT + SPF + DMARC at your DNS provider
#    (the DKIM record is printed by sign_dkim_domain.sh)

# 4. Clone the repo, configure env, run via docker-compose
git clone https://github.com/yunusmi/smtp_server.git /var/www/smtp_server
cd /var/www/smtp_server
cp .env.example .env
nano .env       # fill API_KEY, DB_*, MAIL_FROM
docker compose up -d --build

# 5. Send a test email
curl -X POST https://api.example.com/api/emails/send \
  -H "Content-Type: application/json" \
  -H "x-api-key: <your-API_KEY>" \
  -d '{"emails":["you@gmail.com"],"subject":"Hello","body":"It works","is_html":false}'
```

---

## Provisioning the SMTP server (bash_utils)

All scripts must be run as **root** on a fresh Ubuntu VPS.

| Script                                                            | Purpose                                                                                                                                                                                              |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`setup_smtp_server.sh`](bash_utils/setup_smtp_server.sh)         | Installs postfix + mailutils + certbot, asks for `DOMAIN_NAME` and `SMTP_HOST`, requests a Let's Encrypt cert, writes `/etc/postfix/main.cf`, opens 25/465/587 in iptables, persists the rules.       |
| [`sign_dkim_domain.sh`](bash_utils/sign_dkim_domain.sh)           | Installs OpenDKIM, generates a key for `$SMTP_HOST`, wires it into postfix as a milter, prints the TXT record you must publish in DNS.                                                                |
| [`setup_api_gateway_nginx.sh`](bash_utils/setup_api_gateway_nginx.sh) | Asks for `API_HOST` (e.g. `api.example.com`), installs nginx and the certbot nginx plugin, writes a reverse-proxy server block to `127.0.0.1:3001`, requests an HTTPS cert and enables auto-redirect HTTP→HTTPS. |
| [`setup_ssl_cert.sh`](bash_utils/setup_ssl_cert.sh)               | Re-issues the Let's Encrypt certificate for the SMTP host (e.g. after switching domains) and reloads postfix.                                                                                          |
| [`update_ssl_cert.sh`](bash_utils/update_ssl_cert.sh)             | Renews the SMTP cert via `certbot renew` and reloads postfix. The API HTTPS cert is renewed automatically by `certbot.timer`.                                                                          |
| [`uninstall_smtp_server.sh`](bash_utils/uninstall_smtp_server.sh) | Purges postfix, certbot, opendkim, nginx and the certbot nginx plugin; removes all generated config and env entries.                                                                                   |

The first script asks two questions:

- **DOMAIN_NAME** — your apex domain, e.g. `example.com`
- **SMTP_HOST** — the FQDN of this VPS, e.g. `smtp.example.com`. There must be an `A` record pointing it at the VPS public IP **before** running the script (certbot needs HTTP-01 to succeed).

After both scripts finish, postfix listens on `25`, `465` and `587`,
signs outgoing mail with DKIM, and is ready to relay anything submitted
from `127.0.0.1` without authentication.

---

## Publishing the API over HTTPS (nginx)

The NestJS gateway listens on plain HTTP on `127.0.0.1:3001`. You should
**never** expose port `3001` directly to the internet — the API key
would travel unencrypted. Instead, run
[`setup_api_gateway_nginx.sh`](bash_utils/setup_api_gateway_nginx.sh):

```bash
sudo bash bash_utils/setup_api_gateway_nginx.sh
# Type your API gateway hostname (ex. api.example.com): api.example.com
```

What it does:

1. Installs `nginx` and `python3-certbot-nginx`.
2. Writes `/etc/nginx/sites-available/api-gateway` — a server block that
   proxies `https://$API_HOST/` to `http://127.0.0.1:3001/` and forwards
   `Host`, `X-Real-IP`, `X-Forwarded-For` and `X-Forwarded-Proto`.
3. Disables the default nginx site, runs `nginx -t`, reloads nginx.
4. Opens ports `80` and `443` in iptables and persists the rules.
5. Runs `certbot --nginx --redirect -d $API_HOST` — this issues the
   certificate, edits the server block to add the TLS listener and
   forces HTTP → HTTPS redirection.
6. Enables `nginx` and `certbot.timer` (auto-renewal every 12h).

**Prerequisite:** an `A` record `api.example.com → <VPS_IPv4>` must be
published in DNS *before* you run the script — certbot's HTTP-01
challenge needs to resolve.

After it finishes, your gateway is reachable at `https://api.example.com`
and the certificate auto-renews indefinitely.

---

## DNS records (SPF / DKIM / DMARC / PTR)

Even with a perfect server, mail will land in spam unless these records
exist on the domain in `MAIL_FROM`:

```
; A record for the SMTP host
smtp.example.com.   IN  A     <VPS_IPv4>

; A record for the API gateway
api.example.com.    IN  A     <VPS_IPv4>

; SPF — authorise the VPS to send for the domain
example.com.        IN  TXT   "v=spf1 mx a:smtp.example.com ~all"

; DKIM — the public key printed by sign_dkim_domain.sh.
; The selector is the part before "._domainkey." (the VPS hostname).
smtp._domainkey.example.com.  IN  TXT  "v=DKIM1; k=rsa; p=MIGfMA0GC..."

; DMARC — basic policy
_dmarc.example.com. IN  TXT   "v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com"
```

Also set the **PTR** (reverse DNS) for the VPS public IP to
`smtp.example.com` — this is configured in your hosting/cloud provider's
panel, not in DNS for the domain.

You can verify with:

```bash
dig +short A smtp.example.com
dig +short A api.example.com
dig +short TXT example.com
dig +short TXT smtp._domainkey.example.com
dig +short TXT _dmarc.example.com
dig +short -x <VPS_IPv4>
```

---

## Environment variables

Copy `.env.example` to `.env` and fill in the values. Every variable is
documented inline in the example file. Summary:

| Variable      | Required | Default          | Meaning                                                                                       |
| ------------- | :------: | ---------------- | --------------------------------------------------------------------------------------------- |
| `PORT`        |    no    | `3001`           | HTTP port for the API gateway. Nginx proxies to it.                                            |
| `API_KEY`     |  **yes** | —                | 32-char random string. Required in the `x-api-key` header on every `/api/emails/*` request.    |
| `DB_HOST`     |  **yes** | `127.0.0.1`      | PostgreSQL host. Use `postgres` when running via docker-compose.                                |
| `DB_PORT`     |    no    | `5432`           | PostgreSQL port.                                                                                |
| `DB_USER`     |  **yes** | —                | DB username.                                                                                    |
| `DB_PASSWORD` |  **yes** | —                | DB password.                                                                                    |
| `DB_NAME`     |  **yes** | —                | DB name.                                                                                        |
| `DB_SYNC`     |    no    | `true`           | If `true`, Sequelize creates/updates the `email_logs` table on startup.                          |
| `DB_LOGGING`  |    no    | `false`          | If `true`, prints every SQL query.                                                              |
| `SMTP_HOST`   |  **yes** | `127.0.0.1`      | Hostname of the SMTP relay nodemailer connects to.                                              |
| `SMTP_PORT`   |    no    | `25`             | SMTP port (`25`, `465` or `587`).                                                                |
| `SMTP_SECURE` |    no    | `false`          | `true` only for implicit TLS on port `465`.                                                     |
| `MAIL_FROM`   |  **yes** | —                | `From:` header of every email. Must be on the domain you signed with DKIM.                      |

Generate `API_KEY` (32 random hex chars):

```bash
openssl rand -hex 16
# or
node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"
```

---

## Running the API

### Local (npm)

```bash
npm install
cp .env.example .env
# Make sure PostgreSQL is running and reachable
npm run start:dev      # watch mode
# or
npm run build && npm run start:prod
```

The server listens on `http://localhost:${PORT}`.

### Docker Compose

`docker-compose.yml` brings up two services:

- `postgres` — PostgreSQL 16 with a named volume `postgres_data`
- `app` — this NestJS app, built from `Dockerfile`

```bash
cp .env.example .env
# Fill API_KEY, DB_USER, DB_PASSWORD, DB_NAME, MAIL_FROM in .env

docker compose up -d --build
docker compose logs -f app
```

Inside the `app` container, `SMTP_HOST` defaults to
`host.docker.internal`, which maps to the host machine where postfix
listens on port 25. Override `SMTP_HOST` in `.env` if your relay lives
elsewhere.

In production behind nginx, expose only `127.0.0.1:${PORT}` from the app
container — the public surface is nginx on `:443`.

---

## API reference

All endpoints are prefixed with `/api`. Field names use `snake_case` in
both request bodies and responses.

### `GET /api/health`

Liveness probe — no auth required.

```json
{ "status": "ok", "timestamp": "2026-05-04T12:34:56.789Z" }
```

### `POST /api/emails/send`

Sends one email per address in `emails`. Each attempt is recorded in
`email_logs` regardless of success or failure.

**Headers**

```
Content-Type: application/json
x-api-key: <your API_KEY>
```

**Body**

```json
{
  "emails": ["alice@example.com", "bob@example.com"],
  "subject": "Optional subject line",
  "body": "<h1>Hello</h1><p>Plain text or HTML.</p>",
  "is_html": true
}
```

| Field     | Type       | Required | Notes                                                  |
| --------- | ---------- | :------: | ------------------------------------------------------ |
| `emails`  | `string[]` |  **yes** | 1–500 valid email addresses; duplicates are ignored.    |
| `subject` | `string`   |    no    | Up to 998 chars (RFC 2822 line length).                 |
| `body`    | `string`   |  **yes** | Plain text or HTML depending on `is_html`.              |
| `is_html` | `boolean`  |  **yes** | `true` → sent as `Content-Type: text/html`.             |

**Response — 200 OK**

```json
{
  "total": 2,
  "sent": 1,
  "failed": 1,
  "results": [
    { "email": "alice@example.com", "status": "sent",   "message_id": "<...@smtp.example.com>" },
    { "email": "bob@example.com",   "status": "failed", "error": "550 5.1.1 user unknown" }
  ]
}
```

**Errors**

| Status | When                                                          |
| ------ | ------------------------------------------------------------- |
| `400`  | DTO validation failed (bad email, missing field, etc.).        |
| `401`  | Missing or wrong `x-api-key`.                                  |

**Example**

```bash
curl -X POST https://api.example.com/api/emails/send \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "emails": ["test@gmail.com"],
    "subject": "Greetings",
    "body": "<p>Hi from <b>SMTP server</b>.</p>",
    "is_html": true
  }'
```

---

## Database schema

Table `email_logs` is created automatically on startup
(`DB_SYNC=true`). One row per recipient per send attempt. All column
names are `snake_case`.

| Column          | Type                       | Description                                            |
| --------------- | -------------------------- | ------------------------------------------------------ |
| `id`            | `UUID` (pk)                | Auto-generated.                                        |
| `from_address`  | `varchar`                  | Equal to `MAIL_FROM` at send time.                     |
| `to_address`    | `varchar`                  | Recipient email.                                       |
| `subject`       | `varchar(998)`, nullable   | Subject line, if provided.                             |
| `is_html`       | `boolean`                  | Whether the body was sent as HTML.                     |
| `status`        | `enum('sent','failed')`    | Final delivery status reported by postfix.             |
| `message_id`    | `varchar`, nullable        | RFC `Message-ID` returned by nodemailer on success.    |
| `error_message` | `text`, nullable           | Full error string when `status = 'failed'`.            |
| `sent_at`       | `timestamp`                | When the row was created (= attempt time).             |

Useful queries:

```sql
SELECT status, count(*) FROM email_logs GROUP BY status;

SELECT to_address, error_message, sent_at
FROM email_logs
WHERE status = 'failed'
ORDER BY sent_at DESC
LIMIT 50;
```

---

## GitHub Actions deploy

`.github/workflows/` contains two SSH-based pipelines:

- `vps_server_development.yml` — deploys on every push to `dev`.
- `vps_server_production.yml` — deploys on merged PRs into `main`.

Required repository secrets:

| Secret                  | Description                                                 |
| ----------------------- | ----------------------------------------------------------- |
| `PRIVATE_KEY`           | Private SSH key authorised on the VPS.                      |
| `PROD_HOST`             | Public hostname or IP of the VPS.                           |
| `PROD_USER`             | SSH user (typically `root` or a sudoer).                    |
| `SMTP_DEPLOYMENT_KEY`   | GitHub PAT used to clone the repo over HTTPS on the VPS.    |

Both pipelines `pm2 stop all` → wipe `/var/www/smtp_server/` → re-clone →
`npm ci && npm run build` → `pm2 start ./dist/main.js`. If you prefer
Docker, replace those steps with `docker compose up -d --build` on the
VPS.

---

## Project layout

```
.
├── bash_utils/                          # VPS provisioning scripts
│   ├── setup_smtp_server.sh             # postfix + Let's Encrypt
│   ├── sign_dkim_domain.sh              # OpenDKIM signing
│   ├── setup_api_gateway_nginx.sh       # nginx reverse proxy + HTTPS
│   ├── setup_ssl_cert.sh                # SMTP cert (re)issue
│   ├── update_ssl_cert.sh               # SMTP cert renew
│   └── uninstall_smtp_server.sh
├── src/
│   ├── app.controller.ts                # GET /api/health
│   ├── app.module.ts
│   ├── main.ts                          # Helmet + ValidationPipe + /api prefix
│   ├── common/
│   │   └── guards/
│   │       └── api-key.guard.ts
│   ├── database/
│   │   └── database.module.ts           # Sequelize + PostgreSQL bootstrap
│   └── modules/
│       └── email/
│           ├── dto/send-email.dto.ts
│           ├── entities/email-log.entity.ts
│           ├── services/
│           │   ├── email.service.ts     # business logic + DB logging
│           │   └── mailer.service.ts    # nodemailer transport
│           ├── email.controller.ts
│           └── email.module.ts
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── package.json
```

---

## Troubleshooting

**`Connection refused` to 127.0.0.1:25.**
Postfix is not running. `systemctl status postfix`. If you ran the bash
scripts inside Docker by accident, install postfix on the host instead.

**`502 Bad Gateway` from nginx.**
The NestJS app is not running on `127.0.0.1:3001` (or the port nginx
proxies to). Check `pm2 list` / `docker compose ps` and `journalctl -u
nginx -e`.

**Mail goes to spam.**
Verify SPF, DKIM, DMARC and PTR (see [DNS records](#dns-records-spf--dkim--dmarc--ptr)).
Test with [https://www.mail-tester.com](https://www.mail-tester.com).

**`relay access denied` in the response error.**
Postfix only relays from `mynetworks` (127.0.0.0/8 by default). Either
keep the API on the same host as postfix (recommended) or extend
`mynetworks` in `/etc/postfix/main.cf`.

**`certbot` fails with port 80 in use.**
For `setup_smtp_server.sh` (which uses `--standalone`), stop nginx
temporarily. For `setup_api_gateway_nginx.sh` (which uses
`--nginx`), nginx is expected to be running — that script handles it
automatically.

**`401 Unauthorized` even with the right header.**
Check that `API_KEY` in `.env` is loaded by NestJS — the app must be
restarted after editing `.env`. Header name is case-insensitive but the
value must match byte-for-byte.

---

## License

MIT — see [LICENSE](LICENSE).
