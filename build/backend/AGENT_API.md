# Records API — for Claude instances & data-entry tools

A flexible, **Airtable-compatible** data store lives alongside the Rated app.
It exists so a non-technical business user can do data entry through an
Airtable-style tool while Claude instances read and write the same rows over a
single API token — **no schema, no migrations, no code changes** to add a table
or a field.

## Auth

Every Records endpoint requires a bearer token:

```
Authorization: Bearer <AGENT_API_TOKEN>
```

`AGENT_API_TOKEN` is set in the Render dashboard (generated automatically on
first deploy — see **Environment** tab). The same value is the "personal access
token" you'd paste into any Airtable client. Set a comma-separated list to issue
several tokens. Without the token you get `401`; if the server has no token
configured at all you get `503` (fails closed, never open).

### Pre-signed URLs (no secret in the URL)

For a link that authenticates on its own — handed to a tool that can't send
headers, or one that should "always work" — mint a **pre-signed URL**. It
carries an HMAC *signature* in the query string instead of the raw token, so it
can be shared or logged without leaking the key, and it's scoped to a path
prefix:

```
?scope=<path-prefix>&exp=<unix-ts>&sig=<hmac>
```

- `scope` — the path prefix the signature grants, boundary-matched: `/v0`
  authorizes the whole API; `/v0/app1/Contacts` authorizes just that table
  (and `/v0/app1` would *not* grant `/v0/app1xyz`).
- `exp` — unix expiry; `0` means **never expires**.
- `sig` — `HMAC_SHA256(key, "<scope>\n<exp>")`, hex.

Mint one with the helper (reads `RECORDS_SIGNING_KEY`, falling back to
`AGENT_API_TOKEN`):

```bash
# Whole API, never expires — append the printed params to any /v0 path:
python sign_url.py --scope /v0
# One table, full URL, expires in 7 days:
python sign_url.py --scope /v0/app1/Contacts --base "$BASE" --ttl 604800
```

Set a dedicated **`RECORDS_SIGNING_KEY`** in Render so signed URLs can be
revoked (rotate the key) independently of the header token. If it's unset, URLs
are signed with the `AGENT_API_TOKEN` value and editing that token invalidates
them. Header/token auth keeps working unchanged alongside this.

## Shape

The path and payloads mirror Airtable's REST API:
`/v0/{baseId}/{tableName}[/{recordId}]`. We run one logical base, so `{baseId}`
is accepted and ignored — use any placeholder (e.g. `app1`). Every record is
`{ "id": "rec…", "createdTime": "…Z", "fields": { … } }`.

| Method & path | Does |
|---|---|
| `GET  /v0/meta/tables` | List tables + record counts |
| `GET  /v0/{base}/{table}?pageSize=&offset=` | List records (newest first); returns `{records, offset?}` |
| `POST /v0/{base}/{table}` | Create — body `{"fields": {…}}` (→ one record) or `{"records": [{"fields": {…}}]}` (→ `{records:[…]}`) |
| `GET  /v0/{base}/{table}/{recordId}` | Fetch one |
| `PATCH /v0/{base}/{table}/{recordId}` | Merge fields (unspecified fields untouched) |
| `PUT  /v0/{base}/{table}/{recordId}` | Replace the whole fields object |
| `DELETE /v0/{base}/{table}/{recordId}` | Delete; returns `{deleted, id}` |

## curl

```bash
BASE=https://rated-api.onrender.com        # your Render URL
TOK=...                                     # AGENT_API_TOKEN

# create
curl -s -X POST "$BASE/v0/app1/Contacts" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"fields":{"Name":"Ada Lovelace","Email":"ada@example.com","Status":"Lead"}}'

# list
curl -s "$BASE/v0/app1/Contacts?pageSize=20" -H "Authorization: Bearer $TOK"

# update (merge)
curl -s -X PATCH "$BASE/v0/app1/Contacts/rec<id>" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"fields":{"Status":"Customer"}}'
```

## Point a real Airtable client at it (pyairtable)

```python
from pyairtable import Api
api = Api("<AGENT_API_TOKEN>", endpoint_url="https://rated-api.onrender.com")
table = api.table("app1", "Contacts")
table.create({"Name": "Ada", "Status": "Lead"})
for rec in table.all():
    print(rec["fields"])
```

Because the request shape is identical to Airtable's, the business user can run
data entry in Airtable itself (or n8n / Zapier / Softr pointed at this base) and
Claude operates on exactly the same records.
