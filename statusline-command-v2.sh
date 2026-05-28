#!/bin/bash
# Claude Code statusline — capsule-style powerline
# No npx, no node, no race condition

input=$(cat)

# ── Extract data ──
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // empty')
dir_name=$(basename "$current_dir")
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# 5h rolling rate-limit window (Claude.ai Pro/Max only, populated after first API response)
session_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
session_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')


# ── Git info ──
git_branch=""
git_dirty=""
git_ahead=""
git_behind=""
git_operation=""

if [ -n "$current_dir" ] && git -C "$current_dir" -c gc.autodetach=false rev-parse --git-dir > /dev/null 2>&1; then
git_dir=$(git -C "$current_dir" -c gc.autodetach=false rev-parse --git-dir 2>/dev/null)
branch=$(git -C "$current_dir" -c gc.autodetach=false branch --show-current 2>/dev/null)
[ -n "$branch" ] && git_branch="$branch"

if ! git -C "$current_dir" -c gc.autodetach=false diff --quiet 2>/dev/null || \
! git -C "$current_dir" -c gc.autodetach=false diff --cached --quiet 2>/dev/null; then
git_dirty=" !"
fi

upstream_status=$(git -C "$current_dir" -c gc.autodetach=false rev-list --left-right --count "@{upstream}...HEAD" 2>/dev/null)
if [ -n "$upstream_status" ]; then
behind_count=$(echo "$upstream_status" | awk '{print $1}')
ahead_count=$(echo "$upstream_status" | awk '{print $2}')
[ "$ahead_count" -gt 0 ] 2>/dev/null && git_ahead=" ↑$ahead_count"
[ "$behind_count" -gt 0 ] 2>/dev/null && git_behind=" ↓$behind_count"
fi

if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
git_operation=" REBASE"
elif [ -f "$git_dir/MERGE_HEAD" ]; then
git_operation=" MERGE"
elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
git_operation=" CHERRY-PICK"
elif [ -f "$git_dir/BISECT_LOG" ]; then
git_operation=" BISECT"
elif [ -f "$git_dir/REVERT_HEAD" ]; then
git_operation=" REVERT"
fi
fi

# ── Truecolor palette ──
DIR_BG="58;110;161"; DIR_FG="229;224;222" # #c36244 / #e5e0de
GIT_CLEAN_BG="115;191;159"; GIT_CLEAN_FG="46;52;64" # #069e5f / #ebefe4
GIT_DIRTY_BG="211;186;85"; GIT_DIRTY_FG="46;52;64" # #c9a929 / #2e3440
MODEL_BG="200;134;116"; MODEL_FG="46;52;64" # #bf616a / #f4e8e9

# Context tiers
CTX_BG="163;191;220"; CTX_FG="30;32;48" # #82aaff / #1e2030 (healthy)
CTX_WARN_BG="208;135;112"; CTX_WARN_FG="46;52;64" # #d08770 / #2e3440 (warning)
CTX_CRIT_BG="191;97;106"; CTX_CRIT_FG="236;239;244" # #bf616a / #eceff4 (critical)

SESSION_BG="136;121;178"; SESSION_FG="236;239;244" # #8879b2 / #eceff4 (session window)

# ── Glyphs (Nerd Font) ──
arrow=$'\uE0B4'
left_cap=$'\uE0B6'
branch_icon=$'\uF1D3'
# folder_icon=$'\uF115'
ctx_icon=$'\uF012'
session_icon=$'\uF017'

# ── Segment helpers ──
prev_bg=""
segment() {
local bg="$1" fg="$2" text="$3"
if [ -n "$prev_bg" ]; then
printf "\033[38;2;%sm\033[48;2;%sm%s" "$prev_bg" "$bg" "$arrow"
else
printf "\033[38;2;%sm%s" "$bg" "$left_cap"
fi
printf "\033[48;2;%sm\033[38;2;%sm %s \033[0m" "$bg" "$fg" "$text"
prev_bg="$bg"
}
end_line() {
if [ -n "$prev_bg" ]; then
printf "\033[0m\033[38;2;%sm%s\033[0m" "$prev_bg" "$arrow"
fi
}

# ── Render ──
segment "$DIR_BG" "$DIR_FG" "$dir_name"

if [ -n "$git_branch" ]; then
git_text="${branch_icon} ${git_branch}${git_ahead}${git_behind}${git_dirty}${git_operation}"
if [ -n "$git_dirty" ] || [ -n "$git_operation" ]; then
segment "$GIT_DIRTY_BG" "$GIT_DIRTY_FG" "$git_text"
else
segment "$GIT_CLEAN_BG" "$GIT_CLEAN_FG" "$git_text"
fi
fi

# Model — always its own segment with its own color
segment "$MODEL_BG" "$MODEL_FG" " $model_name"

# Context — separate segment that recolors by tier
if [ -n "$remaining" ]; then
remaining_int=$(printf "%.0f" "$remaining")
if [ "$remaining_int" -le 25 ]; then
seg_bg="$CTX_CRIT_BG"; seg_fg="$CTX_CRIT_FG"
elif [ "$remaining_int" -le 55 ]; then
seg_bg="$CTX_WARN_BG"; seg_fg="$CTX_WARN_FG"
else
seg_bg="$CTX_BG"; seg_fg="$CTX_FG"
fi
segment "$seg_bg" "$seg_fg" "${ctx_icon} ${remaining_int}%"
fi

# Session window — 5h rolling rate-limit (Pro/Max only)
if [ -n "$session_used" ]; then
session_int=$(printf "%.0f" "$session_used")
if [ "$session_int" -ge 90 ]; then
sw_bg="$CTX_CRIT_BG"; sw_fg="$CTX_CRIT_FG"
elif [ "$session_int" -ge 75 ]; then
sw_bg="$CTX_WARN_BG"; sw_fg="$CTX_WARN_FG"
else
sw_bg="$SESSION_BG"; sw_fg="$SESSION_FG"
fi
sw_text="${session_icon} ${session_int}%"
if [ -n "$session_resets" ]; then
now_epoch=$(date +%s)
secs_left=$(( session_resets - now_epoch ))
if [ "$secs_left" -gt 0 ]; then
rh=$(( secs_left / 3600 ))
rm=$(( (secs_left % 3600) / 60 ))
if [ "$rh" -gt 0 ]; then
sw_text="${sw_text} (${rh}h${rm}m)"
else
sw_text="${sw_text} (${rm}m)"
fi
fi
fi
segment "$sw_bg" "$sw_fg" "$sw_text"
fi

end_line
printf "\n"
