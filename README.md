# Rated

Movie ranking + social app. Vite + React frontend (Netlify) talks to a
FastAPI + SQLAlchemy backend (host TBD). SQLite locally, Postgres in prod
via `DATABASE_URL`.

| App tour | Buy tickets |
|---|---|
| ![App tour](docs/gifs/web-app-tour.gif) | ![Buy tickets](docs/gifs/web-buy-tickets.gif) |
| Home → Soon → Search → Board → Me | Shows on a movie once you and someone you follow have both rated it; opens an affiliate Fandango link. Hidden otherwise (The Dark Knight). |
| **iOS · Onboarding → pairwise rank** | |
| ![iOS onboarding and ranking](docs/ios/gifs/ios-onboarding-rank.gif) | |
| Sign in, pick a name and @handle, then rank first films head-to-head; each pick bisects your list and updates Elo. | |

The web app and backend live under [`build/`](build/); the native SwiftUI iOS
app lives under [`ios/`](ios/) ([`ios/README.md`](ios/README.md)). Start there:

- [`build/README.md`](build/README.md) — repo overview, quickstart, API surface, deploy notes
- [`build/backend/README.md`](build/backend/README.md) — backend-specific docs (Make targets, Render walkthrough, schema migrations)

Two Claude skills travel with the repo for repeatable ops:

- `/build-server` — start (or restart) the local app cleanly
- `/fetch-netlify` — read live deploy state, env vars, build logs

Defined under [`build/.claude/skills/`](build/.claude/skills/).
