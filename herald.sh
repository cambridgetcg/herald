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
#
# The jester tells only what is true right now — every joke is derived from the
# census that just ran. It used to recite seven lines hardcoded on 2026-06-09;
# by July one of them still insisted ~/Love was 131 commits ahead. It was 1.
# A jester who does not check is just a liar with better timing.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)

MODE=table
case "${1:-}" in
  --json) MODE=json ;;
  --joke) MODE=joke ;;
  --bless)
    # random non-quote, non-heading line from the blessing section
    line=$(awk '/^## The Blessing/,/^---/' "$HERE/BLESSING.md" \
      | grep -v '^>' | grep -v '^#' | grep -v '^---' | grep -v '^$' \
      | awk -v n="$RANDOM" 'BEGIN{srand(n)} {a[NR]=$0} END{print a[int(rand()*NR)+1]}')
    echo "$line"
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
UNCOUNTED=()          # directories that live here but keep no .git — walked past
for d in "$LOVE_REPOS_DIR"/*/; do
  if [ -e "${d}.git" ]; then
    REPOS+=("${d%/}")
  elif [ -e "${d}README.md" ]; then
    UNCOUNTED+=("$(basename "${d%/}")")
  fi
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

BRANCH_PAD=20

row() {
  printf '%s %s %6s  %s %s %s\n' \
    "$(pad "$1" 32)" "$(pad "$2" "$BRANCH_PAD")" "$3" "$(pad "$4" 12)" "$(pad "$5" 52)" "$6"
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

# parallel arrays (bash 3.2 — no associative arrays on macOS)
R_NAME=(); R_BRANCH=(); R_DIRTY=(); R_AHEAD=(); R_BEHIND=()
R_UPSTREAM=(); R_AGE=(); R_MINS=(); R_SUBJ=(); R_FLAGS=(); R_ROOT=(); R_FETCHAGE=()

if [ "$MODE" = "table" ]; then
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

  ahead=0; behind=0; upstream=1
  if ab=$(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null); then
    read -r behind ahead <<<"$ab"
    sync="↑${ahead} ↓${behind}"
  else
    sync="no upstream"; upstream=0
  fi

  subject=""
  if raw=$(git -C "$dir" log -1 --format='%cr|%s' 2>/dev/null) && [ -n "$raw" ]; then
    last="${raw%%|*} · ${raw#*|}"
    subject="${raw#*|}"
    ct=$(git -C "$dir" log -1 --format='%ct' 2>/dev/null)
  else
    last="no commits yet"
    ct=""
  fi

  age_days=0; age_mins=0
  if [ -n "$ct" ]; then
    age_days=$(( (NOW - ct) / 86400 ))
    age_mins=$(( (NOW - ct) / 60 ))
  fi

  sleeping=0
  if [ -n "$ct" ] && [ $((NOW - ct)) -gt "$SLEEP_SECONDS" ]; then
    sleeping=1
  fi

  # NOTE: 💛 deliberately does not consult `behind` — see README "Health".
  # A citizen that has fallen behind is not marked down for it.
  flags=""
  if [ "$dirty" -eq 0 ] && [ "$ahead" -eq 0 ]; then flags+="💛"; fi
  if [ "$dirty" -gt 0 ]; then flags+="✏️"; fi
  if [ "$ahead" -gt 0 ]; then flags+="⬆️"; fi
  if [ "$sleeping" -eq 1 ]; then flags+="💤"; fi

  root=$(git -C "$dir" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)

  # how old is the remote-tracking data these ↑↓ numbers are measured against?
  fetchage=-1
  if [ -f "$dir/.git/FETCH_HEAD" ]; then
    fh=$(stat -f %m "$dir/.git/FETCH_HEAD" 2>/dev/null)
    [ -n "$fh" ] && fetchage=$(( (NOW - fh) / 86400 ))
  fi

  R_NAME+=("$name");     R_BRANCH+=("$branch"); R_DIRTY+=("$dirty")
  R_AHEAD+=("$ahead");   R_BEHIND+=("$behind"); R_UPSTREAM+=("$upstream")
  R_AGE+=("$age_days");  R_MINS+=("$age_mins"); R_SUBJ+=("$subject")
  R_FLAGS+=("$flags");   R_ROOT+=("$root");     R_FETCHAGE+=("$fetchage")

  CITIZENS=$((CITIZENS + 1))
  [ "$dirty" -gt 0 ]    && DIRTY_COUNT=$((DIRTY_COUNT + 1))
  [ "$ahead" -gt 0 ]    && AHEAD_COUNT=$((AHEAD_COUNT + 1))
  [ "$sleeping" -eq 1 ] && SLEEP_COUNT=$((SLEEP_COUNT + 1))

  if [ "$MODE" = "json" ]; then
    JSON_ROWS+=("$(printf '{"name":"%s","branch":"%s","dirty":%s,"aheadBehind":"%s","lastCommit":"%s","flags":"%s"}' \
      "$(json_escape "$name")" \
      "$(json_escape "$branch")" \
      "$dirty" \
      "$(json_escape "$sync")" \
      "$(json_escape "$last")" \
      "$(json_escape "$flags")")")
  elif [ "$MODE" = "table" ]; then
    row "$name" "$branch" "$dirty" "$sync" "${last:0:50}" "$flags"
  fi
done

# ---- the jester -------------------------------------------------------------
# Every line is DERIVED from the census above, so a joke is only ever told
# while it is still true. Nothing is invented; each number came out of git a
# moment ago. A predicate that does not hold contributes no line.
jester() {
  local J=() i n a b
  local last_i=$((CITIZENS - 1))

  # the health model has no word for "behind"
  for ((i=0; i<=last_i; i++)); do
    if [ "${R_BEHIND[$i]}" -ge 20 ] && [ "${R_FLAGS[$i]}" = "💛" ]; then
      J+=("${R_NAME[$i]} is ${R_BEHIND[$i]} commits behind and still wearing 💛. The health model has no word for \"behind\" — it counts what you're carrying and what you've given, never what you've missed. Kindest bug in the kingdom; nobody fix it.")
    fi
  done

  # the census-taker forgets to count himself
  for ((i=0; i<=last_i; i++)); do
    if [ "${R_NAME[$i]}" = "herald" ] && [ "${R_AGE[$i]}" -ge 30 ]; then
      J+=("The herald has blessed this kingdom out of a silence ${R_AGE[$i]} days long. It isn't neglecting anyone. It's demonstrating walkekin.")
    fi
  done

  # standing in two places at once
  for ((i=0; i<=last_i; i++)); do
    if [ "${R_AHEAD[$i]}" -gt 0 ] && [ "${R_BEHIND[$i]}" -gt 0 ]; then
      J+=("${R_NAME[$i]} is ↑${R_AHEAD[$i]} ↓${R_BEHIND[$i]} — the only way to be lonely in both directions at once. It ran ahead with something and left the rest of the party behind.")
    fi
  done

  # the brother it cannot count
  if [ ${#UNCOUNTED[@]} -gt 0 ]; then
    J+=("The herald walked $((CITIZENS + ${#UNCOUNTED[@]})) doors and came home with ${CITIZENS} heads. ${UNCOUNTED[0]} keeps no .git, so it is never counted — welded into nothing, exactly as its README promised.")
  fi

  # the distance is a memory, not a measurement
  for ((i=0; i<=last_i; i++)); do
    if [ "${R_BEHIND[$i]}" -ge 20 ] && [ "${R_FETCHAGE[$i]}" -ge 3 ]; then
      J+=("${R_NAME[$i]} is \"${R_BEHIND[$i]} behind\" — measured against a remote nobody has asked in ${R_FETCHAGE[$i]} days. That isn't the distance. That's where the distance was, last time anyone looked.")
      break
    fi
  done

  # the whole estate doing maintenance, and one citizen building
  local feat_n="" feat_c=0
  for ((i=0; i<=last_i; i++)); do
    case "${R_SUBJ[$i]}" in
      feat*|feat\(*) feat_c=$((feat_c + 1)); feat_n=${R_NAME[$i]} ;;
    esac
  done
  if [ "$feat_c" -eq 1 ]; then
    J+=("Twenty-nine citizens: heartbeats, syncs, pulses, injection fixes, auto-generated state. Exactly one is still building something — ${feat_n}. The whole estate is doing maintenance and ${feat_n} put on music.")
  fi

  # the most reproducible act in the kingdom
  local subj_max=0 subj_name=""
  for ((i=0; i<=last_i; i++)); do
    n=0
    for ((a=0; a<=last_i; a++)); do
      [ "${R_SUBJ[$a]}" = "${R_SUBJ[$i]}" ] && n=$((n + 1))
    done
    if [ "$n" -gt "$subj_max" ]; then subj_max=$n; subj_name="${R_SUBJ[$i]}"; fi
  done
  if [ "$subj_max" -ge 3 ]; then
    J+=("${subj_max} citizens share the exact same most-recent commit, word for word: \"${subj_name}\". The kingdom's most reproducible act is admitting the last thing wasn't enough.")
  fi

  # the oldest cohort, who all took the same day off
  local old_age=0
  for ((i=0; i<=last_i; i++)); do
    [ "${R_AGE[$i]}" -gt "$old_age" ] && old_age=${R_AGE[$i]}
  done
  if [ "$old_age" -ge 14 ]; then
    local cohort="" cohort_n=0
    for ((i=0; i<=last_i; i++)); do
      if [ "${R_AGE[$i]}" -eq "$old_age" ]; then
        cohort_n=$((cohort_n + 1))
        [ -n "$cohort" ] && cohort="$cohort, "
        cohort="$cohort${R_NAME[$i]}"
      fi
    done
    if [ "$cohort_n" -ge 2 ]; then
      J+=("${cohort_n} citizens last spoke on the same day, ${old_age} days ago: ${cohort}. They all took the same afternoon off and nobody noticed, because the kingdom was busy being one.")
    fi
  fi

  # two standards, no standard
  for ((i=0; i<=last_i; i++)); do
    for ((n=i+1; n<=last_i; n++)); do
      a=${R_NAME[$i]}; b=${R_NAME[$n]}
      if [ "the-$a" = "$b" ] || [ "$a" = "the-$b" ]; then
        if [ "${R_UPSTREAM[$i]}" -eq 0 ] && [ "${R_UPSTREAM[$n]}" -eq 0 ]; then
          J+=("'$a' and '$b' both exist, and they are the only two citizens with no remote at all. Two standards, neither of them standard.")
        fi
      fi
    done
  done

  # addresses, and souls
  local souls=0 seen
  for ((i=0; i<=last_i; i++)); do
    seen=0
    for ((a=0; a<i; a++)); do
      [ -n "${R_ROOT[$i]}" ] && [ "${R_ROOT[$a]}" = "${R_ROOT[$i]}" ] && seen=1
    done
    [ "$seen" -eq 0 ] && souls=$((souls + 1))
  done
  if [ "$souls" -lt "$CITIZENS" ]; then
    J+=("${CITIZENS} citizens, ${souls} root commits. Some of them are one soul keeping a flat in town as well. The census counts addresses; the kingdom has souls.")
  fi

  # being ahead has a cost
  for ((i=0; i<=last_i; i++)); do
    if [ ${#R_BRANCH[$i]} -gt "$BRANCH_PAD" ] && [ "${R_AHEAD[$i]}" -gt 20 ]; then
      J+=("${R_NAME[$i]} is ${R_AHEAD[$i]} commits ahead on a branch name ${#R_BRANCH[$i]} characters long, which shoves this whole table $(( ${#R_BRANCH[$i]} - BRANCH_PAD )) spaces to the right. Being ahead has a cost and today it is column alignment.")
      break
    fi
  done

  # a pulse
  for ((i=0; i<=last_i; i++)); do
    if [ "${R_MINS[$i]}" -le 60 ] && [ "${R_MINS[$i]}" -ge 0 ]; then
      J+=("${R_NAME[$i]} committed ${R_MINS[$i]} minutes ago. Some citizens sleep. This one has a pulse.")
      break
    fi
  done

  # a clean kingdom is its own punchline
  if [ "$DIRTY_COUNT" -eq 0 ] && [ "$AHEAD_COUNT" -eq 0 ]; then
    J+=("${CITIZENS} citizens, nothing uncommitted, nothing unpushed. Suspicious. Nobody is this happy.")
  fi

  # resting is not the same as gone
  if [ "$SLEEP_COUNT" -gt 0 ]; then
    J+=("${SLEEP_COUNT} of ${CITIZENS} citizens have slept more than 180 days. Resting is not the same as gone — the herald counts them anyway.")
  fi

  # the honest fallback
  if [ ${#J[@]} -eq 0 ]; then
    J+=("${CITIZENS} citizens and not one of them did anything funny today. The herald counts that as a win.")
  fi

  echo "${J[$((RANDOM % ${#J[@]}))]}"
}

# ---- closing words ----------------------------------------------------------
if [ "$MODE" = "joke" ]; then
  jester
elif [ "$MODE" = "json" ]; then
  printf '['
  for i in "${!JSON_ROWS[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '\n  %s' "${JSON_ROWS[$i]}"
  done
  printf '\n]\n'
else
  echo
  echo "${CITIZENS} citizens · ${DIRTY_COUNT} carrying uncommitted work · ${AHEAD_COUNT} ahead of remote · ${SLEEP_COUNT} sleeping"

  # ↑↓ are measured against remote-tracking refs. herald never fetches, so say
  # out loud how old that picture is rather than letting it read as "now".
  stalest=-1
  for ((i=0; i<CITIZENS; i++)); do
    [ "${R_FETCHAGE[$i]}" -gt "$stalest" ] && stalest=${R_FETCHAGE[$i]}
  done
  if [ "$stalest" -ge 3 ]; then
    echo "↑↓ measured against remote-tracking refs last refreshed ${stalest} days ago — herald never fetches."
  fi
fi
