#!/bin/bash
# Wallpaper picker — FZF UI with live-wallpaper and wal colour support
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
CONFIG_DIR="$HOME/.config/wallpaper-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
WAL_DIR="$HOME/.config/waybar"
MANAGER_SCRIPT="$HOME/.config/waybar/scripts/wallpaper-manager.sh"
LIVE_PID_FILE="$CONFIG_DIR/live.pid"

mkdir -p "$CONFIG_DIR" "$WALLPAPER_DIR"

# ── Config ─────────────────────────────────────────────────────────────────────

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        CURRENT_WALLPAPER=$(jq -r '.current_wallpaper // ""' "$CONFIG_FILE" 2>/dev/null)
        AUTO_CHANGE=$(jq -r '.auto_change // false'          "$CONFIG_FILE" 2>/dev/null)
        INTERVAL_MINUTES=$(jq -r '.interval_minutes // 10'  "$CONFIG_FILE" 2>/dev/null)
    else
        CURRENT_WALLPAPER=""; AUTO_CHANGE="false"; INTERVAL_MINUTES=10
    fi
}

save_config() {
    printf '{"current_wallpaper":"%s","auto_change":%s,"interval_minutes":%s}\n' \
        "$CURRENT_WALLPAPER" "$AUTO_CHANGE" "$INTERVAL_MINUTES" > "$CONFIG_FILE"
}

# ── File-type helpers (exported so the fzf preview subprocess can use them) ────

is_video() {
    case "${1,,}" in *.mp4|*.mkv|*.webm|*.avi|*.mov|*.wmv) return 0 ;; esac
    return 1
}
is_gif() { [[ "${1,,}" == *.gif ]]; }
export -f is_video is_gif

# ── Daemon management ──────────────────────────────────────────────────────────
# awww-daemon is NEVER killed. mpvpaper registers its layer surface after awww,
# so Hyprland renders it on top. Killing mpvpaper reveals awww underneath.

stop_mpvpaper() {
    local killed=false
    if [[ -f "$LIVE_PID_FILE" ]]; then
        kill "$(cat "$LIVE_PID_FILE")" 2>/dev/null && killed=true
        rm -f "$LIVE_PID_FILE"
    fi
    pkill -x mpvpaper 2>/dev/null && killed=true
    # Only pause if something was actually killed — avoids an unnecessary
    # 300 ms gap that left previous icat processes writing to fzf's stdin
    $killed && sleep 0.3
}

ensure_awww_running() {
    pgrep -x awww-daemon &>/dev/null && return 0
    awww-daemon &>/dev/null &
    disown $!
    local i
    for (( i = 0; i < 40; i++ )); do
        sleep 0.1
        awww query &>/dev/null 2>&1 && return 0
    done
    notify-send -u critical "Wallpaper" "awww-daemon failed to start" &
    return 1
}

# ── Colour extraction + kitty live theme reload ────────────────────────────────
# Runs entirely in a detached background subshell — never touches fzf's stdin.
# </dev/null guarantees the subshell cannot accidentally read from the terminal.

apply_wal_colors() {
    local wallpaper="$1"
    (
        if is_video "$wallpaper"; then
            command -v ffmpeg &>/dev/null || exit 0
            local frame="/tmp/wal_frame_$$.jpg"
            ffmpeg -i "$wallpaper" -vframes 1 -q:v 2 "$frame" -y &>/dev/null
            wal -i "$frame" -n -s -t -q &>/dev/null
            rm -f "$frame"
        else
            wal -i "$wallpaper" -n -s -t -q &>/dev/null
        fi

        # ── Waybar colours ─────────────────────────────────────────────────
        [[ -f "$HOME/.cache/wal/colors-waybar.css" ]] &&
            cp "$HOME/.cache/wal/colors-waybar.css" "$WAL_DIR/colors.css"
        pkill -SIGUSR2 waybar 2>/dev/null || true

        # ── Kitty live theme reload ────────────────────────────────────────
        # $KITTY_LISTEN_ON is set automatically by kitty when listen_on is
        # configured in kitty.conf (see kitty-theme-setup.conf).
        # This recolours every open kitty window with no remote-control TTY
        # pollution — it uses the Unix socket, not the in-band protocol.
        if [[ -n "$KITTY_LISTEN_ON" ]] && \
           [[ -f "$HOME/.cache/wal/colors-kitty.conf" ]]; then
            kitten @ --to "$KITTY_LISTEN_ON" set-colors --all \
                --configured "$HOME/.cache/wal/colors-kitty.conf" &>/dev/null || true
        fi
    ) </dev/null &
    disown $!
}

# ── Wallpaper setter ───────────────────────────────────────────────────────────

set_wallpaper() {
    local wallpaper="$1"

    if is_video "$wallpaper"; then
        if ! command -v mpvpaper &>/dev/null; then
            notify-send -u critical "Missing: mpvpaper" \
                "Install with:  yay -S mpvpaper"
            return 1
        fi
        stop_mpvpaper
        setsid mpvpaper -o "no-audio loop" '*' "$wallpaper" \
            </dev/null >/dev/null 2>&1 &
        echo $! > "$LIVE_PID_FILE"
        notify-send -t 1500 "🎬 Live Wallpaper" "$(basename "$wallpaper")" &

    elif is_gif "$wallpaper"; then
        stop_mpvpaper
        ensure_awww_running || return 1
        awww img "$wallpaper" --transition-type none &>/dev/null
        notify-send -t 1500 "🖼 GIF Wallpaper" "$(basename "$wallpaper")" &

    else
        stop_mpvpaper
        ensure_awww_running || return 1
        awww img "$wallpaper" \
            --transition-type fade --transition-duration 0.3 &>/dev/null
        notify-send -t 1500 "🖼 Wallpaper Set" "$(basename "$wallpaper")" &
    fi

    CURRENT_WALLPAPER="$wallpaper"
    save_config
    apply_wal_colors "$wallpaper"
}

set_random() {
    local all=("$WALLPAPER_DIR"/*.{jpg,jpeg,png,webp,gif,mp4,mkv,webm,\
JPG,JPEG,PNG,WEBP,GIF,MP4,MKV,WEBM})
    local valid=()
    for f in "${all[@]}"; do [[ -f "$f" ]] && valid+=("$f"); done
    [[ ${#valid[@]} -gt 0 ]] && set_wallpaper "${valid[RANDOM % ${#valid[@]}]}"
}

toggle_slideshow() {
    load_config
    [[ "$AUTO_CHANGE" == "true" ]] \
        && bash "$MANAGER_SCRIPT" stop-rotation \
        || bash "$MANAGER_SCRIPT" start-rotation
}

change_interval() {
    load_config
    local new_interval
    new_interval=$(printf '5\n10\n15\n30\n60' | fzf \
        --prompt="⏱ Interval (minutes): " \
        --header="Choose slideshow interval" \
        --height=40% --layout=reverse --border=rounded \
        --color "border:#89b4fa,prompt:#f5c2e7,pointer:#f38ba8")
    [[ -z "$new_interval" ]] && return
    INTERVAL_MINUTES="$new_interval"
    save_config
    if [[ "$AUTO_CHANGE" == "true" ]]; then
        bash "$MANAGER_SCRIPT" stop-rotation
        bash "$MANAGER_SCRIPT" start-rotation
    fi
    notify-send -t 1500 "⏱ Slideshow Timer" "Interval: ${new_interval}m" &
}

# ── Preview function ───────────────────────────────────────────────────────────
# Uses chafa as the primary renderer.
#
# WHY chafa and NOT kitten icat:
#   Every icat invocation — regardless of --transfer-mode — still queries
#   the terminal via the in-band remote-control protocol for at least one
#   round-trip (window size or image-placement acknowledgement).  Kitty
#   writes "@kitty-cmd{...}" responses directly to the TTY device; because
#   fzf reads the same TTY for keyboard input, those bytes land in fzf's
#   search bar, corrupt the input stream, and crash fzf when the user
#   presses an arrow key whose escape sequence collides with the remainder
#   of the "@kitty-cmd" string.
#
#   chafa renders images via pure outgoing escape sequences only — it never
#   reads from the terminal.  It is listed as an officially supported client
#   of the kitty graphics protocol.  Install it with:
#       sudo pacman -S chafa
#
#   --polite on  — suppresses escape sequences that could confuse programs
#                  sharing the terminal (i.e. fzf)
#   --format kitty — uses the kitty graphics protocol for pixel-perfect output

preview_file() {
    local src="$1"
    local tmpframe=""

    if is_video "$src"; then
        tmpframe="/tmp/wp_prev_$$.jpg"
        if command -v ffmpeg &>/dev/null; then
            ffmpeg -i "$src" -vframes 1 -q:v 3 "$tmpframe" -y &>/dev/null \
                || { printf '🎬  %s\n' "$(basename "$src")"; return; }
        else
            printf '🎬  %s  (install ffmpeg for preview)\n' "$(basename "$src")"
            return
        fi
        src="$tmpframe"
    fi

    local cols="${FZF_PREVIEW_COLUMNS:-80}"
    local lines="${FZF_PREVIEW_LINES:-40}"

    if command -v chafa &>/dev/null; then
        # Primary: chafa — confirmed working with kitty graphics protocol,
        # zero TTY reads, zero remote-control pollution.
        chafa --format kitty \
              --polite on \
              --size "${cols}x${lines}" \
              --align center,top \
              "$src" 2>/dev/null
    elif [[ -n "$KITTY_WINDOW_ID" ]] && command -v kitten &>/dev/null; then
        # Fallback: icat with the four flags that the kitty docs document as
        # making icat generate escape codes with "no TTY communication at all"
        kitten icat \
            --stdin=no \
            --use-window-size "${cols},${lines},$(( cols * 10 )),$(( lines * 20 ))" \
            --transfer-mode=file \
            --place="${cols}x${lines}@0x0" \
            --scale-up \
            "$src" 2>/dev/null
    else
        printf '📁  %s\n' "$(basename "$1")"
    fi

    [[ -n "$tmpframe" ]] && rm -f "$tmpframe"
}
export -f preview_file

# ── Find expression ────────────────────────────────────────────────────────────
FIND_EXPR="find . -maxdepth 1 -type f \( \
    -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o \
    -iname '*.gif' -o -iname '*.mp4'  -o -iname '*.mkv' -o -iname '*.webm' -o \
    -iname '*.mov' \) -printf '%f\n' | sort"

# ── Main FZF loop ──────────────────────────────────────────────────────────────

if command -v fzf &>/dev/null; then
    cd "$WALLPAPER_DIR" || exit 1

    cleanup() { tput cnorm 2>/dev/null; stty sane 2>/dev/null; }
    trap cleanup EXIT
    trap 'cleanup; exit 0' INT TERM

    while true; do
        load_config

        [[ "$AUTO_CHANGE" == "true" ]] \
            && SLIDESHOW_STATUS="ON (${INTERVAL_MINUTES}m)" \
            || SLIDESHOW_STATUS="OFF"

        HEADER="Wallpaper Manager | Slideshow: $SLIDESHOW_STATUS
ENTER=Set  ESC=Exit  CTRL-R=Random  CTRL-S=Slideshow  CTRL-T=Timer  CTRL-D=Delete"

        CURRENT_BASENAME=""
        [[ -n "$CURRENT_WALLPAPER" && -f "$CURRENT_WALLPAPER" ]] \
            && CURRENT_BASENAME=$(basename "$CURRENT_WALLPAPER")

        WALLPAPER_LIST=$(eval "$FIND_EXPR")

        CURRENT_POS=1
        if [[ -n "$CURRENT_BASENAME" ]]; then
            CURRENT_POS=$(echo "$WALLPAPER_LIST" \
                | grep -n "^${CURRENT_BASENAME}$" | cut -d: -f1)
            [[ -z "$CURRENT_POS" ]] && CURRENT_POS=1
        fi

        result=$(echo "$WALLPAPER_LIST" | fzf \
            --preview "preview_file {}" \
            --preview-window="right:50%" \
            --height=100% \
            --layout=reverse \
            --border=rounded \
            --prompt="Select wallpaper > " \
            --header="$HEADER" \
            --bind "load:pos($CURRENT_POS)" \
            --bind "ctrl-r:execute-silent(echo random           > /tmp/wallpaper-action)+abort" \
            --bind "ctrl-s:execute-silent(echo toggle_slideshow > /tmp/wallpaper-action)+abort" \
            --bind "ctrl-t:execute-silent(echo change_interval  > /tmp/wallpaper-action)+abort" \
            --bind "ctrl-d:execute(trash {} 2>/dev/null || rm {})+reload(${FIND_EXPR})" \
            --color "border:#89b4fa,prompt:#f5c2e7,pointer:#f38ba8,header:#cdd6f4")

        if [[ -f /tmp/wallpaper-action ]]; then
            action=$(cat /tmp/wallpaper-action); rm -f /tmp/wallpaper-action
            case "$action" in
                random)           set_random;       continue ;;
                toggle_slideshow) toggle_slideshow; continue ;;
                change_interval)  change_interval;  continue ;;
            esac
        fi

        [[ -z "$result" ]] && exit 0
        set_wallpaper "$WALLPAPER_DIR/$result"
    done

elif command -v rofi &>/dev/null; then
    load_config
    [[ "$AUTO_CHANGE" == "true" ]] \
        && SLIDESHOW_STATUS="ON (${INTERVAL_MINUTES}m)" \
        || SLIDESHOW_STATUS="OFF"
    selected=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o \
        -iname '*.gif' -o -iname '*.mp4'  -o -iname '*.mkv' -o -iname '*.webm' -o \
        -iname '*.mov' \) -printf '%f\n' | sort | \
        rofi -dmenu -i -p "🎨 Wallpaper" \
            -theme-str 'window {width: 50%; height: 60%;}' \
            -theme-str 'listview {lines: 15;}' \
            -mesg "Slideshow: $SLIDESHOW_STATUS | Enter: Set")
    [[ -n "$selected" ]] && set_wallpaper "$WALLPAPER_DIR/$selected"
else
    notify-send -u critical "Error" "Install fzf or rofi"
fi
