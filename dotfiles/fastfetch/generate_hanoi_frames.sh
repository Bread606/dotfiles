#!/usr/bin/env bash
OUT="$HOME/.config/fastfetch/hanoi_frames"
rm -rf "$OUT"
mkdir -p "$OUT"
WIDTH=40
HEIGHT=12
BASE=$((HEIGHT-1))
PEG_X=(8 20 32)
FRAME=0
declare -a STACKS
declare -a MOVES
save_frame() {
    local file
    file=$(printf "%s/frame%04d.txt" "$OUT" "$FRAME")
    {
        for ((r=0;r<HEIGHT;r++)); do
            printf "%s\n" "${SCREEN[$r]}"
        done
    } > "$file"
    ((FRAME++))
}
render() {
    unset SCREEN
    for ((r=0;r<HEIGHT;r++)); do
        SCREEN[$r]="$(printf '%*s' "$WIDTH")"
    done
    # pegs
    for peg in "${PEG_X[@]}"; do
        for ((r=1;r<BASE;r++)); do
            row="${SCREEN[$r]}"
            SCREEN[$r]=$(
                printf "%s|%s" \
                "${row:0:$peg}" \
                "${row:$((peg+1))}"
            )
        done
    done
    # base
    SCREEN[$BASE]="$(printf '=%.0s' $(seq 1 $WIDTH))"
    # disks
    for peg in 0 1 2; do
        disks=(${STACKS[$peg]})
        for ((i=0;i<${#disks[@]};i++)); do
            size=${disks[$i]}
            case $size in
                1) width=3 ;;
                2) width=5 ;;
                3) width=7 ;;
            esac
            row=$((BASE-1-i))
            center=${PEG_X[$peg]}
            start=$((center-width/2))
            disk=""
            for ((k=0;k<width;k++)); do
                disk+="█"
            done
            line="${SCREEN[$row]}"
            SCREEN[$row]=$(
                printf "%s%s%s" \
                "${line:0:$start}" \
                "$disk" \
                "${line:$((start+width))}"
            )
        done
    done
    save_frame
}
sort_hanoi() {
    local n=$1
    local A=$2
    local B=$3
    local C=$4
    if ((n==1)); then
        MOVES+=("$A $C")
        return
    fi
    sort_hanoi $((n-1)) "$A" "$C" "$B"
    MOVES+=("$A $C")
    sort_hanoi $((n-1)) "$B" "$A" "$C"
}
apply_move() {
    local src=$1
    local dst=$2
    src_stack=(${STACKS[$src]})
    top=${src_stack[-1]}
    unset 'src_stack[-1]'
    STACKS[$src]="${src_stack[*]}"
    STACKS[$dst]="${STACKS[$dst]} $top"
    render
}
# start state
STACKS[0]="3 2 1"
STACKS[1]=""
STACKS[2]=""
render
# forward
MOVES=()
sort_hanoi 3 0 1 2
for move in "${MOVES[@]}"; do
    read s d <<< "$move"
    apply_move "$s" "$d"
done
# reverse
MOVES=()
sort_hanoi 3 2 1 0
for move in "${MOVES[@]}"; do
    read s d <<< "$move"
    apply_move "$s" "$d"
done
echo "Generated $FRAME frames."
