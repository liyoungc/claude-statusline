#!/bin/sh
# Claude Code statusline — ccline color scheme, no emoji
# Segments: Model [effort] | Ctx | Dir | Git | GH Status | cache | 5h 7d
input=$(cat)

# --- Color palettes (8 coordinated sets) ---------------------------------
# Each palette = "name M_color DT_color G_color C_color"
# (warning Y/R kept identical across all palettes for stable semantics)
palette_table() {
  cat <<'PALETTES'
cyan     51  35  39  207
ocean    38  49  75  81
forest   35  71  28  178
sunset   208 215 173 213
lavender 141 147 105 177
rose     211 218 175 220
gold     220 178 136 39
mono     252 248 244 244
PALETTES
}

# --- Pick palette for this session ---------------------------------------
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
palette_dir="$HOME/.claude/statusline_palette"
override_file="$palette_dir/$session_id"

palette_count=8
if [ -n "$session_id" ] && [ -f "$override_file" ]; then
  idx=$(cat "$override_file" 2>/dev/null)
elif [ -n "$session_id" ]; then
  # deterministic hash → same session always gets same color
  n=$(printf '%s' "$session_id" | cksum | awk '{print $1}')
  idx=$(( n % palette_count + 1 ))
else
  idx=1
fi
[ "$idx" -ge 1 ] 2>/dev/null && [ "$idx" -le "$palette_count" ] 2>/dev/null || idx=1

palette_row=$(palette_table | awk -v i="$idx" 'NR==i {print}')
pal_name=$(echo "$palette_row" | awk '{print $1}')
pal_m=$(echo "$palette_row"    | awk '{print $2}')
pal_dt=$(echo "$palette_row"   | awk '{print $3}')
pal_g=$(echo "$palette_row"    | awk '{print $4}')
pal_c=$(echo "$palette_row"    | awk '{print $5}')

# --- Colors (session palette + fixed warning colors) ---
M=$(printf  '\033[1;38;5;%sm' "$pal_m")   # model
DT=$(printf '\033[1;38;5;%sm' "$pal_dt")  # dir text
G=$(printf  '\033[1;38;5;%sm' "$pal_g")   # git
C=$(printf  '\033[1;38;5;%sm' "$pal_c")   # cost / accent
S='\033[37m'     # separator: white
Y='\033[1;33m'   # warning yellow (fixed)
R='\033[1;31m'   # critical red   (fixed)
N='\033[0m'      # reset

sep="${S} | ${N}"

# --- Model + reasoning effort -------------------------------------------
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
ctx_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty')

effort="${CLAUDE_EFFORT:-}"
if [ -z "$effort" ] && [ -f "$HOME/.claude/settings.json" ]; then
  effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
effort_tag=""
case "$effort" in
  xhigh)  effort_tag=" ${R}[X]${N}" ;;
  high)   effort_tag=" ${R}[H]${N}" ;;
  medium) effort_tag=" ${Y}[M]${N}" ;;
  low)    effort_tag=" ${DT}[L]${N}" ;;
  none)   effort_tag=" ${S}[-]${N}" ;;
esac

model_seg=""
if [ -n "$model" ]; then
  short=$(echo "$model" | sed -e 's/Claude //' -e 's/ ([0-9]*[KMG][^ )]*[^)]*)$//')
  if [ "$ctx_size" = "1000000" ]; then
    model_seg="${M}${short} (1M)${N}${effort_tag}"
  elif [ -n "$ctx_size" ]; then
    model_seg="${M}${short} ($((ctx_size/1000))K)${N}${effort_tag}"
  else
    model_seg="${M}${short}${N}${effort_tag}"
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
  else printf '%b' "$C"
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
      if [ "$remain" -ge 180 ]; then cache_seg="${C}${expire_mmss}${N}"
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
