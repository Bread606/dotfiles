#!/usr/bin/env python3
import json
import subprocess
import sys

def get_active_window():
    try:
        # Get active window info from hyprctl
        result = subprocess.run(
            ['hyprctl', 'activewindow', '-j'],
            capture_output=True,
            text=True,
            check=True
        )

        window_info = json.loads(result.stdout)
        title = window_info.get('title', '')

        # Only return output if there's an actual title
        if title and title.strip():
            # Truncate long titles
            max_length = 50
            if len(title) > max_length:
                title = title[:max_length] + "..."

            # Output in Waybar format
            output = {
                "text": title,
                "tooltip": title,
                "class": "active"
            }
            print(json.dumps(output), flush=True)
        else:
            # Output empty when no window
            output = {
                "text": "",
                "tooltip": "",
                "class": "empty"
            }
            print(json.dumps(output), flush=True)

    except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError):
        # If error, output empty
        output = {
            "text": "",
            "tooltip": "",
            "class": "empty"
        }
        print(json.dumps(output), flush=True)

if __name__ == "__main__":
    # Run continuously, checking every 0.5 seconds
    import time
    while True:
        get_active_window()
        time.sleep(0.5)
