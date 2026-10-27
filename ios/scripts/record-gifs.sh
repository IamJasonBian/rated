#!/usr/bin/env bash
# Record each CoreFlowUITests flow on the booted simulator and convert it to a
# GIF in docs/ios/gifs/. Requires a running backend (default localhost:8010)
# and ffmpeg. Usage: ios/scripts/record-gifs.sh [simulator-udid]
# CONVERT_ONLY=1 re-encodes existing build/videos/*.mov without re-recording.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-booted}"
OUT=../docs/ios/gifs
DD=build/dd
mkdir -p "$OUT" build/videos

[[ -n "${CONVERT_ONLY:-}" ]] || xcodebuild -project Rated.xcodeproj -scheme Rated -destination "platform=iOS Simulator,id=$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)" \
  -derivedDataPath "$DD" build-for-testing -quiet

record() {
  local test="$1" name="$2"
  local mov="build/videos/$name.mov"
  if [[ -z "${CONVERT_ONLY:-}" ]]; then
  rm -f "$mov"
  xcrun simctl io "$SIM" recordVideo --codec h264 --force "$mov" >/dev/null 2>&1 &
  local rec=$!
  sleep 2
  xcodebuild -project Rated.xcodeproj -scheme Rated -destination "platform=iOS Simulator,id=$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)" \
    -derivedDataPath "$DD" test-without-building -only-testing:"RatedUITests/CoreFlowUITests/$test" -quiet || true
  kill -INT "$rec"; wait "$rec" || true
  fi
  # Trim to the app: the springboard (launch + teardown) averages ~158 luma,
  # the app's dark UI ~30-60. Keep from the first 1s run under 100 to the last frame under 100 (a brief
  # light-theme toggle mid-flow stays inside the window).
  local window start end
  window=$(ffprobe -v error -f lavfi -i "movie=$mov,fps=4,signalstats" \
    -show_entries frame=pts_time:frame_tags=lavfi.signalstats.YAVG -of csv=p=0 \
    | awk -F, '$2 < 100 { if (run == 0) rs = $1; run++; if (run == 4 && s == "") s = rs; e = $1; next } { run = 0 } END { print s, e }')
  read -r start end <<<"$window"
  # trim (not -ss): recordings are variable-frame-rate, so input seeking would
  # hold the last springboard frame.
  ffmpeg -y -loglevel error -i "$mov" -vf \
    "trim=start=$(awk "BEGIN{print ${start:-4}+0.3}")${end:+:end=$end},setpts=(PTS-STARTPTS)/1.25,fps=10,scale=300:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$OUT/$name.gif"
  echo "$OUT/$name.gif $(du -h "$OUT/$name.gif" | cut -f1)"
}

record test01_OnboardingAndPairwiseRanking ios-onboarding-rank
record test02_FeedLikeReplyAndDetail ios-feed-review
record test03_ProfileReorderAndSettings ios-profile-settings
record test04_UpcomingSearchLeaderboard ios-browse
record test05_BuyTicketsCTA ios-tickets
