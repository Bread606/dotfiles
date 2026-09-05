#!/usr/bin/env bash
FRAMES="$HOME/.config/fastfetch/hanoi_frames"
DELAY=0.5

tput civis

trap 'tput cnorm' EXIT
trap 'exit 0' INT TERM

while true; do
    for frame in "$FRAMES"/*.txt; do
        printf '\033[H'
        fastfetch \
            --logo-type file \
            --logo "$frame" \
            --config ~/.config/fastfetch/config.jsonc
        if read -rsn1 -t "$DELAY" key; then
            break 2
        fi
    done
done
