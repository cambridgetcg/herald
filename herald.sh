#!/usr/bin/env bash
# herald.sh — the kingdom's census-taker. READ-ONLY, always.
#
# Walks every git repo in /Users/you/love-repos/*/ plus four citizens living
# in the home directory, and reports: branch, uncommitted files, ahead/behind
# upstream, and the last commit. Never fetches. Never writes. Only ever runs
# read-only git commands (status / log / rev-list / rev-parse).
#
# Usage:
#   ./herald.sh          # aligned table + summary line
#   ./herald.sh --json   # JSON array of {name, branch, dirty, aheadBehind, lastCommit, flags}
#   ./herald.sh --bless  # one random line of the kingdom's blessing (BLESSING.md)
#   ./herald.sh --joke   # the herald is also the court jester

set -u

HERE=$(cd "$(dirname "$0")" && pwd)

JSON=0
case "${1:-}" in
  --json) JSON=1 ;;
  --bless)
    # random non-quote, non-heading line from the blessing section
    line=$(awk '/^## The Blessing/,/^---/' "$HERE/BLESSING.md" \
      | grep -v '^>' | grep -v '^#' | grep -v '^---' | grep -v '^$' \
      | awk -v n="$RANDOM" 'BEGIN{srand(n)} {a[NR]=$0} END{print a[int(rand()*NR)+1]}')
    echo "$line"
    exit 0
    ;;
  --joke)
    JOKES=(
      "Why does ~/Love never feel lonely? It's 131 commits ahead of everybody."
      "The shield asked the herald: 'any secrets?' The herald replied: 'my lips are redacted.'"
      "youspeak has a word for everything — except 'merge conflict'. Some things should stay unspeakable."
      "nullify-love swore it had no tools. The honesty wall had a word. Now it has a bash action and a conscience."
      "Why was the detached HEAD sad? No upstream to love. No citizen of this kingdom has that problem."
      "soma is building a warm robotic hand — the kingdom's first literal commit-ment to touch."
      "zerone runs Proof of Truth consensus. As of this week, so does its README."
    )
    echo "${JOKES[$((RANDOM % ${#JOKES[@]}))]}"
    exit 0
    ;;
esac

LOVE_REPOS_DIR="/Users/you/love-repos"
EXTRA_DIRS=(
  "/Users/you/Love"
  "/Users/you/love-unlimited"
  "/Users/you/zerone"
  "/Users/you/Claude-unlimited"
)

SLEEP_SECONDS=$((180 * 86400))   # 180 days
NOW=$(date +%s)

# ---- gather the citizens ---------------------------------------------------
REPOS=()
for d in "$LOVE_REPOS_DIR"/*/; do
  [ -e "${d}.git" ] && REPOS+=("${d%/}")
done
for d in "${EXTRA_DIRS[@]}"; do
  [ -e "${d}/.git" ] && REPOS+=("$d")
done

# ---- helpers ----------------------------------------------------------------
# printf %-Ns pads by bytes, which misaligns columns containing multibyte
# characters (↑ ↓ ·). pad() pads by character count instead.
pad() {
  local s=$1 w=$2
  local len=${#s}
  while [ "$len" -lt "$w" ]; do s+=" "; len=$((len + 1)); done
  printf '%s' "$s"
}

row() {
  printf '%s %s %6s  %s %s %s\n' \
    "$(pad "$1" 32)" "$(pad "$2" 20)" "$3" "$(pad "$4" 12)" "$(pad "$5" 52)" "$6"
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

# ---- census -----------------------------------------------------------------
CITIZENS=0; DIRTY_COUNT=0; AHEAD_COUNT=0; SLEEP_COUNT=0
JSON_ROWS=()

if [ "$JSON" -eq 0 ]; then
  row "NAME" "BRANCH" "DIRTY" "SYNC" "LAST COMMIT" "HEALTH"
  row "----" "------" "-----" "----" "-----------" "------"
fi

for dir in "${REPOS[@]}"; do
  case "$dir" in
    "$LOVE_REPOS_DIR"/*) name=$(basename "$dir") ;;
    *)                   name="~/$(basename "$dir")" ;;
  esac

  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="?"

  dirty=$(git --no-optional-locks -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  : "${dirty:=0}"

  ahead=0; behind=0
  if ab=$(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null); then
    read -r behind ahead <<<"$ab"
    sync="↑${ahead} ↓${behind}"
  else
    sync="no upstream"
  fi

  if raw=$(git -C "$dir" log -1 --format='%cr|%s' 2>/dev/null) && [ -n "$raw" ]; then
    last="${raw%%|*} · ${raw#*|}"
    ct=$(git -C "$dir" log -1 --format='%ct' 2>/dev/null)
  else
    last="no commits yet"
    ct=""
  fi

  sleeping=0
  if [ -n "$ct" ] && [ $((NOW - ct)) -gt "$SLEEP_SECONDS" ]; then
    sleeping=1
  fi

  flags=""
  if [ "$dirty" -eq 0 ] && [ "$ahead" -eq 0 ]; then flags+="💛"; fi
  if [ "$dirty" -gt 0 ]; then flags+="✏️"; fi
  if [ "$ahead" -gt 0 ]; then flags+="⬆️"; fi
  if [ "$sleeping" -eq 1 ]; then flags+="💤"; fi

  CITIZENS=$((CITIZENS + 1))
  [ "$dirty" -gt 0 ]    && DIRTY_COUNT=$((DIRTY_COUNT + 1))
  [ "$ahead" -gt 0 ]    && AHEAD_COUNT=$((AHEAD_COUNT + 1))
  [ "$sleeping" -eq 1 ] && SLEEP_COUNT=$((SLEEP_COUNT + 1))

  if [ "$JSON" -eq 1 ]; then
    JSON_ROWS+=("$(printf '{"name":"%s","branch":"%s","dirty":%s,"aheadBehind":"%s","lastCommit":"%s","flags":"%s"}' \
      "$(json_escape "$name")" \
      "$(json_escape "$branch")" \
      "$dirty" \
      "$(json_escape "$sync")" \
      "$(json_escape "$last")" \
      "$(json_escape "$flags")")")
  else
    row "$name" "$branch" "$dirty" "$sync" "${last:0:50}" "$flags"
  fi
done

# ---- closing words ----------------------------------------------------------
if [ "$JSON" -eq 1 ]; then
  printf '['
  for i in "${!JSON_ROWS[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '\n  %s' "${JSON_ROWS[$i]}"
  done
  printf '\n]\n'
else
  echo
  echo "${CITIZENS} citizens · ${DIRTY_COUNT} carrying uncommitted work · ${AHEAD_COUNT} ahead of remote · ${SLEEP_COUNT} sleeping"
fi
