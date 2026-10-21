#!/usr/bin/env bash
# Claude Code statusline: one jq call, one git call (cached per directory).
# Requires: bash 3.2+, jq 1.6+, git 2.11+. Works on macOS and Linux.

# --- Parse everything in a single jq pass -----------------------------------
# Fields are joined with \x1f (unit separator) so empty values survive `read`.
DATA=$(jq -r '
  def clean: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; "");  # no terminal escapes
  def tok: if . >= 1000000 then "\((. / 100000 | floor) / 10)M"
           elif . >= 1000 then "\((. / 100 | floor) / 10)k"
           else tostring end;
  def dur: (. / 1000 | floor) as $s
           | if $s >= 60 then "\($s / 60 | floor)m \($s % 60)s" else "\($s)s" end;
  def pct: [[(.context_window.used_percentage // 0 | floor), 0] | max, 100] | min;
  def lim($n; $k): if .rate_limits[$k].used_percentage then
                     "\($n):\(.rate_limits[$k].used_percentage | round)%" else empty end;
  [ (.model.display_name // "unknown" | clean),
    (.version // "?" | clean),
    ((.session_name // "" | clean) as $name
     | if $name != "" then "@" + $name
       else "#" + (.session_id // "" | clean | .[0:8]) end),
    (.agent.name // "" | clean),
    (.vim.mode // "" | clean),
    (.output_style.name // "default" | clean),
    (.workspace.current_dir // "" | clean),
    (.workspace.project_dir // "" | clean),
    (.workspace.added_dirs // [] | length),
    (pct),
    (pct * 15 / 100 | floor | [range(.)  | "█"] + [range(15 - .) | "░"] | join("")),
    (.context_window.context_window_size // 200000 | tok),
    (.context_window.total_input_tokens // 0 | tok),
    (.context_window.total_output_tokens // 0 | tok),
    ((.cost.total_cost_usd // 0) * 100 | round
       | "\(. / 100 | floor).\(. % 100 | tostring | if length < 2 then "0" + . else . end)"),
    (.cost.total_duration_ms // 0 | dur),
    (.cost.total_api_duration_ms // 0 | dur),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.exceeds_200k_tokens // false),
    ([lim("5h"; "five_hour"), lim("7d"; "seven_day")] | join(" "))
  ] | map(tostring) | join("\u001f")' 2>/dev/null) && [ -n "$DATA" ] \
  || { echo "statusline: unreadable input"; exit 0; }
IFS=$'\x1f' read -r MODEL VERSION SESSION AGENT VIM STYLE DIR PROJ ADDED \
  PCT BAR CTX TOK_IN TOK_OUT COST DUR API_DUR ADD DEL OVER LIMITS <<< "$DATA"

# --- Colors & icons (hex UTF-8 bytes: portable to macOS bash 3.2) -----------
C=$'\e[36m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' M=$'\e[35m' B=$'\e[34m'
D=$'\e[2m' BOLD=$'\e[1m' X=$'\e[0m'
I_DIR=$'\xf0\x9f\x93\x81' I_GIT=$'\xf0\x9f\x8c\xbf' I_COST=$'\xf0\x9f\x92\xb0'
I_TIME=$'\xe2\x8f\xb0' I_BOT=$'\xf0\x9f\xa4\x96' I_WARN=$'\xf0\x9f\x9a\xa8'
I_TAG=$'\xf0\x9f\x93\x8c'

# --- Git: one `git status` call, cached 5s per directory --------------------
git_info() {
  local dir=${DIR:-$PWD} now cache key ts
  now=$(date +%s)
  key=$(printf '%s' "$dir" | cksum)
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/${key%% *}"
  if [ -f "$cache" ]; then
    IFS='|' read -r ts BRANCH STAGED MODIFIED < "$cache"
    [ $((now - ${ts:-0})) -le 5 ] && return
  fi
  # porcelain v2: "1 XY ..." / "2 XY ..." entries; X=index, Y=worktree ('.' = clean).
  # "u ..." is a merge conflict: counted once as staged and once as modified.
  # A detached HEAD shows no branch, like `git branch --show-current`.
  IFS='|' read -r BRANCH STAGED MODIFIED < <(
    git -C "$dir" status --porcelain=v2 --branch 2>/dev/null | awk '
      /^# branch.head / { if ($3 != "(detached)") b = $3 }
      /^[12] /          { if (substr($2,1,1) != ".") s++; if (substr($2,2,1) != ".") m++ }
      /^u /             { s++; m++ }
      END               { printf "%s|%d|%d\n", b, s, m }')
  mkdir -p "${cache%/*}" && printf '%s|%s|%s|%s\n' "$now" "$BRANCH" "$STAGED" "$MODIFIED" > "$cache"
}
git_info

# --- Line 1 ------------------------------------------------------------------
L1="$C$BOLD[$MODEL]$X ${D}v$VERSION$X"
case $SESSION in @*) L1+=" $M$I_TAG ${SESSION#@}$X" ;; *) L1+=" $D$SESSION$X" ;; esac
[ -n "$AGENT" ] && L1+=" $Y$I_BOT $AGENT$X"
[ -n "$VIM" ]   && L1+=" $B[$VIM]$X"
[ "$STYLE" != default ] && L1+=" ${D}style:$STYLE$X"
SHOWN_DIR=${DIR:-?}
L1+=" | $I_DIR ${SHOWN_DIR##*/}"
[ -n "$PROJ" ] && [ "$DIR" != "$PROJ" ] && L1+=" $D(proj: ${PROJ##*/})$X"
[ "$ADDED" -gt 0 ] && L1+=" $D+$ADDED dirs$X"
if [ -n "$BRANCH" ]; then
  L1+=" | $I_GIT $BRANCH"
  [ "${STAGED:-0}" -gt 0 ]   && L1+=" $G+$STAGED$X"
  [ "${MODIFIED:-0}" -gt 0 ] && L1+=" $Y~$MODIFIED$X"
fi

# --- Line 2 ------------------------------------------------------------------
if   [ "$PCT" -ge 90 ]; then BC=$R
elif [ "$PCT" -ge 70 ]; then BC=$Y
else BC=$G; fi

L2="$BC$BAR$X $PCT%"
[ "$OVER" = true ] && L2+=" $R$I_WARN >200k$X"
L2+=" $D($CTX window)$X | in:$TOK_IN out:$TOK_OUT"
L2+=" | $Y$I_COST \$$COST$X | $I_TIME $DUR $D(api: $API_DUR)$X"
L2+=" | $G+$ADD$X/$R-$DEL$X"
[ -n "$LIMITS" ] && L2+=" | $LIMITS"

printf '%s\n%s\n' "$L1" "$L2"
