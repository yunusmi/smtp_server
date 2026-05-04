# SMTP-сервер

> SMTP-сервер для отправки электронных писем пользователям с вашего
> подготовленного сервера через автоматическую установку bash-скриптов и
> интерфейс API-шлюза.

[English version](README.md)

Готовый набор, который делает три вещи:

1. Разворачивает на чистой Ubuntu VPS защищённый **postfix** SMTP-релей
   с помощью скриптов из [`bash_utils/`](bash_utils/) (TLS через
   Let's Encrypt, подпись DKIM через OpenDKIM).
2. Поднимает NestJS **HTTP API-шлюз**, который принимает запросы на
   отправку писем (с заголовком `x-api-key`) и пересылает их через
   локальный postfix с помощью **nodemailer**. Шлюз публикуется во
   внешний интернет через **nginx + Let's Encrypt** как
   `https://api.example.com`.
3. Сохраняет каждую попытку отправки в **PostgreSQL** (получатель, тема,
   статус, message id, ошибка, время) — полные логи для аудита.

---

## Содержание

- [Архитектура](#архитектура)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Настройка SMTP-сервера (bash_utils)](#настройка-smtp-сервера-bash_utils)
- [Публикация API через HTTPS (nginx)](#публикация-api-через-https-nginx)
- [DNS-записи (SPF / DKIM / DMARC / PTR)](#dns-записи-spf--dkim--dmarc--ptr)
- [Переменные окружения](#переменные-окружения)
- [Запуск API](#запуск-api)
  - [Локально (npm)](#локально-npm)
  - [Docker Compose](#docker-compose)
- [Описание API](#описание-api)
- [Схема базы данных](#схема-базы-данных)
- [Деплой через GitHub Actions](#деплой-через-github-actions)
- [Структура проекта](#структура-проекта)
- [Решение проблем](#решение-проблем)
- [Лицензия](#лицензия)

---

## Архитектура

```
                       +--------------------+
   HTTPS               |  Ваше приложение   |
  (x-api-key)          |  (бэкенд / cron)   |
                       +---------+----------+
                                 |
                                 | POST https://api.example.com/api/emails/send
                                 v
+----------------------------------------------------------------+
|                            VPS                                 |
|                                                                |
|   +--------------+   :443/:80   +-----------------------+      |
|   |    nginx     | <----------- |    Внешний интернет   |      |
|   | (LetsEncrypt)|              +-----------------------+      |
|   +------+-------+                                             |
|          | proxy_pass http://127.0.0.1:3001                    |
|          v                                                     |
|   +--------------------------+                                 |
|   |    NestJS API-шлюз       |                                 |
|   |  ApiKeyGuard             |                                 |
|   |  -> EmailController      |                                 |
|   |  -> EmailService -------- writes ---> +---------------+    |
|   |       |                                |  PostgreSQL  |    |
|   |       v                                |  email_logs  |    |
|   |  MailerService (nodemailer)            +---------------+    |
|   |       |                                                    |
|   |       v 127.0.0.1:25                                       |
|   |  +-----------------+      :25/:465/:587                    |
|   |  |   postfix +     | -------------------> Интернет (получатели)
|   |  |   OpenDKIM      |                                       |
|   |  +-----------------+                                       |
+----------------------------------------------------------------+
```

API-процесс слушает **только `127.0.0.1`** в продакшене. Nginx — это
единственный публичный компонент, поэтому заголовок `x-api-key`
всегда отправляется по TLS.

---

## Требования

| Компонент              | Версия                |
| ---------------------- | --------------------- |
| Ubuntu VPS             | 22.04 LTS+            |
| Node.js                | 20.x                  |
| PostgreSQL             | 14+                   |
| Зарегистрированный домен | с доступом к DNS    |
| Открытые порты на VPS   | 25, 80, 443, 465, 587 |

Также нужен публичный IPv4 с чистой репутацией и настроенной PTR-записью
(обратный DNS), указывающей на имя SMTP-хоста. Без этих условий крупные
почтовые провайдеры (Gmail, Outlook и т.д.) будут отклонять или
помещать письма в спам.

---

## Быстрый старт

```bash
# 1. На VPS под root — установить postfix, выпустить TLS, подписать DKIM
sudo bash bash_utils/setup_smtp_server.sh
sudo bash bash_utils/sign_dkim_domain.sh

# 2. Опубликовать API-шлюз через nginx + HTTPS (api.example.com)
sudo bash bash_utils/setup_api_gateway_nginx.sh

# 3. Опубликовать DKIM TXT + SPF + DMARC у DNS-провайдера
#    (DKIM запись вывел sign_dkim_domain.sh)

# 4. Склонировать репозиторий, настроить env, запустить через docker compose
git clone https://github.com/yunusmi/smtp_server.git /var/www/smtp_server
cd /var/www/smtp_server
cp .env.example .env
nano .env       # заполнить API_KEY, DB_*, MAIL_FROM
docker compose up -d --build

# 5. Проверить отправкой тестового письма
curl -X POST https://api.example.com/api/emails/send \
  -H "Content-Type: application/json" \
  -H "x-api-key: <ваш-API_KEY>" \
  -d '{"emails":["you@gmail.com"],"subject":"Привет","body":"Работает","is_html":false}'
```

---

## Настройка SMTP-сервера (bash_utils)

Все скрипты запускаются от **root** на чистой Ubuntu VPS.

| Скрипт                                                                   | Назначение                                                                                                                                                                                                |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`setup_smtp_server.sh`](bash_utils/setup_smtp_server.sh)                | Ставит postfix + mailutils + certbot, спрашивает `DOMAIN_NAME` и `SMTP_HOST`, выпускает сертификат Let's Encrypt, генерирует `/etc/postfix/main.cf`, открывает порты 25/465/587 в iptables, сохраняет правила. |
| [`sign_dkim_domain.sh`](bash_utils/sign_dkim_domain.sh)                  | Ставит OpenDKIM, генерирует ключ для `$SMTP_HOST`, подключает его как milter к postfix и выводит TXT-запись, которую нужно опубликовать в DNS.                                                              |
| [`setup_api_gateway_nginx.sh`](bash_utils/setup_api_gateway_nginx.sh)    | Спрашивает `API_HOST` (например, `api.example.com`), ставит nginx и certbot-плагин для nginx, конфигурирует reverse-proxy на `127.0.0.1:3001`, выпускает HTTPS-сертификат и включает редирект HTTP → HTTPS. |
| [`setup_ssl_cert.sh`](bash_utils/setup_ssl_cert.sh)                      | Перевыпуск сертификата Let's Encrypt для SMTP-хоста (например, после смены домена) и перезагрузка postfix.                                                                                                  |
| [`update_ssl_cert.sh`](bash_utils/update_ssl_cert.sh)                    | Продление SMTP-сертификата через `certbot renew` и перезагрузка postfix. HTTPS-сертификат для API обновляется автоматически таймером `certbot.timer`.                                                       |
| [`uninstall_smtp_server.sh`](bash_utils/uninstall_smtp_server.sh)        | Полностью удаляет postfix, certbot, opendkim, nginx и плагин certbot-nginx, конфиги и записи в `/etc/environment`.                                                                                            |

Первый скрипт задаёт два вопроса:

- **DOMAIN_NAME** — ваш основной домен, например `example.com`
- **SMTP_HOST** — FQDN этого VPS, например `smtp.example.com`. **До**
  запуска скрипта обязательно нужно создать `A`-запись, указывающую на
  публичный IP VPS — иначе certbot не пройдёт HTTP-01 валидацию.

После завершения обоих скриптов postfix слушает порты `25`, `465` и
`587`, подписывает исходящую почту через DKIM и готов релеить любые
письма, отправленные с `127.0.0.1` без аутентификации.

---

## Публикация API через HTTPS (nginx)

NestJS-шлюз слушает обычный HTTP на `127.0.0.1:3001`. Порт `3001`
**нельзя** выставлять в интернет напрямую — API-ключ будет ходить в
открытом виде. Вместо этого запускайте
[`setup_api_gateway_nginx.sh`](bash_utils/setup_api_gateway_nginx.sh):

```bash
sudo bash bash_utils/setup_api_gateway_nginx.sh
# Type your API gateway hostname (ex. api.example.com): api.example.com
```

Что делает скрипт:

1. Ставит `nginx` и `python3-certbot-nginx`.
2. Пишет `/etc/nginx/sites-available/api-gateway` — server-блок, который
   проксирует `https://$API_HOST/` на `http://127.0.0.1:3001/` и
   пробрасывает заголовки `Host`, `X-Real-IP`, `X-Forwarded-For` и
   `X-Forwarded-Proto`.
3. Отключает дефолтный сайт nginx, делает `nginx -t` и reload.
4. Открывает порты `80` и `443` в iptables и сохраняет правила.
5. Запускает `certbot --nginx --redirect -d $API_HOST` — выпускает
   сертификат, дописывает TLS-листенер в server-блок и принудительно
   редиректит HTTP → HTTPS.
6. Включает `nginx` и `certbot.timer` (авто-обновление каждые 12 часов).

**Предусловие:** `A`-запись `api.example.com → <IPv4 VPS>` должна быть
опубликована в DNS *до* запуска скрипта — certbot нужен HTTP-01
challenge.

После завершения шлюз доступен по адресу `https://api.example.com`, а
сертификат будет автоматически продлеваться.

---

## DNS-записи (SPF / DKIM / DMARC / PTR)

Даже идеально настроенный сервер будет улетать в спам без этих записей
на домене из `MAIL_FROM`:

```
; A-запись для SMTP-хоста
smtp.example.com.   IN  A     <IPv4 VPS>

; A-запись для API-шлюза
api.example.com.    IN  A     <IPv4 VPS>

; SPF — разрешить VPS отправлять почту от имени домена
example.com.        IN  TXT   "v=spf1 mx a:smtp.example.com ~all"

; DKIM — публичный ключ из вывода sign_dkim_domain.sh.
; Селектор — то, что стоит до "._domainkey." (имя хоста VPS).
smtp._domainkey.example.com.  IN  TXT  "v=DKIM1; k=rsa; p=MIGfMA0GC..."

; DMARC — базовая политика
_dmarc.example.com. IN  TXT   "v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com"
```

Также настройте **PTR** (обратный DNS) для публичного IP VPS на
`smtp.example.com` — это делается в панели хостинг-провайдера, а не в
DNS домена.

Проверить можно так:

```bash
dig +short A smtp.example.com
dig +short A api.example.com
dig +short TXT example.com
dig +short TXT smtp._domainkey.example.com
dig +short TXT _dmarc.example.com
dig +short -x <IPv4 VPS>
```

---

## Переменные окружения

Скопируйте `.env.example` в `.env` и заполните значения. Все переменные
закомментированы прямо в файле-примере. Сводка:

| Переменная    | Обязательная | По умолчанию | Описание                                                                                       |
| ------------- | :----------: | ------------ | --------------------------------------------------------------------------------------------- |
| `PORT`        |     нет      | `3001`       | HTTP-порт API-шлюза. Nginx проксирует на него.                                                  |
| `API_KEY`     |   **да**     | —            | Случайная строка длиной 32 символа. Передаётся в заголовке `x-api-key` при каждом запросе.       |
| `DB_HOST`     |   **да**     | `127.0.0.1`  | Хост PostgreSQL. В docker-compose используйте `postgres`.                                       |
| `DB_PORT`     |     нет      | `5432`       | Порт PostgreSQL.                                                                                |
| `DB_USER`     |   **да**     | —            | Пользователь БД.                                                                                |
| `DB_PASSWORD` |   **да**     | —            | Пароль БД.                                                                                      |
| `DB_NAME`     |   **да**     | —            | Имя БД.                                                                                         |
| `DB_SYNC`     |     нет      | `true`       | При `true` Sequelize создаёт/обновляет таблицу `email_logs` при старте.                          |
| `DB_LOGGING`  |     нет      | `false`      | При `true` логирует все SQL-запросы в stdout.                                                    |
| `SMTP_HOST`   |   **да**     | `127.0.0.1`  | Хост SMTP-релея, к которому подключается nodemailer.                                             |
| `SMTP_PORT`   |     нет      | `25`         | Порт SMTP (`25`, `465` или `587`).                                                                |
| `SMTP_SECURE` |     нет      | `false`      | `true` только для implicit TLS на порту `465`.                                                   |
| `MAIL_FROM`   |   **да**     | —            | Заголовок `From:` в исходящих письмах. Должен быть на домене, для которого вы подписали DKIM.    |

Сгенерировать `API_KEY` (32 случайных hex-символа):

```bash
openssl rand -hex 16
# или
node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"
```

---

## Запуск API

### Локально (npm)

```bash
npm install
cp .env.example .env
# Убедитесь, что PostgreSQL запущен и доступен
npm run start:dev      # режим watch
# или
npm run build && npm run start:prod
```

Сервер слушает `http://localhost:${PORT}`.

### Docker Compose

`docker-compose.yml` поднимает два сервиса:

- `postgres` — PostgreSQL 16 с именованным томом `postgres_data`
- `app` — это NestJS-приложение, собирается из `Dockerfile`

```bash
cp .env.example .env
# Заполните API_KEY, DB_USER, DB_PASSWORD, DB_NAME, MAIL_FROM в .env

docker compose up -d --build
docker compose logs -f app
```

В контейнере `app` `SMTP_HOST` по умолчанию — `host.docker.internal`,
что указывает на хост-машину, где postfix слушает порт 25. Если ваш
релей живёт где-то ещё, переопределите `SMTP_HOST` в `.env`.

В продакшене за nginx наружу из контейнера приложения должен быть
открыт только `127.0.0.1:${PORT}` — публичная поверхность это nginx
на `:443`.

---

## Описание API

Все эндпоинты с префиксом `/api`. Поля используют `snake_case` как в
теле запроса, так и в ответе.

### `GET /api/health`

Liveness-пробник, без авторизации.

```json
{ "status": "ok", "timestamp": "2026-05-04T12:34:56.789Z" }
```

### `POST /api/emails/send`

Отправляет одно письмо на каждый адрес из `emails`. Каждая попытка
записывается в `email_logs` независимо от успеха.

**Заголовки**

```
Content-Type: application/json
x-api-key: <ваш API_KEY>
```

**Тело запроса**

```json
{
  "emails": ["alice@example.com", "bob@example.com"],
  "subject": "Тема (необязательно)",
  "body": "<h1>Привет</h1><p>Текст или HTML.</p>",
  "is_html": true
}
```

| Поле      | Тип        | Обязательное | Примечания                                              |
| --------- | ---------- | :----------: | ------------------------------------------------------- |
| `emails`  | `string[]` |   **да**     | 1–500 валидных адресов; дубликаты игнорируются.          |
| `subject` | `string`   |    нет       | До 998 символов (RFC 2822).                              |
| `body`    | `string`   |   **да**     | Текст или HTML — в зависимости от `is_html`.             |
| `is_html` | `boolean`  |   **да**     | `true` → отправляется как `Content-Type: text/html`.     |

**Ответ — 200 OK**

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

**Ошибки**

| Код    | Причина                                                              |
| ------ | -------------------------------------------------------------------- |
| `400`  | Не прошла валидация DTO (битый email, нет обязательного поля и т.д.). |
| `401`  | Заголовок `x-api-key` отсутствует или неверен.                        |

**Пример**

```bash
curl -X POST https://api.example.com/api/emails/send \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "emails": ["test@gmail.com"],
    "subject": "Приветствие",
    "body": "<p>Привет от <b>SMTP server</b>.</p>",
    "is_html": true
  }'
```

---

## Схема базы данных

Таблица `email_logs` создаётся автоматически при старте
(`DB_SYNC=true`). Одна строка на каждую попытку отправки на каждый
адрес. Все колонки именуются в `snake_case`.

| Колонка         | Тип                       | Описание                                              |
| --------------- | ------------------------- | ----------------------------------------------------- |
| `id`            | `UUID` (pk)               | Генерируется автоматически.                           |
| `from_address`  | `varchar`                 | Значение `MAIL_FROM` на момент отправки.              |
| `to_address`    | `varchar`                 | Email получателя.                                     |
| `subject`       | `varchar(998)`, nullable  | Тема, если была передана.                             |
| `is_html`       | `boolean`                 | Был ли body отправлен как HTML.                       |
| `status`        | `enum('sent','failed')`   | Итоговый статус доставки от postfix.                  |
| `message_id`    | `varchar`, nullable       | RFC `Message-ID` от nodemailer при успехе.            |
| `error_message` | `text`, nullable          | Полный текст ошибки при `status = 'failed'`.          |
| `sent_at`       | `timestamp`               | Когда строка была создана (= время попытки).          |

Полезные запросы:

```sql
SELECT status, count(*) FROM email_logs GROUP BY status;

SELECT to_address, error_message, sent_at
FROM email_logs
WHERE status = 'failed'
ORDER BY sent_at DESC
LIMIT 50;
```

---

## Деплой через GitHub Actions

В `.github/workflows/` лежат два SSH-пайплайна:

- `vps_server_development.yml` — деплоит при каждом push в `dev`.
- `vps_server_production.yml` — деплоит при merge PR в `main`.

Необходимые секреты репозитория:

| Секрет                  | Описание                                                  |
| ----------------------- | --------------------------------------------------------- |
| `PRIVATE_KEY`           | Приватный SSH-ключ, авторизованный на VPS.                 |
| `PROD_HOST`             | Публичное имя или IP VPS.                                  |
| `PROD_USER`             | SSH-пользователь (обычно `root` или sudoer).               |
| `SMTP_DEPLOYMENT_KEY`   | GitHub PAT для клонирования репозитория по HTTPS на VPS.    |

Оба пайплайна делают `pm2 stop all` → удаляют `/var/www/smtp_server/` →
заново клонируют → `npm ci && npm run build` → `pm2 start ./dist/main.js`.
Если предпочитаете Docker — замените эти шаги на
`docker compose up -d --build` на VPS.

---

## Структура проекта

```
.
├── bash_utils/                          # Скрипты подготовки VPS
│   ├── setup_smtp_server.sh             # postfix + Let's Encrypt
│   ├── sign_dkim_domain.sh              # подпись OpenDKIM
│   ├── setup_api_gateway_nginx.sh       # nginx reverse proxy + HTTPS
│   ├── setup_ssl_cert.sh                # перевыпуск SMTP-сертификата
│   ├── update_ssl_cert.sh               # продление SMTP-сертификата
│   └── uninstall_smtp_server.sh
├── src/
│   ├── app.controller.ts                # GET /api/health
│   ├── app.module.ts
│   ├── main.ts                          # Helmet + ValidationPipe + префикс /api
│   ├── common/
│   │   └── guards/
│   │       └── api-key.guard.ts
│   ├── database/
│   │   └── database.module.ts           # Подключение Sequelize + PostgreSQL
│   └── modules/
│       └── email/
│           ├── dto/send-email.dto.ts
│           ├── entities/email-log.entity.ts
│           ├── services/
│           │   ├── email.service.ts     # бизнес-логика + запись в БД
│           │   └── mailer.service.ts    # транспорт nodemailer
│           ├── email.controller.ts
│           └── email.module.ts
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── package.json
```

---

## Решение проблем

**`Connection refused` на 127.0.0.1:25.**
Postfix не запущен. `systemctl status postfix`. Если случайно запустили
bash-скрипты внутри Docker — установите postfix на хост.

**`502 Bad Gateway` от nginx.**
NestJS-приложение не запущено на `127.0.0.1:3001` (или на том порту,
куда проксирует nginx). Проверьте `pm2 list` / `docker compose ps` и
`journalctl -u nginx -e`.

**Письма уходят в спам.**
Проверьте SPF, DKIM, DMARC и PTR (см. [DNS-записи](#dns-записи-spf--dkim--dmarc--ptr)).
Тестируйте на [https://www.mail-tester.com](https://www.mail-tester.com).

**`relay access denied` в ошибке ответа.**
Postfix релеит только из `mynetworks` (по умолчанию 127.0.0.0/8). Либо
держите API на той же машине, что и postfix (рекомендуется), либо
расширьте `mynetworks` в `/etc/postfix/main.cf`.

**`certbot` падает с ошибкой про порт 80.**
Для `setup_smtp_server.sh` (использует `--standalone`) — временно
остановите nginx. Для `setup_api_gateway_nginx.sh` (использует
`--nginx`) nginx должен быть запущен — это нормально, скрипт сам
обработает.

**`401 Unauthorized` при правильном заголовке.**
Проверьте, что `API_KEY` из `.env` действительно загрузился — после
правки `.env` нужно перезапустить приложение. Имя заголовка
регистронезависимое, но значение должно совпадать побайтно.

---

## Лицензия

MIT — см. [LICENSE](LICENSE).
