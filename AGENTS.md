# Agent notes

Rules for working on this repo, collected from past corrections.

## Testing and screenshots

- Never test on the maintainer's live desktop. Don't move the pointer, hover, type or open windows there. Instead, start a nested headless session: run `kwin_wayland --virtual` and `plasmashell --no-respawn` inside `dbus-run-session`, with a throwaway `HOME`.
- Set the throwaway `HOME` and every `XDG_*_HOME` before `dbus-run-session` starts. D-Bus-activated services (`kactivitymanagerd`, `kded6`, `kdeconnectd`, ...) inherit the bus daemon's environment, not your script's. Exports made inside the bus leave them on the real `~/.local/share` and `~/.config`, and the nested Application Launcher then writes Plasma's default favorites (browser, Dolphin, System Settings) into the maintainer's real launcher.
- Never run `pkill -f plasmashell` or any similar pattern. It also kills the real shell. Kill only the PIDs you started, and check their environment or command line first.
- Screenshots use the "Next to the icon" battery mode. Blur the device's MAC address in the settings screenshot.
- Don't run `plasmoidviewer`, `qml6` or `spectacle` against the live session either. They open windows and send notifications on the real desktop.

## Making the screenshots

`screenshots/panel.png` shows the widget on the panel with its tooltip open. `screenshots/settings.png` shows the General settings page. Both come from a nested session, set up like this.

1. Make a scratch directory, say `$S`, under `$TMPDIR` (or use `mktemp -d` if `TMPDIR` is unset). Copy `package/` to `$S/home/.local/share/plasma/plasmoids/me.d3sox.bluetoothquickconnect`. The nested shell then loads that copy, not the one installed on the real desktop.
2. To open the tooltip without a pointer, edit only that copy of `contents/ui/main.qml`. Add this `Timer` inside the compact representation's `MouseArea`, right after `acceptedButtons: Qt.LeftButton`. Never commit it.

   ```qml
   Timer {
       running: true; repeat: true; interval: 1500
       onTriggered: {
           let p = compact.parent;
           while (p && typeof p.showToolTip !== "function") p = p.parent;
           if (p) p.showToolTip();
       }
   }
   ```

3. Write a session script and run it with `$S/session.sh` in the background. It sets up the environment first and only then re-executes itself under `dbus-run-session`:

   ```bash
   #!/usr/bin/env bash
   S=...   # the scratch directory
   export HOME=$S/home
   export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache XDG_STATE_HOME=$HOME/.local/state
   export XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 XDG_SESSION_TYPE=wayland
   export QT_FORCE_STDERR_LOGGING=1   # without it, QML console output goes nowhere
   unset DISPLAY
   # start the private bus only now, so the services it activates inherit the env above
   [ -z "$BTQC_NESTED" ] && BTQC_NESTED=1 exec dbus-run-session -- "$0"
   echo "$DBUS_SESSION_BUS_ADDRESS" > $S/bus
   kwin_wayland --virtual --width 1280 --height 800 --socket btqc-wl --no-lockscreen --no-global-shortcuts > $S/kwin.log 2>&1 &
   echo $! > $S/kwin.pid
   # wait for the socket $XDG_RUNTIME_DIR/btqc-wl to appear
   export WAYLAND_DISPLAY=btqc-wl QT_QPA_PLATFORM=wayland
   plasmashell --no-respawn > $S/plasma.log 2>&1 &
   echo $! > $S/plasma.pid
   wait
   ```

   If the settings page no longer fits, raise `--height`. The panel crop below then moves down. The real system bus is still used, so BluezQt sees the real paired devices. Connect the headphones first if the shot should show a battery level.
4. Before every `qdbus6` or `spectacle` call that follows, set `DBUS_SESSION_BUS_ADDRESS=$(cat $S/bus) WAYLAND_DISPLAY=btqc-wl`, and for `spectacle` also `HOME=$S/home`. Without them, the command reaches the real plasmashell or captures the real screen.
5. Wait until the shell has a panel: `evaluateScript 'print(panels().length)'` returns at least 1. A screenshot that shows only the wallpaper was taken too early. Then add the widget left of the tray and configure it:

   ```js
   var p = panels()[0];
   var t = p.widgets("org.kde.plasma.systemtray")[0].geometry;
   var w = p.addWidget("me.d3sox.bluetoothquickconnect", t.x + 2, 20, 40, 40);
   w.currentConfigGroup = ["General"];
   w.writeConfig("deviceAddress", "EC:66:D1:C0:07:9B");
   w.writeConfig("deviceName", "Px7 S2e");
   w.writeConfig("batteryDisplay", 2);
   w.reloadConfig();
   print(w.id);
   ```

   Pass it with `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '<script>'`.
6. Take the panel shot with `spectacle -b -n -f -o $S/shot1.png`, and crop it to the panel corner with the tooltip. On the 1280x800 screen that is the box `(860, 650, 1280, 800)`.
7. Open the settings with `panels()[0].widgetById(<id>).showConfigurationInterface()`. The window's title is `<deviceName> Settings`. Move it to the top left with a KWin script, loaded through `qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript <file> <name>`, then started with `qdbus6 org.kde.KWin /Scripting/Script<returned id> org.kde.kwin.Script.run`:

   ```js
   for (const w of workspace.windowList()) {
       if (w.caption === "Px7 S2e Settings") {
           w.frameGeometry = { x: 40, y: 20, width: w.frameGeometry.width, height: w.frameGeometry.height };
       }
   }
   ```

   Take a second full screenshot. Typing doesn't work in the nested KWin (`wtype` finds no virtual keyboard), so set every value through `writeConfig` before opening the settings.
8. Crop from the window's top left corner, title bar included, down to just below the last setting. Blur the MAC address with Pillow: `s.paste(s.crop(box).filter(ImageFilter.GaussianBlur(5)), box)`, where `box` is the address text. The coordinates change with the layout, so crop a zoomed copy of the address area and look at it to confirm the blur covers all of it.
9. Stop the session by PID. Kill plasmashell only after `/proc/<pid>/environ` shows `HOME=$S/home`. For KWin, whose environ can't be read, match its exact command line. D-Bus also starts services inside the nested session, such as `kwalletd6`. They outlive it and keep the scratch directory busy, so find the processes whose environ has `HOME=$S/home`, kill those, then delete `$S`.

The nested session has no notification server. To test notifications, run a small `org.freedesktop.Notifications` service on the nested bus, for example a Python Gio script that logs every `Notify` call.
