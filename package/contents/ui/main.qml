/*
 * SPDX-FileCopyrightText: 2026 D3SOX
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.components as WorkspaceComponents
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.notification
import org.kde.bluezqt as BluezQt

PlasmoidItem {
    id: root

    readonly property string deviceAddress: Plasmoid.configuration.deviceAddress

    readonly property var device: {
        // Touch these so the lookup re-runs when devices or adapters come and go.
        BluezQt.Manager.devices;
        BluezQt.Manager.adapters;
        BluezQt.Manager.operational;
        return deviceAddress ? BluezQt.Manager.deviceForAddress(deviceAddress) : null;
    }
    readonly property var adapter: device ? device.adapter : null

    // With Bluetooth switched off completely, BlueZ hides all devices, so fall back to "is any adapter usable".
    readonly property bool radioOn: !BluezQt.Manager.bluetoothBlocked && BluezQt.Manager.usableAdapter !== null
    readonly property bool bluetoothOn: device ? (!BluezQt.Manager.bluetoothBlocked && adapter !== null && adapter.powered) : radioOn
    readonly property bool connected: device !== null && device.connected
    readonly property var upower: upowerLoader.item
    // Most devices report their battery to BlueZ. Some, like game controllers, only through the kernel.
    readonly property int batteryPercent: {
        if (!connected) {
            return -1;
        }
        if (device.battery) {
            return device.battery.percentage;
        }
        return upower ? upower.percentage : -1;
    }
    readonly property string displayName: device ? device.name : (Plasmoid.configuration.deviceName || deviceAddress)

    // Use the charging state when the device reports one. Most headphones only report their
    // battery level, so for those assume the device is charging while the level rises.
    property int lastBatteryPercent: -1
    property bool levelRising: false
    property bool chargeNotified: false
    readonly property bool charging: upower && upower.charging !== undefined ? upower.charging : levelRising

    // 0 hidden, 1 badge on the icon, 2 next to the icon. Older versions only had the showBattery switch.
    readonly property int batteryDisplay: Plasmoid.configuration.batteryDisplay >= 0
        ? Plasmoid.configuration.batteryDisplay
        : (Plasmoid.configuration.showBattery ? 2 : 0)

    readonly property string iconName: Plasmoid.configuration.icon
        || (device && device.icon)
        || Plasmoid.configuration.deviceIcon
        || "preferences-system-bluetooth"

    // "" when idle, otherwise "power", "connect" or "disconnect".
    property string pendingAction: ""
    readonly property bool busy: pendingAction !== ""
    // Keeps the running BluezQt call alive until it reports back.
    property var activeCall: null

    property string lastError: ""
    property string lastErrorDetail: ""

    function toggle() {
        if (busy) {
            return;
        }
        clearError();

        if (!deviceAddress) {
            Plasmoid.internalAction("configure").trigger();
            return;
        }
        if (connected) {
            run(device.disconnectFromDevice(), "disconnect");
            return;
        }
        if (!bluetoothOn) {
            if (!Plasmoid.configuration.powerOnAdapter) {
                fail(i18n("Bluetooth is turned off."), "");
                return;
            }
            pendingAction = "power";
            powerOn();
            powerWatcher.restart();
            return;
        }
        if (!device) {
            fail(notPairedMessage(), "");
            return;
        }
        run(device.connectToDevice(), "connect");
    }

    function powerOn() {
        if (BluezQt.Manager.bluetoothBlocked) {
            BluezQt.Manager.bluetoothBlocked = false;
        }
        if (adapter) {
            if (!adapter.powered) {
                adapter.powered = true;
            }
            return;
        }
        // We don't know the device's adapter yet, so power up all of them.
        const adapters = BluezQt.Manager.adapters;
        for (let i = 0; i < adapters.length; i++) {
            if (!adapters[i].powered) {
                adapters[i].powered = true;
            }
        }
    }

    function notPairedMessage() {
        return i18n("%1 is not paired with this computer.", displayName);
    }

    function run(call, action) {
        pendingAction = action;
        activeCall = call;
        callTimeout.restart();
        call.finished.connect(() => {
            if (activeCall !== call) {
                return; // timed out earlier, ignore the late answer
            }
            callTimeout.stop();
            activeCall = null;
            pendingAction = "";
            if (call.error !== BluezQt.PendingCall.NoError) {
                handleCallError(call, action);
            }
        });
    }

    function handleCallError(call, action) {
        switch (call.error) {
        case BluezQt.PendingCall.AlreadyConnected:
        case BluezQt.PendingCall.NotConnected:
            return; // the device is already in the state we wanted
        case BluezQt.PendingCall.InProgress:
            fail(i18n("%1 is already connecting.", displayName), call.errorText);
            return;
        case BluezQt.PendingCall.NotReady:
            fail(i18n("Bluetooth is not ready yet. Try again in a moment."), call.errorText);
            return;
        }
        failAction(action, call.errorText);
    }

    function failAction(action, detail) {
        if (action === "connect") {
            fail(i18n("Couldn't connect to %1. Make sure it is turned on and in range.", displayName), detail);
        } else {
            fail(i18n("Couldn't disconnect from %1.", displayName), detail);
        }
    }

    function fail(message, detail) {
        lastError = message;
        lastErrorDetail = detail || "";
        errorExpiry.restart();
        if (Plasmoid.configuration.notifyOnError) {
            notify(message);
        }
    }

    function notify(message) {
        const notification = notificationComponent.createObject(root, {
            title: displayName || i18n("Bluetooth"),
            text: message,
            iconName: iconName,
        });
        notification.closed.connect(() => notification.destroy());
        notification.sendEvent();
    }

    function clearError() {
        lastError = "";
        lastErrorDetail = "";
        errorExpiry.stop();
    }

    function statusText() {
        if (!deviceAddress) {
            return i18n("No device selected");
        }
        switch (pendingAction) {
        case "power": return i18n("Turning on Bluetooth…");
        case "connect": return i18n("Connecting…");
        case "disconnect": return i18n("Disconnecting…");
        }
        if (!device) {
            return radioOn ? i18n("Not paired") : i18n("Disconnected · Bluetooth is off");
        }
        if (connected) {
            return batteryPercent >= 0
                ? i18n("Connected · Battery %1%", batteryPercent)
                : i18n("Connected");
        }
        if (!bluetoothOn) {
            return i18n("Disconnected · Bluetooth is off");
        }
        return i18n("Disconnected");
    }

    function hintText() {
        if (!deviceAddress) {
            return i18n("Click to choose a device");
        }
        if (busy || (!device && radioOn)) {
            return "";
        }
        return connected ? i18n("Click to disconnect") : i18n("Click to connect");
    }

    // Remember the device name so we can still show it while the device is gone.
    onDeviceChanged: {
        if (!device) {
            return;
        }
        if (device.name && device.name !== Plasmoid.configuration.deviceName) {
            Plasmoid.configuration.deviceName = device.name;
        }
        if (device.icon && device.icon !== Plasmoid.configuration.deviceIcon) {
            Plasmoid.configuration.deviceIcon = device.icon;
        }
    }
    onDeviceAddressChanged: {
        clearError();
        searchUPower();
    }
    onConnectedChanged: {
        if (connected) {
            clearError();
            searchUPower();
        } else if (upower) {
            upower.forget();
        }
    }

    onBatteryPercentChanged: {
        const percent = batteryPercent;
        if (percent < 0 || lastBatteryPercent < 0) {
            // Disconnected, or the first reading after connecting: start over from here.
            lastBatteryPercent = percent;
            levelRising = false;
            chargeNotified = false;
        } else {
            // A flat reading never gets here, so a plateau keeps counting as rising.
            levelRising = percent > lastBatteryPercent;
            lastBatteryPercent = percent;
        }
        checkCharge();
    }
    onChargingChanged: checkCharge()

    function checkCharge() {
        const percent = batteryPercent;
        if (percent < 0) {
            return;
        }
        if (percent < Math.min(Plasmoid.configuration.chargeResetBelow, Plasmoid.configuration.chargeThreshold)) {
            chargeNotified = false;
        }
        if (Plasmoid.configuration.notifyOnCharge && charging && !chargeNotified
                && percent >= Plasmoid.configuration.chargeThreshold) {
            chargeNotified = true;
            notify(i18n("Battery charged to %1%.", percent));
        }
    }

    function searchUPower() {
        upowerSearch.tries = 0;
        upowerSearch.restart();
    }

    Plasmoid.icon: iconName
    Plasmoid.title: displayName || i18n("Bluetooth Quick Connect")

    preferredRepresentation: compactRepresentation
    activationTogglesExpanded: false
    Plasmoid.onActivated: toggle()

    toolTipMainText: deviceAddress ? displayName : i18n("Bluetooth Quick Connect")
    toolTipSubText: [statusText(), lastError, lastErrorDetail, hintText()].filter(line => line).join("\n")
    toolTipTextFormat: Text.PlainText

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.connected ? i18n("Disconnect") : i18n("Connect")
            icon.name: root.connected ? "network-disconnect-symbolic" : "network-connect-symbolic"
            enabled: root.deviceAddress !== "" && !root.busy
            onTriggered: root.toggle()
        },
        PlasmaCore.Action {
            text: i18n("Bluetooth Settings…")
            icon.name: "preferences-system-bluetooth"
            onTriggered: KCMUtils.KCMLauncher.openSystemSettings("kcm_bluetooth")
        }
    ]

    // Waits for the adapter to come up after we asked to turn Bluetooth on.
    Timer {
        id: powerWatcher
        property int ticks: 0
        interval: 250
        repeat: true
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            if (root.pendingAction !== "power") {
                stop();
                return;
            }
            if (root.bluetoothOn && root.device) {
                stop();
                root.run(root.device.connectToDevice(), "connect");
                return;
            }
            ticks++;
            // Bluetooth is up but the device never showed up: it isn't paired (anymore).
            if (root.radioOn && !root.device && ticks >= 12) {
                stop();
                root.pendingAction = "";
                root.fail(root.notPairedMessage(), "");
                return;
            }
            // After an rfkill unblock the adapter object can reappear unpowered, so ask again.
            if (ticks % 4 === 0) {
                root.powerOn();
            }
            if (ticks >= 40) {
                stop();
                root.pendingAction = "";
                root.fail(i18n("Couldn't turn on Bluetooth."), "");
            }
        }
    }

    // BlueZ gives up on its own after ~30 s; this only guards against a call that never answers.
    Timer {
        id: callTimeout
        interval: 60000
        onTriggered: {
            const action = root.pendingAction;
            root.activeCall = null;
            root.pendingAction = "";
            root.failAction(action, "");
        }
    }

    Timer {
        id: errorExpiry
        interval: 60000
        onTriggered: root.clearError()
    }

    // Needs Plasma's D-Bus QML module. Without it, upower stays null and only BlueZ is used.
    Loader {
        id: upowerLoader
        source: "UPowerDevice.qml"
        onLoaded: {
            item.address = Qt.binding(() => root.deviceAddress);
            root.searchUPower();
        }
    }

    // The kernel adds a device's battery a moment after the device connects, so look a few times.
    Timer {
        id: upowerSearch
        property int tries: 0
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!root.upower || !root.connected || root.upower.devicePath !== "" || tries >= 6) {
                stop();
                return;
            }
            tries++;
            root.upower.find();
        }
    }

    Component {
        id: notificationComponent
        Notification {
            componentName: "plasma_workspace"
            eventId: "notification"
        }
    }

    // Plasma only uses compactRepresentation when a full one exists too. It is never
    // opened by clicking (that toggles the connection), but it is a handy status card.
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: implicitHeight
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                source: root.iconName
                opacity: root.connected ? 1 : 0.5
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    elide: Text.ElideRight
                    text: root.toolTipMainText
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: [root.statusText(), root.lastError].filter(line => line).join("\n")
                }
            }
        }

        PlasmaComponents3.Button {
            Layout.alignment: Qt.AlignRight
            enabled: !root.busy
            icon.name: !root.deviceAddress ? "configure" : (root.connected ? "network-disconnect-symbolic" : "network-connect-symbolic")
            text: !root.deviceAddress ? i18n("Choose Device…") : (root.connected ? i18n("Disconnect") : i18n("Connect"))
            onClicked: root.toggle()
        }
    }

    compactRepresentation: MouseArea {
        id: compact

        readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property bool hasBattery: root.batteryPercent >= 0
        readonly property bool showBadge: root.batteryDisplay === 1 && hasBattery
        readonly property bool showLabel: root.batteryDisplay === 2 && hasBattery
        readonly property real spacing: Kirigami.Units.smallSpacing
        readonly property bool lowBattery: root.batteryPercent <= Plasmoid.configuration.lowBatteryLevel
        readonly property color batteryColor: lowBattery ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor

        readonly property real iconSize: {
            if (horizontal) {
                return height;
            }
            if (vertical) {
                return width;
            }
            return Math.max(0, Math.min(width, height - (showLabel ? batteryLabel.implicitHeight : 0)));
        }

        // In a horizontal panel the badge hangs off the icon's right edge, so make room for it.
        readonly property real badgeOverflow: showBadge && horizontal ? Math.max(0, batteryBadge.x + batteryBadge.width - iconSize) : 0

        Layout.minimumWidth: horizontal ? iconSize + badgeOverflow + (showLabel ? spacing + batteryLabel.implicitWidth : 0) : Kirigami.Units.iconSizes.small
        Layout.maximumWidth: horizontal ? Layout.minimumWidth : Infinity
        Layout.minimumHeight: vertical ? iconSize + (showLabel ? batteryLabel.implicitHeight : 0) : Kirigami.Units.iconSizes.small
        Layout.maximumHeight: vertical ? Layout.minimumHeight : Infinity

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.toggle()

        Kirigami.Icon {
            id: deviceIcon

            property real pulse: 1

            x: compact.horizontal ? 0 : (compact.width - width) / 2
            y: compact.vertical ? 0 : compact.horizontal ? (compact.height - height) / 2 : (compact.height - height - (compact.showLabel ? batteryLabel.implicitHeight : 0)) / 2
            width: compact.iconSize
            height: compact.iconSize

            source: root.iconName
            active: compact.containsMouse
            opacity: root.busy ? pulse : (root.connected ? 1 : 0.5)

            SequentialAnimation on pulse {
                running: root.busy
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { from: 1; to: 0.3; duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.3; to: 1; duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutQuad }
            }

            // Plasma's badge, as used by the Bluetooth and battery widgets. In a horizontal panel it
            // starts at the middle of the icon and hangs off its right edge, so it covers one side
            // like a notification count instead of the whole bottom.
            WorkspaceComponents.BadgeOverlay {
                id: batteryBadge
                x: compact.horizontal ? Math.round(parent.width * 0.45) : parent.width - width
                anchors.bottom: parent.bottom
                visible: compact.showBadge
                // Plasma 6.8 and later draw it with Kirigami.Badge, which has its own text color. Before that,
                // its label took the color from the theme.
                Kirigami.Theme.textColor: compact.batteryColor
                Component.onCompleted: {
                    if ("customTextColor" in batteryBadge) {
                        batteryBadge.customTextColor = Qt.binding(() => compact.lowBattery ? Kirigami.Theme.negativeTextColor : "transparent");
                    }
                }
                text: i18nc("battery percentage badge on the panel icon", "%1%", root.batteryPercent)
                icon: deviceIcon
            }
        }

        PlasmaComponents3.Label {
            id: batteryLabel

            visible: compact.showLabel
            x: compact.horizontal ? deviceIcon.width + compact.spacing : (compact.width - width) / 2
            y: compact.horizontal ? (compact.height - height) / 2 : deviceIcon.y + deviceIcon.height

            text: i18nc("battery percentage shown next to the panel icon", "%1%", root.batteryPercent)
            font: compact.vertical ? Kirigami.Theme.smallFont : Kirigami.Theme.defaultFont
            color: compact.batteryColor
        }
    }
}
