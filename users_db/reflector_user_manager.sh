#!/bin/bash
# =============================================================================
# Unified XLX Reflector users management tool
# Features: RadioID database | whitelist | dashboard access (htpasswd) | passwords
#
# Input wildcards available in entry fields:
#   X  → cancels the current operation and returns to the previous menu
#   -  → (DMRID field only) clears the DMRID from the record
# =============================================================================

# --------------------------------------------
# CONFIGURATION — adjust paths if necessary
# --------------------------------------------
DB_FILE="/xlxd/users_db/users_base.csv"
HTPASSWD="/var/www/restricted/.htpasswd"
PENDING_FILE="/var/www/restricted/pendentes.txt"
WHITELIST="/xlxd/xlxd.whitelist"
CREATE_DB_PHP="/xlxd/users_db/create_user_db.php"

ESCAPE="X"
CLEAR="-"
MAX_W=70        # maximum desired width in columns

# --------------------------------------------
# COLORS
# --------------------------------------------
RST=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
CYAN=$'\e[36m'
BCYAN=$'\e[1;36m'
BYELLOW=$'\e[1;33m'
GREEN=$'\e[32m'
BGREEN=$'\e[1;32m'
RED=$'\e[31m'
BRED=$'\e[1;31m'
MAGENTA=$'\e[35m'
WHITE=$'\e[37m'
BWHITE=$'\e[1;37m'

# --------------------------------------------
# DYNAMIC WIDTH
# Capped at the lesser of the real terminal width and MAX_W.
# Recalculated on SIGWINCH (terminal resize).
# --------------------------------------------
LBL_W=10   # label column width inside the record box

setup_width() {
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    (( cols > MAX_W )) && cols=$MAX_W
    COLS=$cols

    # Separator line length (COLS - 2 indent spaces)
    local sep_len=$(( COLS - 2 ))
    SEP_LINE=$(printf '%*s' "$sep_len" '' | sed 's/ /═/g')

    # Horizontal bar inside the record box (between ┌ and ┐): COLS - 4
    local box_bar=$(( COLS - 4 ))
    BOX_BAR=$(printf '%*s' "$box_bar" '' | sed 's/ /─/g')

    # Value width inside the record box:
    # layout: "  │ " + LBL(10) + " " + VAL + " │"
    # total  = 2 + 1 + 1 + 10 + 1 + VAL_W + 1 + 1 = VAL_W + 17 = COLS
    VAL_W=$(( COLS - LBL_W - 7 ))
    (( VAL_W < 1 )) && VAL_W=1

    # Inner width of the main banner (between ║ and ║): COLS - 4
    BANNER_IN=$(( COLS - 4 ))
}

trap 'setup_width' SIGWINCH
setup_width

# --------------------------------------------
# DISPLAY UTILITIES
# All colored output uses printf and ends with \n.
# NEVER include ANSI codes on the line where read waits for input.
# --------------------------------------------

separator() { printf "${CYAN}  %s${RST}\n" "$SEP_LINE"; }

header() {
    printf "\n"
    separator
    printf "${BCYAN}  %-*s${RST}\n" "$(( COLS - 2 ))" "$1"
    separator
}

ok()    { printf "${BGREEN}  ✔  ${GREEN}%s${RST}\n" "$*"; }
err()   { printf "${BRED}  ✘  ${RED}%s${RST}\n"    "$*"; }
warn()  { printf "${MAGENTA}  ⚠  %s${RST}\n"        "$*"; }
info()  { printf "${CYAN}  ✔  %s${RST}\n"              "$*"; }

# Truncate a string to maximum length
trunc() { printf '%s' "${1:0:$2}"; }

check_escape() {
    if [[ "${1^^}" == "${ESCAPE^^}" ]]; then
        printf "${MAGENTA}  ↩  Operation cancelled.${RST}\n"
        return 0
    fi
    return 1
}

validate_no_commas() {
    if [[ "$1" == *","* ]]; then
        err "Field cannot contain commas."; return 1
    fi
    return 0
}

validate_callsign() {
    local U="$1"
    if [[ ! "$U" =~ ^[A-Z0-9]{4,8}$ ]] || \
       [[ $(echo "$U" | grep -o '[0-9]' | wc -l) -gt 1 ]]; then
        err "Callsign: 4-8 uppercase characters, at most one digit."
        return 1
    fi
    return 0
}

generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' < /dev/urandom | head -c 12
}

add_to_pending() {
    local U="$1"
    if ! grep -q "^${U}$" "$PENDING_FILE" 2>/dev/null; then
        echo "$U" | sudo tee -a "$PENDING_FILE" > /dev/null
    fi
}

# =============================================================================
# INPUT FUNCTIONS
# Fixed pattern:
#   1. Colored printf of label/hint — ends with \n
#   2. printf of the input marker  — NO ANSI codes whatsoever
#   3. read -r into the variable
# =============================================================================

# Simple read with optional label and hint
# Usage: pread VARNAME "Label" "hint"
pread() {
    local _var="$1" _label="$2" _hint="${3:-}"
    printf "${BYELLOW}  %s${RST}  ${DIM}%s${RST}\n" "$_label" "$_hint"
    printf "  > "
    read -r "$_var"
}

# y/N confirmation
# Usage: pconfirm VARNAME "Message"
pconfirm() {
    local _var="$1" _msg="$2"
    printf "${BYELLOW}  %s${RST}  ${DIM}(y/N)${RST}\n" "$_msg"
    printf "  > "
    read -r "$_var"
}

# Read a field with pre-filled value (Enter keeps the current value)
# Usage: read_field VARNAME "Label" "current_value" [r=required]
# Returns 1 if escape was triggered
read_field() {
    local _var="$1" _label="$2" _current="$3" _required="${4:-}"
    local _hint _input

    if [[ -n "$_current" ]]; then
        _hint="[current: ${_current}] [${ESCAPE}=cancel]"
    else
        _hint="[${ESCAPE}=cancel]"
    fi

    while true; do
        printf "${BYELLOW}  %s${RST}  ${DIM}%s${RST}\n" "$_label" "$_hint"
        printf "  > "
        read -r _input
        check_escape "$_input" && return 1
        [[ -z "$_input" && -n "$_current" ]] && _input="$_current"
        validate_no_commas "$_input" || continue
        if [[ "$_required" == "r" && -z "$_input" ]]; then
            err "Required field."; continue
        fi
        printf -v "$_var" '%s' "$_input"
        return 0
    done
}

# --------------------------------------------
# CSV DATABASE HELPER FUNCTIONS
# --------------------------------------------

list_by_callsign() {
    local CALL="$1"

    mapfile -t _LINES < <(find_lines_by_call "$CALL")

    local total=${#_LINES[@]}

    if (( total == 0 )); then
        warn "No records found for ${CALL}."
        return
    fi

    local W_DMR=8 W_CALL=9 W_NAME=18 W_CITY=14
    local W_CTRY=$(( COLS - 2 - W_DMR - W_CALL - W_NAME - W_CITY ))
    (( W_CTRY < 6 )) && W_CTRY=6

    printf "\n"
    printf "${CYAN}  %-*s%-*s%-*s%-*s%-*s${RST}\n" \
        $W_DMR  "DMRID" \
        $W_CALL "CALLSIGN" \
        $W_NAME "NAME" \
        $W_CITY "CITY" \
        $W_CTRY "COUNTRY"
    separator

    for LN in "${_LINES[@]}"; do
        IFS=',' read -r _D _C _N _S _CI _E _P <<< "$(sed -n "${LN}p" "$DB_FILE")"
        _P="${_P%$'\r'}"
        local full_name="${_N} ${_S}"
        printf "  ${DIM}%-*s${RST}${BYELLOW}%-*s${RST}${WHITE}%-*s${RST}${DIM}%-*s%-*s${RST}\n" \
            $W_DMR  "$(trunc "$_D"        $(( W_DMR  - 1 )))" \
            $W_CALL "$(trunc "$_C"        $(( W_CALL - 1 )))" \
            $W_NAME "$(trunc "$full_name" $(( W_NAME - 1 )))" \
            $W_CITY "$(trunc "$_CI"       $(( W_CITY - 1 )))" \
            $W_CTRY "$(trunc "$_P"        $(( W_CTRY - 1 )))"
    done

    separator
    printf "${DIM}  %d record(s) found for "%s"${RST}\n" "$total" "$CALL"
}

find_lines_by_call() {
    awk -F',' -v call="$1" '$2 == call {print NR}' "$DB_FILE"
}

find_line_by_dmrid() {
    awk -F',' -v dmr="$1" '$1 == dmr {print NR; exit}' "$DB_FILE"
}

load_record() {
    local REG
    REG=$(sed -n "${1}p" "$DB_FILE")
    IFS=',' read -r F_DMRID F_CALL F_FIRSTNAME F_LASTNAME F_CITY F_STATE F_COUNTRY <<< "$REG"
}

display_record() {
    setup_width   # ensure up-to-date measurements
    local REG="$1"
    IFS=',' read -r _D _C _N _S _CI _E _P <<< "$REG"
    local full_name="$_N $_S"
    printf "${DIM}  ┌%s┐${RST}\n" "$BOX_BAR"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${BWHITE}%-*s${RST} ${DIM}│${RST}\n" \
        "$LBL_W" "DMRID:"    "$VAL_W" "$(trunc "$_D"        $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${BWHITE}%-*s${RST} ${DIM}│${RST}\n" \
        "$LBL_W" "Callsign:" "$VAL_W" "$(trunc "$_C"        $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "Name:"     "$VAL_W" "$(trunc "$full_name" $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "City:"     "$VAL_W" "$(trunc "$_CI"       $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "State:"    "$VAL_W" "$(trunc "$_E"        $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "Country:"  "$VAL_W" "$(trunc "$_P"        $VAL_W)"
    printf "${DIM}  └%s┘${RST}\n" "$BOX_BAR"
}

# --------------------------------------------
# DATABASE — CREATE SQL DATABASE
# --------------------------------------------
create_sql_database() {
    header "CREATE / UPDATE SQL DATABASE"
    printf "\n"
    info "Running: php ${CREATE_DB_PHP}"
    printf "\n"
    if sudo php "$CREATE_DB_PHP"; then
        printf "\n"; ok "SQL database created/updated successfully."
    else
        printf "\n"; err "Failed to run the PHP script (exit code: $?)."
    fi
}

# --------------------------------------------
# DATABASE — ADD / EDIT RECORD
# --------------------------------------------
add_or_edit_record() {
    header "ADD / EDIT RECORD"
    printf "${DIM}  Press Enter on a [current:] field to keep its value.${RST}\n\n"

    local EXISTING_LINE="" FOUND_BY=""
    local F_DMRID="" F_CALL="" F_FIRSTNAME="" F_LASTNAME="" F_CITY="" F_STATE="" F_COUNTRY=""
    local DMRID="" CALL="" FIRSTNAME="" LASTNAME="" CITY="" STATE="" COUNTRY=""

    # ── PHASE 1: SEARCH BY DMRID (optional) ─────────────────────────────────
    while true; do
        pread DMRID "DMRID (7 digits)" "[optional] [${ESCAPE}=cancel]"
        check_escape "$DMRID" && return
        validate_no_commas "$DMRID" || continue
        [[ -z "$DMRID" ]] && break

        if [[ ! "$DMRID" =~ ^[0-9]{7}$ ]]; then
            err "Invalid DMRID."; continue
        fi

        EXISTING_LINE=$(find_line_by_dmrid "$DMRID")
        if [[ -n "$EXISTING_LINE" ]]; then
            printf "\n"; info "Record found:"
            display_record "$(sed -n "${EXISTING_LINE}p" "$DB_FILE")"
            pconfirm RESP "Edit this record?"
            [[ "$RESP" =~ ^[yY]$ ]] || return
            load_record "$EXISTING_LINE"
            FOUND_BY="dmrid"
        fi
        break
    done

    # ── PHASE 2: SEARCH / CONFIRM BY CALLSIGN ───────────────────────────────
    while true; do
        local _hint_call="[required] [${ESCAPE}=cancel]"
        [[ -n "$F_CALL" ]] && _hint_call="[current: ${F_CALL}] [${ESCAPE}=cancel]"

        pread CALL "Callsign (up to 8 chars)" "$_hint_call"
        check_escape "$CALL" && return
        [[ -z "$CALL" && -n "$F_CALL" ]] && CALL="$F_CALL"
        CALL=$(echo "$CALL" | tr '[:lower:]' '[:upper:]')

        validate_no_commas "$CALL" || continue
        if [[ ! "$CALL" =~ ^[A-Z0-9]{1,8}$ ]]; then
            err "Invalid callsign."; continue
        fi

        LINE_MAP=( $(find_lines_by_call "$CALL") )

        if (( ${#LINE_MAP[@]} > 1 )); then
            printf "\n"; info "Multiple records found for ${BOLD}${CALL}${RST}:"; printf "\n"
            local IDX=1
            for LN in "${LINE_MAP[@]}"; do
                printf "${BYELLOW}  %2d)${RST} %s\n" "$IDX" "$(sed -n "${LN}p" "$DB_FILE")"
                (( IDX++ ))
            done
            printf "\n"
            local OPTION
            while true; do
                pread OPTION "Record number" "[${ESCAPE}=cancel]"
                check_escape "$OPTION" && return
                if [[ "$OPTION" =~ ^[0-9]+$ ]] && \
                   (( OPTION >= 1 && OPTION <= ${#LINE_MAP[@]} )); then break; fi
                err "Enter a number between 1 and ${#LINE_MAP[@]}."
            done
            local LSEL="${LINE_MAP[$((OPTION - 1))]}"
            if [[ -n "$EXISTING_LINE" && "$EXISTING_LINE" != "$LSEL" ]]; then
                err "Selected record does not match the provided DMRID."; return
            fi
            EXISTING_LINE="$LSEL"
            load_record "$EXISTING_LINE"
            FOUND_BY="${FOUND_BY:-call}"
            break

        elif (( ${#LINE_MAP[@]} == 1 )); then
            if [[ -n "$EXISTING_LINE" && "$EXISTING_LINE" != "${LINE_MAP[0]}" ]]; then
                err "Callsign belongs to a different record."; return
            fi
            if [[ -z "$EXISTING_LINE" ]]; then
                EXISTING_LINE="${LINE_MAP[0]}"
                printf "\n"; info "Record found:"
                display_record "$(sed -n "${EXISTING_LINE}p" "$DB_FILE")"
                pconfirm RESP "Edit this record?"
                [[ "$RESP" =~ ^[yY]$ ]] || return
                load_record "$EXISTING_LINE"
                FOUND_BY="call"
            fi
            break
        fi
        break
    done

    # ── PHASE 3: FIELD EDITING ───────────────────────────────────────────────
    printf "\n"; separator
    if [[ -n "$EXISTING_LINE" ]]; then
        printf "${DIM}  Press Enter to keep the current value.${RST}\n"
    else
        printf "${DIM}  New record. Fill in all required fields.${RST}\n"
    fi
    separator; printf "\n"

    # DMRID
    local DMRID_DEFAULT="${F_DMRID:-$DMRID}"
    local _hint_dmr="[optional] [${ESCAPE}=cancel]"
    [[ -n "$DMRID_DEFAULT" ]] && \
        _hint_dmr="[current: ${DMRID_DEFAULT}] [${CLEAR}=clear] [${ESCAPE}=cancel]"
    while true; do
        pread INPUT "DMRID (7 digits)" "$_hint_dmr"
        check_escape "$INPUT" && return

        if [[ "$INPUT" == "$CLEAR" ]]; then
            pconfirm CONF "Confirm removal of DMRID ${DMRID_DEFAULT}?"
            if [[ "$CONF" =~ ^[yY]$ ]]; then
                DMRID=""; ok "DMRID cleared."; break
            else
                warn "Removal cancelled."; continue
            fi
        fi

        [[ -z "$INPUT" ]] && INPUT="$DMRID_DEFAULT"
        validate_no_commas "$INPUT" || continue
        if [[ -n "$INPUT" && ! "$INPUT" =~ ^[0-9]{7}$ ]]; then
            err "Invalid DMRID."; continue
        fi
        if [[ -n "$INPUT" && -z "$DMRID_DEFAULT" ]]; then
            local CONFLICT_LINE
            CONFLICT_LINE=$(find_line_by_dmrid "$INPUT")
            if [[ -n "$CONFLICT_LINE" ]]; then
                err "DMRID $INPUT is already in use:"
                display_record "$(sed -n "${CONFLICT_LINE}p" "$DB_FILE")"
                warn "Enter a different DMRID or leave blank."; continue
            fi
        fi
        DMRID="$INPUT"; break
    done

    # Callsign
    while true; do
        pread INPUT "Callsign (up to 8 chars)" "[current: ${CALL}] [${ESCAPE}=cancel]"
        check_escape "$INPUT" && return
        [[ -z "$INPUT" ]] && INPUT="$CALL"
        INPUT=$(echo "$INPUT" | tr '[:lower:]' '[:upper:]')
        validate_no_commas "$INPUT" || continue
        if [[ ! "$INPUT" =~ ^[A-Z0-9]{1,8}$ ]]; then
            err "Invalid callsign."; continue
        fi
        CALL="$INPUT"; break
    done

    read_field FIRSTNAME "First name (required)" "$F_FIRSTNAME" "r" || return
    read_field LASTNAME  "Last name (optional)"  "$F_LASTNAME"       || return
    read_field CITY      "City (required)"       "$F_CITY"      "r" || return
    read_field STATE     "State (required)"      "$F_STATE"     "r" || return
    read_field COUNTRY   "Country (required)"    "$F_COUNTRY"   "r" || return

    local NEW_RECORD="${DMRID},${CALL},${FIRSTNAME},${LASTNAME},${CITY},${STATE},${COUNTRY}"

    printf "\n"; separator
    info "Final record:"
    display_record "$NEW_RECORD"
    separator

    pconfirm C "Confirm save?"
    [[ "$C" =~ ^[yY]$ ]] || return

    if [[ -n "$EXISTING_LINE" ]]; then
        sed -i "${EXISTING_LINE}s~.*~$NEW_RECORD~" "$DB_FILE"
        ok "Record updated."
    else
        echo "$NEW_RECORD" >> "$DB_FILE"
        ok "Record added."
    fi
}

# --------------------------------------------
# DATABASE — DELETE RECORD
# --------------------------------------------
delete_record() {
    header "DELETE RECORD FROM DATABASE"
    printf "\n"
    printf "  ${BYELLOW}1)${RST} Delete by DMRID\n"
    printf "  ${BYELLOW}2)${RST} Delete by Callsign\n"
    printf "  ${BYELLOW}X)${RST} ${DIM}Back${RST}\n\n"
    pread OP "Choice" ""

    case "$OP" in
        1)
            printf "\n"
            pread DMR "DMRID (7 digits)" "[${ESCAPE}=cancel]"
            check_escape "$DMR" && return
            if [[ ! "$DMR" =~ ^[0-9]{7}$ ]]; then err "Invalid DMRID."; return; fi
            LINE=$(find_line_by_dmrid "$DMR")
            if [[ -z "$LINE" ]]; then warn "No record found."; return; fi
            printf "\n"
            display_record "$(sed -n "${LINE}p" "$DB_FILE")"
            pconfirm C "Confirm deletion?"
            [[ "$C" =~ ^[yY]$ ]] || return
            sed -i "${LINE}d" "$DB_FILE"
            ok "Record deleted."
            ;;
        2)
            printf "\n"
            pread CALL "Callsign" "[${ESCAPE}=cancel]"
            check_escape "$CALL" && return
            CALL=$(echo "$CALL" | tr '[:lower:]' '[:upper:]')
            LINES=( $(find_lines_by_call "$CALL") )

            if (( ${#LINES[@]} == 0 )); then warn "No records found."; return; fi

            if (( ${#LINES[@]} == 1 )); then
                printf "\n"
                display_record "$(sed -n "${LINES[0]}p" "$DB_FILE")"
                pconfirm C "Confirm deletion?"
                [[ "$C" =~ ^[yY]$ ]] || return
                sed -i "${LINES[0]}d" "$DB_FILE"
                ok "Record deleted."
            else
                printf "\n"; info "Multiple records for ${BOLD}${CALL}${RST}:"; printf "\n"
                local IDX=1
                for LN in "${LINES[@]}"; do
                    printf "${BYELLOW}  %2d)${RST} %s\n" "$IDX" "$(sed -n "${LN}p" "$DB_FILE")"
                    (( IDX++ ))
                done
                printf "\n"
                local OPTION
                while true; do
                    pread OPTION "Record number" "[${ESCAPE}=cancel]"
                    check_escape "$OPTION" && return
                    if [[ "$OPTION" =~ ^[0-9]+$ ]] && \
                       (( OPTION >= 1 && OPTION <= ${#LINES[@]} )); then break; fi
                    err "Enter a number between 1 and ${#LINES[@]}."
                done
                local LSEL="${LINES[$((OPTION - 1))]}"
                printf "\n"
                display_record "$(sed -n "${LSEL}p" "$DB_FILE")"
                pconfirm C "Confirm deletion?"
                [[ "$C" =~ ^[yY]$ ]] || return
                sed -i "${LSEL}d" "$DB_FILE"
                ok "Record deleted."
            fi
            ;;
        [Xx]) return ;;
        *) err "Invalid option." ;;
    esac
}

# --------------------------------------------
# ACCESS — ADD USER
# --------------------------------------------
add_access_user() {
    header "ADD USER — WHITELIST AND DASHBOARD"
    printf "\n"

    pread USER "User callsign" "[${ESCAPE}=cancel]"
    check_escape "$USER" && return
    USER=$(echo "$USER" | tr '[:lower:]' '[:upper:]')
    validate_callsign "$USER" || return

    printf "\n"
    local CHANGES_MADE=0

    # ── Whitelist ─────────────────────────────────────────────────────────────
    if grep -q "^${USER}$" "$WHITELIST" 2>/dev/null; then
        warn "Whitelist: ${USER} is already registered."
    else
        pconfirm CWL "Add ${USER} to the reflector whitelist?"
        if [[ "$CWL" =~ ^[yY]$ ]]; then
            echo "$USER" | sudo tee -a "$WHITELIST" > /dev/null
            ok "Added to reflector whitelist."
            CHANGES_MADE=1
        else
            info "Whitelist: no changes made."
            printf "\n"
        fi
    fi

    # ── Dashboard (htpasswd) ──────────────────────────────────────────────────
    if sudo grep -q "^${USER}:" "$HTPASSWD" 2>/dev/null; then
        warn "Dashboard: ${USER} already has access."
    else
        pconfirm CDASH "Add ${USER} to the dashboard (generates password)?"
        if [[ "$CDASH" =~ ^[yY]$ ]]; then
            local PASSWORD
            PASSWORD=$(generate_password)
            sudo htpasswd -b "$HTPASSWD" "$USER" "$PASSWORD"
            add_to_pending "$USER"
            CHANGES_MADE=1
            printf "\n"; separator
            ok "Dashboard access created for ${BOLD}${USER}${RST}${GREEN}!"
            printf "${CYAN}  %-18s${RST}${BWHITE}%s${RST}\n" "Initial password:" "$PASSWORD"
            printf "${DIM}  NOTE: user must change the password on first login.${RST}\n"
            separator
        else
            info "Dashboard: no changes made."
        fi
    fi

    [[ $CHANGES_MADE -eq 0 ]] && warn "No changes were made."
}

# --------------------------------------------
# ACCESS — RESET PASSWORD
# --------------------------------------------
reset_password() {
    header "RESET DASHBOARD PASSWORD"
    printf "\n"

    pread USER "User callsign" "[${ESCAPE}=cancel]"
    check_escape "$USER" && return
    USER=$(echo "$USER" | tr '[:lower:]' '[:upper:]')
    validate_callsign "$USER" || return

    if ! sudo grep -q "^${USER}:" "$HTPASSWD" 2>/dev/null; then
        err "User not found in the dashboard!"; return
    fi

    PASSWORD=$(generate_password)
    printf "\n"; info "Updating password..."
    sudo sed -i "/^${USER}:/d" "$HTPASSWD"
    sudo htpasswd -b "$HTPASSWD" "$USER" "$PASSWORD"
    add_to_pending "$USER"

    printf "\n"; separator
    ok "Password changed for ${BOLD}${USER}${RST}${GREEN}!"
    printf "${CYAN}  %-18s${RST}${BWHITE}%s${RST}\n" "New password:" "$PASSWORD"
    printf "${DIM}  NOTE: user must change the password on first login.${RST}\n"
    separator
}

# --------------------------------------------
# ACCESS — REMOVE USER
# --------------------------------------------
remove_access_user() {
    header "REMOVE USER — WHITELIST AND DASHBOARD"
    printf "\n"

    pread USER "User callsign" "[${ESCAPE}=cancel]"
    check_escape "$USER" && return
    USER=$(echo "$USER" | tr '[:lower:]' '[:upper:]')
    validate_callsign "$USER" || return

    local REMOVED=0; printf "\n"

    if sudo grep -q "^${USER}:" "$HTPASSWD" 2>/dev/null; then
        pconfirm C "Remove dashboard access for ${USER}?"
        if [[ "$C" =~ ^[yY]$ ]]; then
            sudo sed -i "/^${USER}:/d" "$HTPASSWD"
            ok "Removed from dashboard."; REMOVED=1
        fi
    else
        warn "User not found in the dashboard."
    fi

    if grep -q "^${USER}$" "$WHITELIST" 2>/dev/null; then
        pconfirm C "Also remove from the whitelist?"
        if [[ "$C" =~ ^[yY]$ ]]; then
            sudo sed -i "/^${USER}$/d" "$WHITELIST"
            ok "Removed from reflector whitelist."; REMOVED=1
        fi
    fi

    if grep -q "^${USER}$" "$PENDING_FILE" 2>/dev/null; then
        sudo sed -i "/^${USER}$/d" "$PENDING_FILE"
    fi

    [[ $REMOVED -eq 0 ]] && warn "No changes were made."
}

# --------------------------------------------
# ACCESS — LOOK UP USER
# --------------------------------------------
lookup_access_user() {
    header "LOOK UP USER — WHITELIST AND DASHBOARD"
    printf "\n"

    pread USER "User callsign" "[${ESCAPE}=cancel]"
    check_escape "$USER" && return
    USER=$(echo "$USER" | tr '[:lower:]' '[:upper:]')
    validate_callsign "$USER" || return

    printf "\n"
    separator
    printf "${BCYAN}  Status: ${BOLD}%s${RST}\n" "$USER"
    separator

    # Whitelist
    if grep -q "^${USER}$" "$WHITELIST" 2>/dev/null; then
        ok "Reflector whitelist:    PRESENT"
    else
        err "Reflector whitelist:    ABSENT"
    fi

    # Dashboard
    if sudo grep -q "^${USER}:" "$HTPASSWD" 2>/dev/null; then
        ok "Dashboard access:       PRESENT"
        # Pending list only makes sense if the user has dashboard access
        if grep -q "^${USER}$" "$PENDING_FILE" 2>/dev/null; then
            warn "Pending list:           PRESENT (password not yet changed)"
        else
            info "Pending list:           OK (password already changed)"
        fi
    else
        err "Dashboard access:       ABSENT"
    fi

    separator
}

# --------------------------------------------
# MENUS
# --------------------------------------------

# --------------------------------------------
# ACCESS — LIST PENDING USERS
# --------------------------------------------
list_pending_users() {
    header "USERS WITH PENDING PASSWORD CHANGE"
    printf "\n"

    if [[ ! -f "$PENDING_FILE" ]] || [[ ! -s "$PENDING_FILE" ]]; then
        ok "No users with pending password changes."
        return
    fi

    local count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf "  ${BYELLOW}•${RST} %s\n" "$line"
        (( count++ ))
    done < "$PENDING_FILE"

    printf "\n"
    if (( count == 0 )); then
        ok "No users with pending password changes."
    else
        info "Total: ${count} user(s) with pending password change."
    fi
    separator
}

# --------------------------------------------
# ACCESS — LIST WHITELIST IN COLUMNS
# --------------------------------------------
list_whitelist() {
    header "CALLSIGNS ON THE REFLECTOR WHITELIST"
    printf "\n"

    if [[ ! -f "$WHITELIST" ]] || [[ ! -s "$WHITELIST" ]]; then
        warn "Whitelist is empty or file not found."
        return
    fi

    # Load valid entries: skip blank lines and comments (#)
    mapfile -t _ENTRIES < <(grep -v '^[[:space:]]*#' "$WHITELIST" | grep -v '^[[:space:]]*$' | sort)
    local total=${#_ENTRIES[@]}

    if (( total == 0 )); then
        warn "No callsigns found in the whitelist."
        return
    fi

    # Cell width: longest callsign + 2 padding spaces
    local max_len=0
    for e in "${_ENTRIES[@]}"; do
        (( ${#e} > max_len )) && max_len=${#e}
    done
    local cell_w=$(( max_len + 2 ))
    (( cell_w < 6 )) && cell_w=6

    # How many columns fit in the usable area (COLS - 2 indent)
    local area=$(( COLS - 2 ))
    local ncols=$(( area / cell_w ))
    (( ncols < 1 )) && ncols=1

    # Print in columns
    local col=0
    printf "  "
    for e in "${_ENTRIES[@]}"; do
        printf "${BWHITE}%-*s${RST}" "$cell_w" "$e"
        (( col++ ))
        if (( col >= ncols )); then
            printf "\n  "
            col=0
        fi
    done
    # Close the last line if it did not end at the edge
    (( col > 0 )) && printf "\n"

    printf "\n"
    info "Total: ${total} callsign(s) on the whitelist."
    separator
}

# --------------------------------------------
# DATABASE — SEARCH WITH FILTER AND PAGINATION
# --------------------------------------------
search_database() {
    header "SEARCH DATABASE (RadioID)"
    printf "\n"

    # ── Field selection ───────────────────────────────────────────────────────
    printf "  Filter by:\n\n"
    printf "  ${BYELLOW}1)${RST} Callsign  "
    printf "${BYELLOW}2)${RST} DMRID  "
    printf "${BYELLOW}3)${RST} Name  "
    printf "${BYELLOW}4)${RST} City  "
    printf "${BYELLOW}5)${RST} Country\n\n"
    pread FIELD "Field" "[${ESCAPE}=cancel]"
    check_escape "$FIELD" && return

    local awk_col label
    case "$FIELD" in
        1) awk_col=2; label="Callsign" ;;
        2) awk_col=1; label="DMRID"    ;;
        3) awk_col=0; label="Name"     ;;   # 0 = search across cols 3 and 4
        4) awk_col=5; label="City"     ;;
        5) awk_col=7; label="Country"  ;;
        *) err "Invalid option."; return ;;
    esac

    # ── Search term ───────────────────────────────────────────────────────────
    printf "\n"
    pread TERM "Search term (partial match)" "[${ESCAPE}=cancel]"
    check_escape "$TERM" && return
    [[ -z "$TERM" ]] && { err "Search term cannot be empty."; return; }

    # ── Convert glob * to regex .* for intuitive wildcard behaviour ───────────
    local TERM_RE="${TERM//\*/.*}"

    # ── Search via awk — results stored in a temporary file ──────────────────
    local TMPFILE
    TMPFILE=$(mktemp /tmp/xlxd_query.XXXXXX)

    info "Searching..."
    if [[ "$FIELD" == "3" ]]; then
        awk -F',' -v t="${TERM_RE,,}" \
            'NR>1 && (tolower($3) ~ t || tolower($4) ~ t)' \
            "$DB_FILE" > "$TMPFILE"
    else
        awk -F',' -v col="$awk_col" -v t="${TERM_RE,,}" \
            'NR>1 && tolower($col) ~ t' \
            "$DB_FILE" > "$TMPFILE"
    fi

    local total
    total=$(wc -l < "$TMPFILE")

    if (( total == 0 )); then
        rm -f "$TMPFILE"
        warn "No records found for \"${TERM}\" in ${label}."
        return
    fi

    # ── Column widths for the compact table ──────────────────────────────────
    # layout (2-space indent): DMRID(8) CALLSIGN(9) NAME(18) CITY(14) COUNTRY(rest)
    local W_DMR=8 W_CALL=9 W_NAME=18 W_CITY=14
    local W_CTRY=$(( COLS - 2 - W_DMR - W_CALL - W_NAME - W_CITY ))
    (( W_CTRY < 6 )) && W_CTRY=6

    # ── Pagination ────────────────────────────────────────────────────────────
    local PAGE_SIZE=25
    local page=1
    local total_pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
    local nav

    while true; do
        local start=$(( (page - 1) * PAGE_SIZE + 1 ))
        local end=$(( page * PAGE_SIZE ))
        (( end > total )) && end=$total

        printf "\n"

        # Table header
        printf "${CYAN}  %-*s%-*s%-*s%-*s%-*s${RST}\n" \
            $W_DMR  "DMRID" \
            $W_CALL "CALLSIGN" \
            $W_NAME "NAME" \
            $W_CITY "CITY" \
            $W_CTRY "COUNTRY"
        separator

        # Page rows (sed slices efficiently from the tmpfile)
        while IFS=',' read -r _D _C _N _S _CI _E _P; do
            _P="${_P%$'\r'}"   # strip \r from Windows line endings
            local full_name="${_N} ${_S}"
            printf "  ${DIM}%-*s${RST}${BYELLOW}%-*s${RST}${WHITE}%-*s${RST}${DIM}%-*s%-*s${RST}\n" \
                $W_DMR  "$(trunc "$_D"        $(( W_DMR  - 1 )))" \
                $W_CALL "$(trunc "$_C"        $(( W_CALL - 1 )))" \
                $W_NAME "$(trunc "$full_name" $(( W_NAME - 1 )))" \
                $W_CITY "$(trunc "$_CI"       $(( W_CITY - 1 )))" \
                $W_CTRY "$(trunc "$_P"        $(( W_CTRY - 1 )))"
        done < <(sed -n "${start},${end}p" "$TMPFILE")

        separator
        printf "${DIM}  Page %d/%d — %d record(s) | filter: \"%s\" in %s${RST}\n" \
            "$page" "$total_pages" "$total" "$TERM" "$label"

        # Navigation controls
        if (( total_pages == 1 )); then
            printf "\n"; break
        fi

        printf "\n"
        local hint_nav=""
        (( page < total_pages )) && hint_nav="${BYELLOW}[Enter]${RST}${DIM} next${RST}  "
        (( page > 1 ))           && hint_nav+="${BYELLOW}[P]${RST}${DIM} previous${RST}  "
        hint_nav+="${BYELLOW}[${ESCAPE}]${RST}${DIM} exit${RST}"
        printf "  %b\n" "$hint_nav"
        printf "  > "
        read -r nav

        case "${nav^^}" in
            "$ESCAPE") break ;;
            P) (( page > 1 )) && (( page-- )) ;;
            *)
                if (( page < total_pages )); then
                    (( page++ ))
                else
                    break   # last page: Enter exits
                fi
                ;;
        esac
    done

    rm -f "$TMPFILE"
}

menu_database() {
    while true; do
        header "DATABASE (RadioID)"
        printf "  ${BYELLOW}1)${RST} Add / Edit record\n"
        printf "  ${BYELLOW}2)${RST} Delete record\n"
        printf "  ${BYELLOW}3)${RST} List records by Callsign\n"
        printf "  ${BYELLOW}4)${RST} Search records ${DIM}(filter)${RST}\n"
        printf "  ${BYELLOW}5)${RST} Create / Update SQL database\n"
        printf "  ${BYELLOW}X)${RST} ${DIM}Back to main menu${RST}\n"
        separator
        pread OP "Choice" ""

        case "$OP" in
            1) add_or_edit_record ;;
            2) delete_record ;;
            3)
                printf "\n"
                pread CALL "Callsign" "[${ESCAPE}=cancel]"
                check_escape "$CALL" && continue
                CALL=$(echo "$CALL" | tr '[:lower:]' '[:upper:]')
                printf "\n"; list_by_callsign "$CALL"
                ;;
            4) search_database ;;
            5) create_sql_database ;;
            [Xx]) return ;;
            *) err "Invalid option." ;;
        esac
    done
}

menu_access() {
    while true; do
        header "ACCESS CONTROL"
        printf "  ${BYELLOW}1)${RST} Add user         ${DIM}(whitelist + dashboard)${RST}\n"
        printf "  ${BYELLOW}2)${RST} Reset password   ${DIM}(dashboard)${RST}\n"
        printf "  ${BYELLOW}3)${RST} Remove user      ${DIM}(whitelist + dashboard)${RST}\n"
        printf "  ${BYELLOW}4)${RST} Look up user     ${DIM}(whitelist + dashboard)${RST}\n"
        printf "  ${BYELLOW}5)${RST} List pending     ${DIM}(password not yet changed)${RST}\n"
        printf "  ${BYELLOW}6)${RST} List whitelist   ${DIM}(all callsigns)${RST}\n"
        printf "  ${BYELLOW}X)${RST} ${DIM}Back to main menu${RST}\n"
        separator
        pread OP "Choice" ""

        case "$OP" in
            1) add_access_user ;;
            2) reset_password ;;
            3) remove_access_user ;;
            4) lookup_access_user ;;
            5) list_pending_users ;;
            6) list_whitelist ;;
            [Xx]) return ;;
            *) err "Invalid option." ;;
        esac
    done
}

main_menu() {
    while true; do
        setup_width
        clear
        local title="XLX USER MANAGEMENT"
        local tlen=${#title}
        local bar; bar=$(printf '%*s' "$BANNER_IN" '' | sed 's/ /═/g')
        local lpad=$(( (BANNER_IN - tlen) / 2 ))
        local rpad=$(( BANNER_IN - tlen - lpad ))
        (( lpad < 0 )) && lpad=0
        (( rpad < 0 )) && rpad=0
        local lstr; lstr=$(printf '%*s' "$lpad" '')
        local rstr; rstr=$(printf '%*s' "$rpad" '')
        printf "\n"
        printf "${BCYAN}  ╔%s╗${RST}\n" "$bar"
        printf "${BCYAN}  ║${RST}%s${BOLD}%s${RST}%s${BCYAN}║${RST}\n" "$lstr" "$title" "$rstr"
        printf "${BCYAN}  ╚%s╝${RST}\n" "$bar"
        printf "\n"
        printf "  ${BYELLOW}1)${RST} Database ${DIM}(RadioID)${RST}\n"
        printf "  ${BYELLOW}2)${RST} Access control\n"
        printf "  ${BYELLOW}X)${RST} ${DIM}Exit${RST}\n\n"
        separator
        pread OP "Choice" ""

        case "$OP" in
            1) menu_database ;;
            2) menu_access ;;
            [Xx]) printf "\n${DIM}  Exiting...${RST}\n\n"; exit 0 ;;
            *) err "Invalid option." ;;
        esac
    done
}

# --------------------------------------------
# ENTRY POINT
# --------------------------------------------
main_menu
