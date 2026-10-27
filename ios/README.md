# Rated for iOS

Native SwiftUI port of the web app in `build/src`. It covers the same feature set and
uses the same FastAPI backend.

| Area | What's there |
|---|---|
| Auth | Apple/Google stub sign-in (`sub\|name\|email` dev tokens, same as web), two-step name → @handle with debounced availability check, Keychain-stored session, restore on launch |
| Onboarding | Rank-your-first-5 tutorial with popular grid + TMDB search, progress, skip |
| Ranking | Pairwise binary-search ranker with Elo updates, pairwise + final score synced to `/users/{id}/pairwise` and `/rankings`, weekly streak |
| Home | Highlights carousel, Following/Everyone feed, likes, 280-char replies, follow, share, report/block, rank/save from the card, pull to refresh |
| Movie detail | Backdrop/poster viewer, trailer (Safari sheet), stats, rank/save/review, cast, people-you-follow takes, **Buy tickets** CTA from `/users/{id}/movies/{movie_id}/tickets` |
| Upcoming / Search / Board | Genre chips + watchlist; movie + user search with history, browse, find friends; Most Rated / Friends' Picks / Top Rated |
| Profile | Streak, stats, rankings with native drag-reorder / re-rank / swipe-to-remove, saved + watchlist with swipe actions, reviews with edit/delete, followers/following sheets, share profile |
| Notifications | All/Followers/Watchlist tabs, follow-request approve/decline, follow back, mark read |
| Settings | Account (PhotosPicker + circular cropper, name/bio, 30-day username change, 2-step delete), privacy + blocked users, find friends (on-device SHA-256 contact hashing, share/email/SMS invite), notification toggles (weekly streak reminder via local notification), dark/light/system theme and text size, developer API-base override |

Optimistic writes with rollback + toast, an offline banner (NWPathMonitor), and mock-data
fallbacks behave the same as on web. Emoji icons from the web UI render as SF Symbols
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
# Unit: Elo, bisection ranker, streaks, profanity/username rules, time formatting
xcodebuild -scheme Rated -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:RatedTests
# UI: five end-to-end flows against the running backend (test05 needs the tickets endpoint)
xcodebuild -scheme Rated -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:RatedUITests
```

## GIFs

`scripts/record-gifs.sh` drives each UI test on the booted simulator, records the screen
and writes `docs/ios/gifs/ios-*.gif`. Set `CONVERT_ONLY=1` to re-encode existing recordings.
