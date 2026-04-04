#!/bin/zsh
# Comprehensive Claude Code statusline - all available fields except worktree
# Uses Nerd Font icons (requires a Nerd Font in your terminal)
input=$(cat)

# Colors
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[2m'; BOLD='\033[1m'; MAGENTA='\033[35m'; BLUE='\033[34m'; RESET='\033[0m'

# Nerd Font icons
ICO_FOLDER=$'\uf07b'       # nf-fa-folder
ICO_BRANCH=$'\ue725'       # nf-dev-git_branch
ICO_DOLLAR=$'\uf155'       # nf-fa-dollar
ICO_CLOCK=$'\uf017'        # nf-fa-clock
ICO_CODE=$'\uf121'         # nf-fa-code
ICO_WARN=$'\uf071'         # nf-fa-warning
ICO_TAG=$'\uf02b'          # nf-fa-tag
ICO_PLUS=$'\uf067'         # nf-fa-plus
ICO_MINUS=$'\uf068'        # nf-fa-minus

# --- Extract all fields ---
MODEL_ID=$(echo "$input" | jq -r '.model.id // "unknown"')
MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
VERSION=$(echo "$input" | jq -r '.version // "?"')
SESSION_ID=$(echo "$input" | jq -r '.session_id // ""' | cut -c1-8)
SESSION_NAME=$(echo "$input" | jq -r '.session_name // empty' 2>/dev/null)
OUTPUT_STYLE=$(echo "$input" | jq -r '.output_style.name // "default"')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty' 2>/dev/null)
AGENT_NAME=$(echo "$input" | jq -r '.agent.name // empty' 2>/dev/null)

# Workspace
DIR=$(echo "$input" | jq -r '.workspace.current_dir // "?"')
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // "?"')
ADDED_DIRS=$(echo "$input" | jq -r '.workspace.added_dirs // [] | length')

# Cost
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
API_DURATION_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# Context window
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
REMAINING=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100' | cut -d. -f1)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
TOTAL_IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
EXCEEDS_200K=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')

# Rate limits
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
FIVE_H_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
WEEK=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
WEEK_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

# --- Format helpers ---
format_duration() {
    local ms=$1
    local sec=$((ms / 1000))
    local min=$((sec / 60))
    local s=$((sec % 60))
    if [ "$min" -gt 0 ]; then echo "${min}m ${s}s"; else echo "${s}s"; fi
}

format_tokens() {
    local t=$1
    if [ "$t" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $t / 1000000" | bc)"
    elif [ "$t" -ge 1000 ]; then
        printf "%.1fk" "$(echo "scale=1; $t / 1000" | bc)"
    else
        echo "$t"
    fi
}

# Context bar color
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Progress bar
BAR_WIDTH=15
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /█}"
[ "$EMPTY" -gt 0 ] && printf -v PAD "%${EMPTY}s" && BAR="${BAR}${PAD// /░}"

# Git info (cached)
CACHE_FILE="/tmp/claude-statusline-git-cache"
CACHE_MAX_AGE=5
cache_stale() {
    [ ! -f "$CACHE_FILE" ] || [ $(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}
if cache_stale; then
    if git rev-parse --git-dir > /dev/null 2>&1; then
        BRANCH=$(git branch --show-current 2>/dev/null)
        STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        echo "$BRANCH|$STAGED|$MODIFIED" > "$CACHE_FILE"
    else
        echo "||" > "$CACHE_FILE"
    fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED < "$CACHE_FILE"

# --- Line 1: Model, session, workspace, git ---
L1="${CYAN}${BOLD}[${MODEL}]${RESET}"
L1="${L1} ${DIM}v${VERSION}${RESET}"
[ -n "$SESSION_NAME" ] && L1="${L1} ${MAGENTA}${ICO_TAG} ${SESSION_NAME}${RESET}" || L1="${L1} ${DIM}#${SESSION_ID}${RESET}"
[ -n "$AGENT_NAME" ] && L1="${L1} ${YELLOW}${ICO_CODE} ${AGENT_NAME}${RESET}"
[ -n "$VIM_MODE" ] && L1="${L1} ${BLUE}[${VIM_MODE}]${RESET}"
[ "$OUTPUT_STYLE" != "default" ] && L1="${L1} ${DIM}style:${OUTPUT_STYLE}${RESET}"
L1="${L1} | ${ICO_FOLDER} ${DIR##*/}"
[ "$DIR" != "$PROJECT_DIR" ] && L1="${L1} ${DIM}(proj: ${PROJECT_DIR##*/})${RESET}"
[ "$ADDED_DIRS" -gt 0 ] && L1="${L1} ${DIM}+${ADDED_DIRS} dirs${RESET}"
if [ -n "$BRANCH" ]; then
    GIT_INFO="${ICO_BRANCH} ${BRANCH}"
    [ "$STAGED" -gt 0 ] && GIT_INFO="${GIT_INFO} ${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] && GIT_INFO="${GIT_INFO} ${YELLOW}~${MODIFIED}${RESET}"
    L1="${L1} | ${GIT_INFO}"
fi
echo -e "$L1"

# --- Line 2: Context bar, cost, duration, lines changed ---
L2="${BAR_COLOR}${BAR}${RESET} ${PCT}%"
[ "$EXCEEDS_200K" = "true" ] && L2="${L2} ${RED}${ICO_WARN} >200k${RESET}"
CTX_SIZE_FMT=$(format_tokens "$CTX_SIZE")
L2="${L2} ${DIM}(${CTX_SIZE_FMT} window)${RESET}"
L2="${L2} | in:$(format_tokens "$TOTAL_IN") out:$(format_tokens "$TOTAL_OUT")"
COST_FMT=$(printf '$%.2f' "$COST")
L2="${L2} | ${YELLOW}${ICO_DOLLAR} ${COST_FMT}${RESET}"
L2="${L2} | ${ICO_CLOCK} $(format_duration "$DURATION_MS") ${DIM}(api: $(format_duration "$API_DURATION_MS"))${RESET}"
L2="${L2} | ${GREEN}${ICO_PLUS}${LINES_ADDED}${RESET}/${RED}${ICO_MINUS}${LINES_REMOVED}${RESET}"

# Rate limits
LIMITS=""
if [ -n "$FIVE_H" ]; then
    FH=$(printf '%.0f' "$FIVE_H")
    LIMITS="5h:${FH}%"
fi
if [ -n "$WEEK" ]; then
    WK=$(printf '%.0f' "$WEEK")
    LIMITS="${LIMITS:+$LIMITS }7d:${WK}%"
fi
[ -n "$LIMITS" ] && L2="${L2} | ${LIMITS}"

echo -e "$L2"
