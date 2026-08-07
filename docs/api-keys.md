# API Keys & host check

## Panel UI

**Settings → API Keys**

| Column | Behavior |
|--------|----------|
| API Key | Masked; eye toggles reveal |
| API Secret | Never shown again after create |
| Label | Pencil → inline edit → check to save |
| Permission | Read Only or Read & Write (set at create) |
| Action | Icon pencil / trash only |

Create opens a modal; after create, copy key, secret, and `.env` snippet.

## Machine API

Headers: `x-dpanel-api-key`, `x-dpanel-api-secret`

| Endpoint | Min permission |
|----------|----------------|
| `GET /api/sites/check?domain=` | read |
| `POST /api/internal/routing-domains` | read_write |
| `POST /api/internal/routing-reconcile` | read_write |

Check response: `{ "available": true }` or `{ "available": false }`.

Availability is **exact** match on site primary domain, `extraDomains`, wildcard base, or `www.{wildcardBase}` — not every host under `*.wildcardBase`.

Wrong credentials: ~1 request/second per IP. Valid credentials: unlimited.

Storage: `/opt/stack/data/panel/api-keys.json` (secrets bcrypt-hashed).

## App site `.env`

```env
DPANEL_SITE_DOMAIN=app.example.com
DPANEL_API_KEY=dpk_...
DPANEL_API_SECRET=...
```

## Manual verify checklist

1. Create Read & Write key; secret only on create screen.
2. Wrong secret spam → throttled; correct secret not throttled.
3. Read Only key can check; routing returns 403.
4. Occupied host → `available: false`; free hub subdomain under wildcard → `true`.
5. App with credentials blocks create when host taken; merchant sees generic “name taken”.
