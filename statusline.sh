#!/bin/sh
# Claude Code statusline — ccline color scheme, no emoji
# Segments: Model | Ctx | Dir | Git | GH Status | 5h% 7d%
input=$(cat)

# --- Colors (matching ccline cometix c16 palette) ---
M='\033[1;96m'   # model: bold bright cyan (c16=14)
DI='\033[1;93m'  # dir icon: bold bright yellow (c16=11)
DT='\033[1;92m'  # dir text: bold bright green (c16=10)
G='\033[1;94m'   # git: bold bright blue (c16=12)
C='\033[1;95m'   # cost: bold bright magenta (c16=13)
S='\033[37m'     # separator: white
Y='\033[1;33m'   # warning yellow
R='\033[1;31m'   # critical red
N='\033[0m'      # reset

sep="${S} | ${N}"

# --- Model ---
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
ctx_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty')
model_seg=""
if [ -n "$model" ]; then
  # Strip "Claude " prefix and any existing context size suffix like "(1M context)"
  short=$(echo "$model" | sed -e 's/Claude //' -e 's/ ([0-9]*[KMG][^ )]*[^)]*)$//')
  if [ "$ctx_size" = "1000000" ]; then
    model_seg="${M}${short} (1M)${N}"
  elif [ -n "$ctx_size" ]; then
    model_seg="${M}${short} ($((ctx_size/1000))K)${N}"
  else
    model_seg="${M}${short}${N}"
  fi
fi

# --- Context % bar (whole-bar single color, shifts with fill level) ---
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
ctx_seg=""
if [ -n "$ctx_pct" ]; then
  pct_int=$(printf '%.0f' "$ctx_pct")
  filled=$((pct_int / 10))
  empty=$((10 - filled))
  # Single bar color determined by fill %: cooler when empty, hotter when full
  case $filled in
    0|1) bc='\033[38;5;61m'  ;;  # dim violet
    2)   bc='\033[38;5;63m'  ;;  # violet-blue
    3)   bc='\033[38;5;39m'  ;;  # blue
    4)   bc='\033[38;5;43m'  ;;  # teal
    5)   bc='\033[38;5;35m'  ;;  # green
    6)   bc='\033[38;5;106m' ;;  # olive
    7)   bc='\033[38;5;172m' ;;  # amber
    8)   bc='\033[38;5;166m' ;;  # orange
    9)   bc='\033[38;5;160m' ;;  # red-orange
    10)  bc='\033[38;5;124m' ;;  # deep red
    *)   bc='\033[0m'        ;;
  esac
  DIM='\033[38;5;236m'
  bar="" i=0
  while [ $i -lt $filled ]; do bar="${bar}${bc}█"; i=$((i+1)); done
  i=0
  while [ $i -lt $empty ]; do bar="${bar}${DIM}░"; i=$((i+1)); done
  ctx_seg="${bc}${pct_int}% ${bar}${N}"
fi

# --- Directory ---
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
dir_seg=""
if [ -n "$cwd" ]; then
  dirname=$(basename "$cwd")
  dir_seg="${DT}${dirname}${N}"
fi

# --- Git ---
git_seg=""
if [ -d "${cwd}/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" describe --tags --exact-match 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    if git -C "$cwd" diff --quiet 2>/dev/null && git -C "$cwd" diff --cached --quiet 2>/dev/null; then
      git_seg="${G}${branch}${N}"
    else
      git_seg="${G}${branch} *${N}"
    fi
  fi
fi

# --- GitHub CI Status (cached 60s) ---
gh_seg=""
if [ -n "$cwd" ] && command -v gh >/dev/null 2>&1; then
  gh_cache="$HOME/.claude/hooks/gh_status_cache"
  gh_cache_key="${cwd}__$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)"
  now=$(date +%s)
  cached="" cache_age=999
  if [ -f "$gh_cache" ]; then
    cache_ts=$(head -1 "$gh_cache" | cut -f1)
    cache_key=$(head -1 "$gh_cache" | cut -f2)
    cache_age=$((now - cache_ts))
    if [ "$cache_age" -lt 60 ] && [ "$cache_key" = "$gh_cache_key" ]; then
      cached=$(tail -1 "$gh_cache")
    fi
  fi
  if [ -z "$cached" ] && [ -n "$gh_cache_key" ]; then
    # Run gh in background-safe way with timeout
    cached=$(cd "$cwd" && timeout 3 gh run list --branch "$(git symbolic-ref --short HEAD 2>/dev/null)" --limit 1 --json status,conclusion --jq '.[0] | if .conclusion then .conclusion else .status end' 2>/dev/null) || cached=""
    if [ -n "$cached" ]; then
      printf '%s\t%s\n%s' "$now" "$gh_cache_key" "$cached" > "$gh_cache"
    fi
  fi
  if [ -n "$cached" ]; then
    case "$cached" in
      success)    gh_seg="${DT}ci:ok${N}" ;;
      failure)    gh_seg="${R}ci:fail${N}" ;;
      in_progress|queued|waiting|pending)
                  gh_seg="${Y}ci:run${N}" ;;
      cancelled)  gh_seg="${S}ci:skip${N}" ;;
      *)          gh_seg="${S}ci:${cached}${N}" ;;
    esac
  fi
fi

# --- Rate Limits ---
five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

color_pct() {
  p=$(printf '%.0f' "$1" 2>/dev/null || echo 0)
  if [ "$p" -ge 80 ]; then printf '%b' "$R"
  elif [ "$p" -ge 60 ]; then printf '%b' "$Y"
  else printf '%b' "$M"
  fi
}

elapsed_pct() {
  reset_ts=$1; window_secs=$2; now_ts=$3
  elapsed=$(( now_ts - (reset_ts - window_secs) ))
  [ "$elapsed" -lt 0 ] && elapsed=0
  [ "$elapsed" -gt "$window_secs" ] && elapsed=$window_secs
  printf '%d' $(( elapsed * 100 / window_secs ))
}

limits=""
now=$(date +%s)
if [ -n "$week" ]; then
  pct_int=$(printf '%.0f' "$week")
  clr=$(color_pct "$week")
  time_part=""
  if [ -n "$week_reset" ]; then
    ep=$(elapsed_pct "$week_reset" 604800 "$now")
    time_part="(${ep}%)"
  fi
  limits="${clr}7d:${pct_int}%${time_part}${N}"
fi
if [ -n "$five" ]; then
  pct_int=$(printf '%.0f' "$five")
  clr=$(color_pct "$five")
  time_part=""
  if [ -n "$five_reset" ]; then
    ep=$(elapsed_pct "$five_reset" 18000 "$now")
    time_part="(${ep}%)"
  fi
  limits="${limits:+${limits}${sep}}${clr}5h:${pct_int}%${time_part}${N}"
fi

# --- Cache idle timer (5m TTL, default since 2026-03-06) ---
cache_state="$HOME/.claude/hooks/cache_last_active"
cache_seg=""
if [ -f "$cache_state" ]; then
  last_active=$(cat "$cache_state" 2>/dev/null)
  if [ -n "$last_active" ]; then
    idle=$(( now - last_active ))
    remain=$(( 300 - idle ))
    if [ "$remain" -le 0 ]; then
      cache_seg="${R}gone${N}"
    else
      expire_ts=$(( last_active + 300 ))
      expire_mmss=$(date -r "$expire_ts" +"%M'%S\"" 2>/dev/null)
      if [ "$remain" -ge 180 ]; then cache_seg="${M}${expire_mmss}${N}"
      elif [ "$remain" -ge 60 ]; then cache_seg="${Y}${expire_mmss}${N}"
      else cache_seg="${R}${expire_mmss}${N}"
      fi
    fi
  fi
fi
printf '%s' "$now" > "$cache_state"

# --- Assemble ---
out="$model_seg"
[ -n "$ctx_seg" ] && out="${out}${sep}${ctx_seg}"
[ -n "$dir_seg" ] && out="${out}${sep}${dir_seg}"
[ -n "$git_seg" ] && out="${out}${sep}${git_seg}"
[ -n "$gh_seg" ] && out="${out}${sep}${gh_seg}"
[ -n "$cache_seg" ] && out="${out}${sep}${cache_seg}"
[ -n "$limits" ] && out="${out}${sep}${limits}"

printf '%b' "$out"
