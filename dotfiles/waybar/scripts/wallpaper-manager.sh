#!/bin/bash
# Wallpaper manager — init, rotation, live wallpapers, wal colour extraction
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
CONFIG_DIR="$HOME/.config/wallpaper-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
WAL_DIR="$HOME/.config/waybar"
PID_FILE="$CONFIG_DIR/rotation.pid"
LIVE_PID_FILE="$CONFIG_DIR/live.pid"

mkdir -p "$CONFIG_DIR" "$WALLPAPER_DIR"

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

is_video() {
    case "${1,,}" in *.mp4|*.mkv|*.webm|*.avi|*.mov|*.wmv) return 0 ;; esac
    return 1
}
is_gif() { [[ "${1,,}" == *.gif ]]; }

stop_mpvpaper() {
    local killed=false
    if [[ -f "$LIVE_PID_FILE" ]]; then
        kill "$(cat "$LIVE_PID_FILE")" 2>/dev/null && killed=true
        rm -f "$LIVE_PID_FILE"
    fi
    pkill -x mpvpaper 2>/dev/null && killed=true
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
    return 1
}

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

        # Waybar
        [[ -f "$HOME/.cache/wal/colors-waybar.css" ]] &&
            cp "$HOME/.cache/wal/colors-waybar.css" "$WAL_DIR/colors.css"
        pkill -SIGUSR2 waybar 2>/dev/null || true

        # Kitty — recolour all open windows via socket (no TTY pollution)
        if [[ -n "$KITTY_LISTEN_ON" ]] && \
           [[ -f "$HOME/.cache/wal/colors-kitty.conf" ]]; then
            kitten @ --to "$KITTY_LISTEN_ON" set-colors --all \
                --configured "$HOME/.cache/wal/colors-kitty.conf" &>/dev/null || true
        fi
    ) </dev/null &
    disown $!
}

set_wallpaper() {
    local wallpaper="$1"

    if is_video "$wallpaper"; then
        command -v mpvpaper &>/dev/null || { echo "mpvpaper not found" >&2; return 1; }
        stop_mpvpaper
        setsid mpvpaper -o "no-audio loop" '*' "$wallpaper" \
            </dev/null >/dev/null 2>&1 &
        echo $! > "$LIVE_PID_FILE"
    elif is_gif "$wallpaper"; then
        stop_mpvpaper
        ensure_awww_running || return 1
        awww img "$wallpaper" --transition-type none &>/dev/null
    else
        stop_mpvpaper
        ensure_awww_running || return 1
        awww img "$wallpaper" \
            --transition-type fade --transition-duration 0.5 &>/dev/null
    fi

    CURRENT_WALLPAPER="$wallpaper"
    save_config
    apply_wal_colors "$wallpaper"
}

random_wallpaper() {
    local all=("$WALLPAPER_DIR"/*.{jpg,jpeg,png,webp,gif,mp4,mkv,webm,\
JPG,JPEG,PNG,WEBP,GIF,MP4,MKV,WEBM})
    local valid=()
    for f in "${all[@]}"; do [[ -f "$f" ]] && valid+=("$f"); done
    [[ ${#valid[@]} -gt 0 ]] && set_wallpaper "${valid[RANDOM % ${#valid[@]}]}"
}

start_rotation() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && return
    (
        echo $BASHPID > "$PID_FILE"
        while true; do
            sleep $(( INTERVAL_MINUTES * 60 ))
            random_wallpaper
        done
    ) &
}

stop_rotation() {
    [[ -f "$PID_FILE" ]] && { kill "$(cat "$PID_FILE")" 2>/dev/null; rm -f "$PID_FILE"; } || true
}

case "${1:-}" in
    init)
        load_config
        [[ -n "$CURRENT_WALLPAPER" && -f "$CURRENT_WALLPAPER" ]] \
            && set_wallpaper "$CURRENT_WALLPAPER"
        [[ "$AUTO_CHANGE" == "true" ]] && start_rotation
        ;;
    set)
        [[ -z "$2" ]] && { echo "Usage: $0 set <path>"; exit 1; }
        set_wallpaper "$2"
        ;;
    random)  load_config; random_wallpaper ;;
    start-rotation)
        load_config; AUTO_CHANGE="true"; save_config
        start_rotation
        notify-send "Wallpaper Rotation" "Auto-change enabled (${INTERVAL_MINUTES}m)"
        ;;
    stop-rotation)
        load_config; AUTO_CHANGE="false"; save_config
        stop_rotation
        notify-send "Wallpaper Rotation" "Auto-change disabled"
        ;;
    *)
        echo "Usage: $0 {init|set <path>|random|start-rotation|stop-rotation}"
        exit 1 ;;
esac
