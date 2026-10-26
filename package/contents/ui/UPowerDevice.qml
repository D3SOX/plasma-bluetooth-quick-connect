/*
 * SPDX-FileCopyrightText: 2026 D3SOX
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// The device's battery as the kernel reports it to UPower. Only some devices have one, mostly
// game controllers, and it can say whether the device is charging. Battery levels that UPower
// just copies from BlueZ are skipped, because they never come with a charging state.
Item {
    id: source

    property string address

    property string devicePath: ""
    readonly property var deviceProperties: watcher.item ? watcher.item.properties : null

    readonly property int percentage: deviceProperties && deviceProperties.Percentage !== undefined
        ? Math.round(deviceProperties.Percentage) : -1

    // true or false when the device reports it, undefined when it doesn't.
    readonly property var charging: {
        switch (deviceProperties ? deviceProperties.State : 0) {
        case 1: // Charging
        case 4: // Fully charged, still on the charger
        case 5: // Pending charge
            return true;
        case 2: // Discharging
        case 3: // Empty
        case 6: // Pending discharge
            return false;
        }
        return undefined;
    }

    function call(path, iface, member, args, callback) {
        const reply = DBus.SystemBus.asyncCall({
            service: "org.freedesktop.UPower",
            path: path,
            iface: iface,
            member: member,
            arguments: args,
        });
        reply.finished.connect(() => {
            if (!reply.isError) {
                callback(reply.value);
            }
            reply.destroy();
        });
    }

    function find() {
        const mac = address.toLowerCase();
        if (!mac || devicePath) {
            return;
        }
        call("/org/freedesktop/UPower", "org.freedesktop.UPower", "EnumerateDevices", [], paths => {
            for (const entry of paths || []) {
                const path = entry.value ?? entry;
                call(path, "org.freedesktop.DBus.Properties", "GetAll", ["org.freedesktop.UPower.Device"], props => {
                    const nativePath = String(props.NativePath || "").toLowerCase();
                    if (nativePath.startsWith("/org/bluez/")) {
                        return;
                    }
                    // Kernel drivers put the address in the battery's name, e.g. ps-controller-battery-<mac>.
                    if (nativePath.includes(mac) || nativePath.includes(mac.replace(/:/g, "_"))
                            || String(props.Serial || "").toLowerCase() === mac) {
                        source.devicePath = path;
                    }
                });
            }
        });
    }

    function forget() {
        devicePath = "";
    }

    onAddressChanged: forget()

    Loader {
        id: watcher
        active: source.devicePath !== ""
        sourceComponent: DBus.Properties {
            busType: DBus.BusType.System
            service: "org.freedesktop.UPower"
            path: source.devicePath
            iface: "org.freedesktop.UPower.Device"
        }
    }
}
