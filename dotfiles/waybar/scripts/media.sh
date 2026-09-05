#!/usr/bin/env bash
# ~/.config/waybar/scripts/media.sh
# Shows currently playing media via playerctl as waybar JSON.
# Requires: playerctl

PLAYER=$(playerctl -l 2>/dev/null | head -1)

if [ -z "$PLAYER" ]; then
    echo '{"text": "", "class": "stopped", "tooltip": "No media player"}'
    exit 0
fi

STATUS=$(playerctl --player="$PLAYER" status 2>/dev/null)

if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then
    ARTIST=$(playerctl --player="$PLAYER" metadata artist 2>/dev/null | head -1)
    TITLE=$(playerctl  --player="$PLAYER" metadata title  2>/dev/null | head -1)

    # Truncate long strings
    MAX=25
    if [ ${#ARTIST} -gt $MAX ]; then ARTIST="${ARTIST:0:$MAX}…"; fi
    if [ ${#TITLE}  -gt $MAX ]; then TITLE="${TITLE:0:$MAX}…";   fi

    if [ "$STATUS" = "Playing" ]; then
        ICON="󰎆"
        CLASS="playing"
    else
        ICON="󰏤"
        CLASS="paused"
    fi

    if [ -n "$ARTIST" ] && [ -n "$TITLE" ]; then
        TEXT="$ICON  $ARTIST — $TITLE"
        TOOLTIP="$ARTIST — $TITLE\nPlayer: $PLAYER\nStatus: $STATUS"
    elif [ -n "$TITLE" ]; then
        TEXT="$ICON  $TITLE"
        TOOLTIP="$TITLE\nPlayer: $PLAYER\nStatus: $STATUS"
    else
        TEXT="$ICON  Playing"
        TOOLTIP="Player: $PLAYER\nStatus: $STATUS"
    fi

    printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' \
        "$TEXT" "$CLASS" "$TOOLTIP"
else
    echo '{"text": "", "class": "stopped", "tooltip": "No media playing"}'
fi
