# Rated for iOS

Native SwiftUI port of the web app in `build/src`. It covers the same feature set and
uses the same FastAPI backend.

| Area | What's there |
|---|---|
| Auth | Apple/Google stub sign-in (`sub\|name\|email` dev tokens, same as web), two-step name → @handle with debounced availability check, Keychain-stored session, restore on launch |
| Onboarding | Rank-your-first-5 tutorial with popular grid + search, progress, skip |
| Ranking | Pairwise binary-search ranker with Elo updates, pairwise + final score synced to `/users/{id}/pairwise` and `/rankings` |
| Home | Popular-films grid (TMDB proxy when configured, else `/movies`) |
| Movie detail | Backdrop/poster viewer, trailer, rating, rank/save/review, cast (rich fields need a backend TMDB key) |
| Search / Board | Movie search with recent searches; community top list from `/movies/top` |
| Profile | Rankings, saved films with swipe-to-remove, reviews with edit/delete |
| Settings | Account (display name, username change, 2-step delete), About with developer API-base override |

Optimistic writes roll back with a toast on failure; an unreachable backend shows an honest empty/error state rather than fake data. Emoji icons from the web UI render as SF Symbols
(`Components/Glyphs.swift`).

## Build and run

Needs Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
# Backend (separate terminal). Debug builds point at http://localhost:8010.
cd build/backend && uv venv -p 3.12 .venv && uv pip install -p .venv/bin/python -r requirements.txt
.venv/bin/uvicorn api:app --host 0.0.0.0 --port 8010

# App
cd ios && xcodegen generate && open Rated.xcodeproj
```

On a physical device, set Settings → About → Developer → API base URL to your Mac's LAN IP
(e.g. `http://192.168.1.20:8010`), or pass `-rated.apiBase <url>` as a launch argument.
Release builds use the hosted API in `project.yml`.

## Tests

```bash
cd ios
# Unit: Elo, bisection ranker, profanity/username rules, time formatting
xcodebuild -scheme Rated -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:RatedTests
# UI: five end-to-end flows against the running backend
xcodebuild -scheme Rated -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:RatedUITests
```

## GIFs

`scripts/record-gifs.sh` drives each UI test on the booted simulator, records the screen
and writes `docs/ios/gifs/ios-*.gif`. Set `CONVERT_ONLY=1` to re-encode existing recordings.
