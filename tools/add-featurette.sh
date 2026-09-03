#!/bin/bash
# ---------------------------------------------------------------------------
# Encode a clip, upload it to the `featurettes` bucket, and point a title at it.
#
# Exists because the tvOS hero has no reliable video source of its own. It
# falls back to extracting a YouTube trailer with YouTubeKit, which breaks
# whenever YouTube changes its player and, on the titles checked so far,
# only ever yields adaptive DASH renditions that AVPlayer refuses to open as
# plain URLs. A hosted MP4 in `title_featurettes` takes priority over that
# path in TVHomeView.buildHeroItems, so a row added here removes one title
# from the mercy of extraction entirely.
#
#   ./tools/add-featurette.sh --tmdb 125988 --type tv --in ~/clips/silo.mov
#   ./tools/add-featurette.sh --tmdb 860508 --type movie --in raw.mp4 \
#       --start 00:00:12 --duration 25
#
# Options:
#   --tmdb <id>        TMDB id of the title                        (required)
#   --type tv|movie    media_type; must match the hero item        (default tv)
#   --in <file>        source video, any format ffmpeg reads       (required)
#   --start <ts>       seek into the source before trimming        (default 0)
#   --duration <secs>  clip length                                 (default 25)
#   --keep             leave the encoded .mp4 in ./ instead of /tmp
#   --dry-run          encode only; upload and insert nothing
#
# Requires: ffmpeg + ffprobe (brew install ffmpeg) and curl.
#
# Needs the project's SERVICE ROLE key in the environment. It is not stored
# in this repo and must never be pasted into it:
#
#   export SUPABASE_SERVICE_ROLE_KEY='...'      # Supabase → Settings → API
#
# The anon key will not do — writes to storage and to title_featurettes are
# service-role only by design.
# ---------------------------------------------------------------------------

set -euo pipefail

PROJECT_REF="qwxxkubkbanridcqsqjo"
BUCKET="featurettes"
BASE="https://${PROJECT_REF}.supabase.co"

TMDB_ID=""
MEDIA_TYPE="tv"
SOURCE=""
START="0"
DURATION="25"
KEEP=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmdb)     TMDB_ID="$2"; shift 2 ;;
    --type)     MEDIA_TYPE="$2"; shift 2 ;;
    --in)       SOURCE="$2"; shift 2 ;;
    --start)    START="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --keep)     KEEP=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TMDB_ID" ]] || { echo "--tmdb is required" >&2; exit 2; }
[[ -n "$SOURCE"  ]] || { echo "--in is required" >&2; exit 2; }
[[ -f "$SOURCE"  ]] || { echo "no such file: $SOURCE" >&2; exit 2; }
[[ "$MEDIA_TYPE" == "tv" || "$MEDIA_TYPE" == "movie" ]] \
  || { echo "--type must be tv or movie" >&2; exit 2; }

command -v ffmpeg  >/dev/null || { echo "ffmpeg not found — brew install ffmpeg" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found — brew install ffmpeg" >&2; exit 1; }

if [[ $DRY_RUN -eq 0 && -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "SUPABASE_SERVICE_ROLE_KEY is not set. Export it and run again:" >&2
  echo "  export SUPABASE_SERVICE_ROLE_KEY='...'   # Supabase → Settings → API" >&2
  exit 1
fi

OBJECT="${MEDIA_TYPE}-${TMDB_ID}.mp4"
if [[ $KEEP -eq 1 ]]; then OUT="./${OBJECT}"; else OUT="$(mktemp -d)/${OBJECT}"; fi

# H.264 High + AAC is what AVPlayer opens without negotiation on tvOS.
# +faststart moves the moov atom to the front — without it the player waits
# for the whole file before it can show a frame, which is the stall the hero
# already has too much of. yuv420p because anything else is a black frame on
# some decoders. Even dimensions or x264 refuses the stream outright.
echo "encoding ${DURATION}s from ${START} → ${OUT}"
ffmpeg -hide_banner -loglevel error -y \
  -ss "$START" -i "$SOURCE" -t "$DURATION" \
  -vf "scale='min(1920,iw)':-2:flags=lanczos" \
  -c:v libx264 -profile:v high -level 4.2 -preset slow -crf 20 -maxrate 6M -bufsize 12M \
  -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ac 2 \
  -movflags +faststart \
  "$OUT"

SECONDS_OUT="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | cut -d. -f1)"
BYTES="$(wc -c < "$OUT" | tr -d ' ')"
echo "encoded ${SECONDS_OUT}s, $((BYTES / 1024 / 1024))MB"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run — not uploading. File: $OUT"
  exit 0
fi

PUBLIC_URL="${BASE}/storage/v1/object/public/${BUCKET}/${OBJECT}"

echo "uploading → ${BUCKET}/${OBJECT}"
curl -sS --fail-with-body -X POST \
  "${BASE}/storage/v1/object/${BUCKET}/${OBJECT}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: video/mp4" \
  -H "x-upsert: true" \
  --data-binary "@${OUT}" > /dev/null

# Upsert rather than insert: the table is unique on (tmdb_id, media_type), so
# re-running with a better cut replaces the row instead of failing.
echo "pointing tmdb:${MEDIA_TYPE}:${TMDB_ID} at it"
curl -sS --fail-with-body -X POST \
  "${BASE}/rest/v1/title_featurettes" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: resolution=merge-duplicates,return=minimal" \
  -d "{\"tmdb_id\": ${TMDB_ID}, \"media_type\": \"${MEDIA_TYPE}\", \"featurette_url\": \"${PUBLIC_URL}\", \"duration_seconds\": ${SECONDS_OUT}, \"updated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > /dev/null

echo
echo "done: ${PUBLIC_URL}"
echo "Relaunch the tvOS app; this title should now play the hosted clip."
echo "Check it took with:"
echo "  select title, device_kind from debug_logs where event='tv_hero_video' order by created_at desc limit 6;"
