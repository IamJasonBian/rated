---
name: records-api
description: Read and write the Rated Records API — an Airtable-shaped JSON data store at https://rated-api.onrender.com. Use when building a frontend or script that needs to list/create/update/delete records, or when the user says "vibe code from the records API", "talk to the rated backend", "use the data store", or asks about /v0 endpoints.
---

# Rated Records API

A token-gated, Airtable-compatible store of arbitrary JSON records. No schema
migrations to add a table or field — just write to it. Path shape mirrors
Airtable: `/v0/{base}/{table}[/{recordId}]`. There's one logical base, so
`{base}` is ignored — use any placeholder like `app1`.

## Base URL

```
https://rated-api.onrender.com
```
(Local dev alternative: run the backend and use `http://127.0.0.1:8010`.)

⚠️ Free tier sleeps after ~15 min idle — the first request after a nap
cold-starts in ~30s. Just retry once.

## Auth — two ways

**1. Pre-signed URL (recommended for a frontend — no secret in your code).**
Append this query string to ANY `/v0/...` path. It's an HMAC signature scoped to
the whole API (`/v0`) that never expires — not the raw secret, so it's safe in
client code, and revocable by rotating the key server-side.

```
?scope=%2Fv0&exp=0&sig=de23ecee33cf1f1984806f7a60398f0395e89d73567dd6ab5667e635b6b5e559
```

**2. Bearer header (for server-side / Airtable clients).**
```
Authorization: Bearer <AGENT_API_TOKEN>
```
`AGENT_API_TOKEN` lives in the Render dashboard → `rated-api` → Environment. Any
pyairtable/airtable.js client pointed at the base URL with this as its PAT works
unchanged.

No auth → `401`. Server with no token configured → `503`.

## Endpoints

| Method & path | Does |
|---|---|
| `GET  /v0/meta/tables` | List tables + record counts |
| `GET  /v0/{base}/{table}?pageSize=&offset=` | List records, newest first → `{records, offset?}` |
| `POST /v0/{base}/{table}` | Create — `{"fields":{…}}` (→ one) or `{"records":[{"fields":{…}}]}` (→ `{records:[…]}`) |
| `GET  /v0/{base}/{table}/{recordId}` | Fetch one |
| `PATCH /v0/{base}/{table}/{recordId}` | Merge fields (others untouched) |
| `PUT  /v0/{base}/{table}/{recordId}` | Replace the whole fields object |
| `DELETE /v0/{base}/{table}/{recordId}` | Delete → `{deleted, id}` |

Every record is `{ "id": "rec…", "createdTime": "…Z", "fields": { … } }`.

## curl quickstart

```bash
BASE=https://rated-api.onrender.com
AUTH='scope=%2Fv0&exp=0&sig=de23ecee33cf1f1984806f7a60398f0395e89d73567dd6ab5667e635b6b5e559'

# list tables
curl -s "$BASE/v0/meta/tables?$AUTH"

# create a record
curl -s -X POST "$BASE/v0/app1/Movies?$AUTH" \
  -H 'Content-Type: application/json' \
  -d '{"fields":{"title":"Dune","rating":9}}'

# list records
curl -s "$BASE/v0/app1/Movies?$AUTH"

# update (merge) / delete
curl -s -X PATCH "$BASE/v0/app1/Movies/REC_ID?$AUTH" -H 'Content-Type: application/json' -d '{"fields":{"rating":10}}'
curl -s -X DELETE "$BASE/v0/app1/Movies/REC_ID?$AUTH"
```

## Frontend helper (drop into a Vite/React app)

```js
// records.js — tiny client for the Rated Records API
const BASE = import.meta.env.VITE_API_BASE_URL ?? "https://rated-api.onrender.com";
const AUTH = "scope=%2Fv0&exp=0&sig=de23ecee33cf1f1984806f7a60398f0395e89d73567dd6ab5667e635b6b5e559";
const url = (path) => `${BASE}${path}${path.includes("?") ? "&" : "?"}${AUTH}`;

export const listTables  = ()            => fetch(url(`/v0/meta/tables`)).then(r => r.json());
export const listRecords = (t)           => fetch(url(`/v0/app1/${t}`)).then(r => r.json());
export const createRecord = (t, fields)  => fetch(url(`/v0/app1/${t}`),
  { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ fields }) }).then(r => r.json());
export const updateRecord = (t, id, fields) => fetch(url(`/v0/app1/${t}/${id}`),
  { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ fields }) }).then(r => r.json());
export const deleteRecord = (t, id)      => fetch(url(`/v0/app1/${t}/${id}`), { method: "DELETE" }).then(r => r.json());
```

## Minting a different URL (narrower scope or an expiry)

The signature is `HMAC_SHA256(RECORDS_SIGNING_KEY, "<scope>\n<exp>")`. To scope a
URL to one table, or give it an expiry, use the repo helper (needs the signing
key in env — read it from Render):

```bash
cd build/backend
RECORDS_SIGNING_KEY=<key from Render>  python sign_url.py --scope /v0/app1/Movies --ttl 604800   # one table, 7 days
RECORDS_SIGNING_KEY=<key from Render>  python sign_url.py --scope /v0                              # whole API, forever
```

`scope` is boundary-matched: `/v0/app1` grants `/v0/app1/Movies` but not
`/v0/app1xyz`. `exp=0` = never expires.
