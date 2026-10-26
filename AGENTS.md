# Agent notes

Rules for working on this repo, collected from past corrections.

## Testing and screenshots

- Never test on the maintainer's live desktop. Don't move the pointer, hover, type or open windows there. Instead, start a nested headless session: run `kwin_wayland --virtual` and `plasmashell --no-respawn` inside `dbus-run-session`, with a throwaway `HOME`.
- Never run `pkill -f plasmashell` or any similar pattern. It also kills the real shell. Kill only the PIDs you started, and check their environment or command line first.
- Screenshots use the "Next to the icon" battery mode. Blur the device's MAC address in the settings screenshot.
