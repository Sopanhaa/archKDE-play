#!/usr/bin/env bash
#
# Terminal UI helpers for archKDE-play.
# Sourced after lib/common.sh and lib/modules.sh.

MAIN_MENU_KEYS=(1 2 3 4 5 6 0)
MAIN_MENU_LABELS=(
    "Quick Setup"
    "Custom Setup"
    "GPU Drivers"
    "Gaming Apps"
    "Performance Tools"
    "System Check"
    "Exit"
)
MAIN_MENU_DESCRIPTIONS=(
    "Drivers, KDE, Steam, tools, and performance setup"
    "Choose exactly which modules to install"
    "NVIDIA, AMD, Intel, and hybrid graphics"
    "Steam, Lutris, Heroic, Wine, GameMode, MangoHud"
    "SSD trim and safe power profiles"
    "Read-only check; nothing is changed"
    "Quit without changing anything"
)
MAIN_MENU_TAGS=("Recommended" "" "" "" "" "" "")

ui_use_unicode() {
    local locale_name="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    [[ "${TERM:-dumb}" != "dumb" ]] || return 1
    locale_name="${locale_name,,}"
    [[ "$locale_name" == *utf-8* || "$locale_name" == *utf8* ]]
}

ui_arrow_menu_supported() {
    [[ -t 0 && -t 1 && "${TERM:-dumb}" != "dumb" ]]
}

ui_terminal_columns() {
    local cols="${COLUMNS:-}"
    if [[ -z "$cols" ]] && command -v tput >/dev/null 2>&1; then
        cols="$(tput cols 2>/dev/null || true)"
    fi
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    ((cols < 40)) && cols=40
    printf '%s\n' "$cols"
}

ui_use_compact_menu() {
    local cols
    cols="$(ui_terminal_columns)"
    ((cols < 70))
}

ui_clear_screen() {
    if ui_arrow_menu_supported; then
        printf '\033[H\033[2J'
    fi
}

ui_icon_selected() {
    if ui_use_unicode; then printf '❯'; else printf '>'; fi
}

ui_icon_step() {
    if ui_use_unicode; then printf '→'; else printf '>'; fi
}

ui_icon_done() {
    if ui_use_unicode; then printf '✓'; else printf '[OK]'; fi
}

ui_icon_pending() {
    if ui_use_unicode; then printf '○'; else printf '[ ]'; fi
}

ui_icon_error() {
    if ui_use_unicode; then printf '✗'; else printf '[X]'; fi
}

ui_step() {
    printf '  %s%s%s %s\n' "$C_BLUE" "$(ui_icon_step)" "$C_RESET" "$*"
}

ui_done() {
    printf '  %s%s%s %s\n' "$C_GREEN" "$(ui_icon_done)" "$C_RESET" "$*"
}

ui_pending() {
    printf '  %s%s%s %s\n' "$C_DIM" "$(ui_icon_pending)" "$C_RESET" "$*"
}

ui_error_step() {
    printf '  %s%s%s %s\n' "$C_RED" "$(ui_icon_error)" "$C_RESET" "$*"
}

ui_menu_option() {
    local index="$1"
    local selected="$2"
    local key="${MAIN_MENU_KEYS[$index]}"
    local label="${MAIN_MENU_LABELS[$index]}"
    local description="${MAIN_MENU_DESCRIPTIONS[$index]}"
    local tag="${MAIN_MENU_TAGS[$index]}"
    local marker="  "
    local label_color=""

    if ((selected == index)); then
        marker="$(ui_icon_selected) "
        label_color="$C_BOLD$C_GREEN"
    fi

    printf '  %s%s%s %s[%s]%s %s%-38s%s' \
        "$C_GREEN" "$marker" "$C_RESET" "$C_BOLD$C_YELLOW" "$key" "$C_RESET" \
        "$label_color" "$label" "$C_RESET"
    if [[ -n "$tag" ]]; then
        printf '  %s(%s)%s' "$C_GREEN" "$tag" "$C_RESET"
    fi
    printf '\n'
    if [[ -n "$description" ]]; then
        printf '        %s%s%s\n' "$C_DIM" "$description" "$C_RESET"
    fi
}

ui_menu_system_line() {
    local os="Linux"
    local gpu="Unknown GPU"
    local kde=""
    local sep=" | "
    local info vendors
    local -a vendor_list=()

    if ui_use_unicode; then
        sep=" · "
    fi
    [[ -f /etc/arch-release ]] && os="Arch Linux"
    info="$(detect_system_gpu_info)"
    vendors="$(detect_gpu_vendors "$info")"
    mapfile -t vendor_list <<<"$vendors"
    gpu="$(gpu_vendor_label "${vendor_list[@]}") GPU"
    if command -v plasmashell >/dev/null 2>&1; then
        kde="KDE Plasma"
    fi

    printf '%s %s%s%s' "$os" "$(uname -m)" "$sep" "$gpu"
    if [[ -n "$kde" ]]; then
        printf '%s%s' "$sep" "$kde"
    fi
}

show_main_menu() {
    local selected="${1:-0}"
    local i
    local sep=" | "
    local top_left="+"
    local top_right="+"
    local bottom_left="+"
    local bottom_right="+"
    local horizontal="-"
    local vertical="|"
    local rule=""
    local up_hint="Up"
    local down_hint="Down"

    if ui_use_unicode; then
        sep=" · "
        top_left="╭"
        top_right="╮"
        bottom_left="╰"
        bottom_right="╯"
        horizontal="─"
        vertical="│"
        up_hint="↑"
        down_hint="↓"
    fi
    for ((i = 0; i < 50; i++)); do
        rule+="$horizontal"
    done

    if ui_use_compact_menu; then
        printf '\n  %sarchKDE-play%s - Arch Linux Gaming Setup\n' "$C_BOLD" "$C_RESET"
        printf '  %sWelcome! Let'\''s set up your gaming system.%s\n\n' "$C_DIM" "$C_RESET"
        for i in "${!MAIN_MENU_KEYS[@]}"; do
            local marker=" "
            local tag=""
            ((selected == i)) && marker="$(ui_icon_selected)"
            [[ -n "${MAIN_MENU_TAGS[$i]}" ]] && tag=" (${MAIN_MENU_TAGS[$i]})"
            printf '  %s%s%s [%s] %s%s%s%s\n' \
                "$C_GREEN" "$marker" "$C_RESET" "${MAIN_MENU_KEYS[$i]}" \
                "${MAIN_MENU_LABELS[$i]}" "$C_DIM" "$tag" "$C_RESET"
        done
        printf '\n  %s%s/%s Navigate   Enter Select   Q Quit%s\n' \
            "$C_DIM" "$up_hint" "$down_hint" "$C_RESET"
        return 0
    fi

    printf '\n'
    printf '  %s%s%s\n' "$C_CYAN" "${top_left}${rule}${top_right}" "$C_RESET"
    printf '  %s%s%s %s%-48s%s %s%s%s\n' \
        "$C_CYAN" "$vertical" "$C_RESET" "$C_BOLD" " archKDE-play" "$C_RESET" \
        "$C_CYAN" "$vertical" "$C_RESET"
    printf '  %s%s%s %-48s %s%s%s\n' \
        "$C_CYAN" "$vertical" "$C_RESET" " Arch Linux gaming setup" \
        "$C_CYAN" "$vertical" "$C_RESET"
    printf '  %s%s%s\n' \
        "$C_CYAN" "${bottom_left}${rule}${bottom_right}" "$C_RESET"
    printf '\n  %sWelcome! Let'\''s set up your gaming system.%s\n' "$C_DIM" "$C_RESET"
    printf '  %sSystem%s   %s\n' "$C_BOLD" "$C_RESET" "$(ui_menu_system_line)"
    printf '  %sSafety%s   %sNo partitions%sNo bootloader edits%sNo auto-reboot%s\n' \
        "$C_BOLD" "$C_RESET" "$C_DIM" "$sep" "$sep" "$C_RESET"
    printf '\n'

    for i in "${!MAIN_MENU_KEYS[@]}"; do
        ui_menu_option "$i" "$selected"
    done

    printf '\n  %s%s/%s Navigate   Enter Select   Q Quit%s\n' \
        "$C_DIM" "$up_hint" "$down_hint" "$C_RESET"
}

show_main_menu_plain() {
    local i
    printf '\n  archKDE-play - Arch Linux Gaming Setup\n'
    printf '  Welcome! Let'\''s set up your gaming system.\n\n'
    for i in "${!MAIN_MENU_KEYS[@]}"; do
        printf '  [%s] %s' "${MAIN_MENU_KEYS[$i]}" "${MAIN_MENU_LABELS[$i]}"
        if [[ -n "${MAIN_MENU_TAGS[$i]}" ]]; then
            printf ' (%s)' "${MAIN_MENU_TAGS[$i]}"
        fi
        printf '\n'
    done
    printf '\n  Type a number and press Enter, or q to quit.\n'
}

main_menu_choice() {
    local choice="$1"
    local status

    case "$choice" in
        1)
            SELECTED_MODULES="$RECOMMENDED_MODULES"
            MENU_SELECTED=1
            return 0
            ;;
        2)
            ui_clear_screen
            interactive_select_modules
            status=$?
            if ((status == 0)); then
                MENU_SELECTED=1
                return 0
            fi
            if ((status == 2)); then
                return 2
            fi
            return 1
            ;;
        3)
            SELECTED_MODULES="03"
            MENU_SELECTED=1
            return 0
            ;;
        4)
            SELECTED_MODULES="05"
            MENU_SELECTED=1
            return 0
            ;;
        5)
            SELECTED_MODULES="07"
            MENU_SELECTED=1
            return 0
            ;;
        6)
            # shellcheck disable=SC2034  # consumed by install.sh
            CHECK_ONLY=1
            MENU_SELECTED=1
            return 0
            ;;
        0)
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

interactive_select_arrow() {
    local selected=0
    local count="${#MAIN_MENU_KEYS[@]}"
    local key rest typed choice status
    local redraw=1
    local ignore_empty=0
    typed=""
    choice=""

    while true; do
        if ((redraw)); then
            ui_clear_screen
            show_main_menu "$selected"
            printf '\n  Choose an option [%s]: ' "${MAIN_MENU_KEYS[$selected]}"
            redraw=0
        fi

        if ! IFS= read -rsn1 key; then
            printf '\n'
            return 1
        fi
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.05 rest || rest=""
            key+="$rest"
        fi
        [[ -n "$key" ]] && ignore_empty=0

        case "$key" in
            $'\x1b[A'|$'\x1bOA'|k|K)
                selected=$(((selected - 1 + count) % count))
                typed=""
                redraw=1
                ;;
            $'\x1b[B'|$'\x1bOB'|j|J)
                selected=$(((selected + 1) % count))
                typed=""
                redraw=1
                ;;
            ""|$'\n'|$'\r')
                if ((ignore_empty)); then
                    ignore_empty=0
                    redraw=1
                    continue
                fi
                printf '\n'
                if [[ -n "$typed" ]]; then
                    choice="$typed"
                else
                    choice="${MAIN_MENU_KEYS[$selected]}"
                fi
                typed=""
                ;;
            [0-6])
                typed+="$key"
                printf '%s' "$key"
                ;;
            q|Q)
                printf '\n'
                return 1
                ;;
            *)
                ui_warn "Use arrow keys, a number, or q."
                typed=""
                ignore_empty=1
                redraw=1
                ;;
        esac

        if [[ -n "$choice" ]]; then
            if [[ ! "$choice" =~ ^[0-6]$ ]]; then
                ui_warn "Enter a number from 0 to 6."
                typed=""
                choice=""
                redraw=1
                continue
            fi
            main_menu_choice "$choice"
            status=$?
            if ((status == 0)); then
                return 0
            fi
            if ((status == 2)); then
                choice=""
                selected=1
                redraw=1
                continue
            fi
            return 1
        fi
    done
}

interactive_select_simple() {
    local answer
    local status

    while true; do
        show_main_menu_plain
        printf '\n  Choose an option: '
        if ! IFS= read -r answer; then
            printf '\n'
            return 1
        fi
        answer="${answer#"${answer%%[![:space:]]*}"}"
        answer="${answer%"${answer##*[![:space:]]}"}"

        case "${answer,,}" in
            ""|1|quick) answer=1 ;;
            2|custom) answer=2 ;;
            3|gpu|drivers) answer=3 ;;
            4|gaming|apps) answer=4 ;;
            5|performance) answer=5 ;;
            6|check) answer=6 ;;
            0|q|quit|exit) return 1 ;;
            *)
                ui_warn "Enter a number from 0 to 6, or q to quit."
                continue
                ;;
        esac

        main_menu_choice "$answer"
        status=$?
        if ((status == 0)); then
            return 0
        fi
        if ((status == 2)); then
            continue
        fi
        return 1
    done
}

interactive_select() {
    if ui_arrow_menu_supported; then
        interactive_select_arrow
    else
        interactive_select_simple
    fi
}

show_module_menu() {
    local i
    section "Custom setup"
    printf '  Select the modules you want:\n\n'
    printf '  a) All modules\n\n'
    for i in "${!MODULE_NUMBERS[@]}"; do
        printf '  %s) %s\n' "${MODULE_NUMBERS[$i]}" "${MODULE_TITLES[$i]}"
        printf '      %s\n' "${MODULE_DESCRIPTIONS[$i]}"
    done
    printf '\n  q) Back to main menu\n'
    printf '\n  Enter numbers separated by spaces or commas (for example: 03 05 06),\n'
    printf '  a range such as 03-06, or "all".\n'
}

interactive_select_modules() {
    local answer normalized
    show_module_menu

    while true; do
        printf '\n  Select modules (or q to go back): '
        if ! IFS= read -r answer; then
            printf '\n'
            return 1
        fi
        answer="${answer#"${answer%%[![:space:]]*}"}"
        answer="${answer%"${answer##*[![:space:]]}"}"

        case "${answer,,}" in
            "") ui_warn "Please enter a selection, or q to go back."; continue ;;
            a|all) SELECTED_MODULES="$ALL_MODULES"; return 0 ;;
            q|quit|back) return 2 ;;
            h|help|\?) show_module_menu; continue ;;
        esac

        if normalized="$(parse_module_selection "$answer")"; then
            SELECTED_MODULES="$normalized"
            return 0
        fi
        ui_warn "That selection was not understood. Use 01-08, a range like 03-05, or all."
    done
}

show_selection() {
    local number
    local bullet="•"
    if ! ui_use_unicode; then
        bullet="*"
    fi
    section "Installation plan"
    for number in $SELECTED_MODULES; do
        printf '  %s%s%s %s  %s\n' "$C_GREEN" "$bullet" "$C_RESET" "$number" "$(module_title "$number")"
    done
    if ((DRY_RUN)); then
        printf '\nDry run: these modules would run, but nothing will be changed.\n'
    else
        printf '\nThe installer asks for confirmation before making changes.\n'
    fi
    printf 'It will never format disks, edit bootloader entries, or reboot automatically.\n'
    if [[ " $SELECTED_MODULES " != *" 08 "* ]]; then
        printf 'Optional virtualization (08) is not included; add it later with: bash %q --modules 08\n' "$ROOT_DIR/install.sh"
    fi
}

show_recommendation() {
    local info vendors
    info="$(detect_system_gpu_info)"
    vendors="$(detect_gpu_vendors "$info")"

    section "Recommendation"
    if gpu_has_vendor nvidia "$vendors"; then
        printf '  NVIDIA graphics detected: the driver module chooses a matching NVIDIA package.\n'
    elif gpu_has_vendor amd "$vendors"; then
        printf '  AMD graphics detected: Mesa and Vulkan drivers will be installed.\n'
    elif gpu_has_vendor intel "$vendors"; then
        printf '  Intel graphics detected: Mesa and Intel Vulkan drivers will be installed.\n'
    fi
    if ((!SELECTION_SET && !FULL_INSTALL && !PROFILE_SET && !MENU_SELECTED)); then
        if package_installed plasma-desktop 2>/dev/null; then
            printf '  KDE Plasma is already installed: choose Custom Setup to skip the desktop module.\n'
        fi
    fi
    if ! multilib_enabled; then
        printf '  [multilib] is disabled: the installer can enable it for Steam when needed.\n'
    fi
    printf '  Recommended gaming packages: Steam, Lutris, Heroic, Wine, GameMode, and MangoHud.\n'
    if ((!SELECTION_SET && !FULL_INSTALL && !PROFILE_SET && !MENU_SELECTED)); then
        printf '  Press Enter at the menu to use Quick Setup.\n'
    fi
}
