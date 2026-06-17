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
