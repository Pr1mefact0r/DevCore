#!/usr/bin/env bash
# {{PROJECT_NAME}}-Dev statusline (DevCore v3.0)
# Dual-frame layout when in dev context (dev/ dir + v_* dir present).
# Reads counts from dev/documentation.db via sqlite3.
# Falls back to a generic single-frame otherwise.
#
# Backport: replace PROJECT_NAME / RUNTIME_PREFIX per project.
PROJECT_NAME="{{PROJECT_NAME}}"
RUNTIME_PREFIX="{{PREFIX}}"   # runtime skill prefix, e.g. "mp", "ww", "cc"

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remain_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

fmt_tokens() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" = "null" ]; then echo "?"
    elif [ "$n" -ge 1000000 ] 2>/dev/null; then LC_NUMERIC=C printf "%.1fM" "$(LC_NUMERIC=C echo "scale=1; $n / 1000000" | bc)"
    elif [ "$n" -ge 1000 ] 2>/dev/null; then LC_NUMERIC=C printf "%.1fk" "$(LC_NUMERIC=C echo "scale=1; $n / 1000" | bc)"
    else echo "$n"
    fi
}

input_tok=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
output_tok=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // empty')
in_fmt=$(fmt_tokens "$input_tok")
out_fmt=$(fmt_tokens "$output_tok")

RST='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
CYN='\033[36m'; GRN='\033[32m'; YEL='\033[33m'; RED='\033[31m'
MAG='\033[35m'; BLU='\033[34m'; WHT='\033[37m'
BCYN='\033[96m'; BGRN='\033[92m'; BYEL='\033[93m'; BRED='\033[91m'
BMAG='\033[95m'; BWHT='\033[97m'; BBLU='\033[94m'

TL='╭' TR='╮' BL='╰' BR='╯' H='─' V='│'

mk_hline() {
    local l="$1" r="$2" w="$3"
    local line=""
    for ((i=0; i<w; i++)); do line+="$H"; done
    printf '%b' "${DIM}${CYN}${l}${line}${r}${RST}"
}

mk_line() {
    local content="$1" w="$2"
    local rendered
    rendered=$(printf '%b' "$content")
    local stripped
    stripped=$(printf '%s' "$rendered" | sed 's/\x1b\[[0-9;]*m//g')
    local vl=${#stripped}
    local pad=$((w - vl))
    [ "$pad" -lt 0 ] && pad=0
    local border
    border=$(printf '%b' "${DIM}${CYN}${V}${RST}")
    printf '%s%s%*s%s' "$border" "$rendered" "$pad" "" "$border"
}

BOX_W=62
box_line() { printf '%s\n' "$(mk_line "$1" "$BOX_W")"; }
box_top()  { printf '%s\n' "$(mk_hline "$TL" "$TR" "$BOX_W")"; }
box_sep()  { printf '%s\n' "$(mk_hline "├" "┤" "$BOX_W")"; }
box_bot()  { printf '%s\n' "$(mk_hline "$BL" "$BR" "$BOX_W")"; }

bar_fill="████████████████████"
if [ -n "$used_pct" ]; then
    pct_int="${used_pct%.*}"
    if [ "$pct_int" -ge 80 ] 2>/dev/null; then ctx_color="${BOLD}${RED}"
    elif [ "$pct_int" -ge 50 ] 2>/dev/null; then ctx_color="${YEL}"
    else ctx_color="${GRN}"; fi
    filled=$((pct_int / 5)); empty=$((20 - filled))
    ctx_bar="${ctx_color}${bar_fill:0:$filled}${DIM}${WHT}${bar_fill:0:$empty}${RST}"
    ctx_str="${ctx_color}${used_pct}%${RST} ${DIM}(${in_fmt}in/${out_fmt}out)${RST}"
else
    ctx_bar="${DIM}────────────────────${RST}"
    ctx_str="${DIM}no data${RST}"
fi

if [ -n "$remain_pct" ]; then
    remain_int="${remain_pct%.*}"
    ac_effective=$((remain_int - 17))
    [ "$ac_effective" -lt 0 ] && ac_effective=0
    if [ "$ac_effective" -le 10 ] 2>/dev/null; then ac_color="${BOLD}${RED}"
    elif [ "$ac_effective" -le 25 ] 2>/dev/null; then ac_color="${YEL}"
    else ac_color="${GRN}"; fi
    ac_filled=$((ac_effective / 5)); ac_empty=$((20 - ac_filled))
    ac_bar="${ac_color}${bar_fill:0:$ac_filled}${DIM}${WHT}${bar_fill:0:$ac_empty}${RST}"
    ac_str="${ac_color}${ac_effective}%${RST} ${DIM}remaining${RST}"
else
    ac_bar="${DIM}────────────────────${RST}"
    ac_str="${DIM}no data${RST}"
fi

# Helper: count via sqlite3 if DB exists, else "?"
db_count() {
    local sql="$1"
    local db="$2"
    if [ -f "$db" ] && command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$db" "$sql" 2>/dev/null || echo "?"
    else
        echo "?"
    fi
}

# =====================================================================
# Dev — dual frame layout (dev/ + v_* exists)
# =====================================================================
_latest=$(find "$cwd" -maxdepth 1 -type d -name 'v_*' 2>/dev/null | sort -V | tail -1)
if [ -d "$cwd/dev" ] && [ -n "$_latest" ]; then
    latest="$_latest"
    if [ -f "$latest/VERSION" ]; then
        fw=$(grep '^framework=' "$latest/VERSION" 2>/dev/null | cut -d= -f2)
    fi
    fw="${fw:-?}"

    DB="$cwd/dev/documentation.db"
    bugs=$(db_count "SELECT COUNT(*) FROM bugs WHERE status='open';" "$DB")
    obs=$(db_count "SELECT COUNT(*) FROM observations WHERE status IN ('watching','fix_deployed_monitoring');" "$DB")
    decisions=$(db_count "SELECT COUNT(*) FROM decisions;" "$DB")
    targets_open=$(db_count "SELECT COUNT(*) FROM next_targets WHERE status IN ('open','in_progress');" "$DB")

    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    dev_skills=$(ls -d "$latest/.claude/skills"/dev-*/SKILL.md 2>/dev/null | wc -l)
    # runtime-skills segment: only when RUNTIME_PREFIX is a real, resolved prefix (not empty and
    # not the unresolved {{PREFIX}} placeholder — detected by a literal brace) and ≥1 such skill exists.
    rt_seg=""
    case "$RUNTIME_PREFIX" in
        ""|*'{'*) : ;;
        *) rt_skills=$(ls -d "$latest/.claude/skills"/${RUNTIME_PREFIX}-*/SKILL.md 2>/dev/null | wc -l)
           [ "$rt_skills" -gt 0 ] 2>/dev/null && rt_seg="  ${DIM}${RUNTIME_PREFIX}-skills${RST} ${BWHT}${rt_skills}${RST}" ;;
    esac

    if [ "$bugs" != "?" ] && [ "$bugs" -gt 0 ] 2>/dev/null; then bug_str="${BYEL}${bugs}${RST}"; else bug_str="${GRN}${bugs}${RST}"; fi
    if [ "$obs" != "?" ] && [ "$obs" -gt 0 ] 2>/dev/null; then obs_str="${BCYN}${obs}${RST}"; else obs_str="${GRN}${obs}${RST}"; fi

    # Top targets from DB
    targets=()
    if [ -f "$DB" ] && command -v sqlite3 >/dev/null 2>&1; then
        while IFS='|' read -r prio title; do
            [ -z "$title" ] && continue
            [ "${#title}" -gt 52 ] && title="${title:0:49}..."
            targets+=("${prio}|${title}")
        done < <(sqlite3 "$DB" "SELECT priority, title FROM next_targets WHERE status IN ('open','in_progress') ORDER BY priority ASC, id ASC LIMIT 5;" 2>/dev/null)
    fi

    L_W=62
    L=()
    L+=("$(mk_hline "$TL" "$TR" $L_W)")
    L+=("$(mk_line "  ${BOLD}${BYEL}${PROJECT_NAME}${RST}${DIM} — Dev${RST}  ${BGRN}v${fw}${RST}  ${BMAG}@${branch}${RST}" $L_W)")
    L+=("$(mk_hline "├" "┤" $L_W)")
    L+=("$(mk_line "  ${DIM}dev-skills${RST} ${BWHT}${dev_skills}${RST}${rt_seg}  ${bug_str}${DIM} bugs${RST}  ${obs_str}${DIM} obs${RST}" $L_W)")
    L+=("$(mk_line "  ${BBLU}${model}${RST}" $L_W)")
    L+=("$(mk_hline "├" "┤" $L_W)")
    L+=("$(mk_line "  ${DIM}context   ${RST}${ctx_bar} ${ctx_str}" $L_W)")
    L+=("$(mk_line "  ${DIM}autocompact${RST}${ac_bar} ${ac_str}" $L_W)")
    L+=("$(mk_hline "$BL" "$BR" $L_W)")

    R_W=62
    R=()
    R+=("$(mk_hline "$TL" "$TR" $R_W)")
    R+=("$(mk_line "  ${BOLD}${BWHT}Next Targets${RST} ${DIM}(${targets_open} open)${RST}" $R_W)")
    R+=("$(mk_hline "├" "┤" $R_W)")
    for i in 0 1 2 3 4 5; do
        if [ "$i" -lt "${#targets[@]}" ]; then
            IFS='|' read -r prio title <<< "${targets[$i]}"
            if [ "$prio" = "1" ]; then
                R+=("$(mk_line "  ${BYEL}${prio}${RST}  ${BWHT}${title}${RST}" $R_W)")
            else
                R+=("$(mk_line "  ${WHT}${prio}${RST}  ${WHT}${title}${RST}" $R_W)")
            fi
        else
            R+=("$(mk_line "" $R_W)")
        fi
    done
    R+=("$(mk_hline "$BL" "$BR" $R_W)")

    gap="  "
    for i in "${!L[@]}"; do
        printf '%s%s%s\n' "${L[$i]}" "$gap" "${R[$i]:-}"
    done

# =====================================================================
# Generic — single frame (no v_* dir yet)
# =====================================================================
else
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    branch_str=""
    [ -n "$branch" ] && branch_str="${BMAG}@${branch}${RST}  "

    box_top
    box_line "  ${BOLD}${BYEL}${PROJECT_NAME}-Dev${RST}  ${branch_str}${BBLU}${model}${RST}"
    box_sep
    box_line "  ${DIM}context   ${RST}${ctx_bar} ${ctx_str}"
    box_line "  ${DIM}autocompact${RST}${ac_bar} ${ac_str}"
    box_bot
fi
