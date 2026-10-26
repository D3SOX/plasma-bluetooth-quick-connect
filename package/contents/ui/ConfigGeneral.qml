/*
 * SPDX-FileCopyrightText: 2026 D3SOX
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.iconthemes as KIconThemes
import org.kde.bluezqt as BluezQt

KCMUtils.SimpleKCM {
    id: page

    property string cfg_deviceAddress
    property string cfg_deviceAddressDefault
    property string cfg_deviceName
    property string cfg_deviceNameDefault
    property string cfg_deviceIcon
    property string cfg_deviceIconDefault
    property string cfg_icon
    property string cfg_iconDefault
    property int cfg_batteryDisplay
    property int cfg_batteryDisplayDefault
    property bool cfg_showBattery
    property bool cfg_showBatteryDefault
    property alias cfg_powerOnAdapter: powerOnCheck.checked
    property bool cfg_powerOnAdapterDefault
    property alias cfg_notifyOnError: notifyCheck.checked
    property bool cfg_notifyOnErrorDefault
    property alias cfg_notifyOnCharge: chargeCheck.checked
    property bool cfg_notifyOnChargeDefault
    property alias cfg_chargeThreshold: thresholdSpin.value
    property int cfg_chargeThresholdDefault
    property alias cfg_chargeResetBelow: resetBelowSpin.value
    property int cfg_chargeResetBelowDefault

    // Paired devices, plus the saved one if it is currently missing.
    readonly property var deviceOptions: {
        const options = [];
        const devices = BluezQt.Manager.devices;
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (device.paired) {
                options.push({ name: device.name, address: device.address, icon: device.icon || "preferences-system-bluetooth" });
            }
        }
        options.sort((a, b) => a.name.localeCompare(b.name));
        if (cfg_deviceAddress && !options.some(option => option.address === cfg_deviceAddress)) {
            options.push({
                name: i18n("%1 (not available)", cfg_deviceName || cfg_deviceAddress),
                address: cfg_deviceAddress,
                icon: "dialog-question",
            });
        }
        return options;
    }

    readonly property var selectedOption: deviceOptions.find(option => option.address === cfg_deviceAddress) ?? null

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: i18n("Device:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: deviceCombo

                Layout.minimumWidth: Kirigami.Units.gridUnit * 14
                enabled: page.deviceOptions.length > 0
                model: page.deviceOptions
                textRole: "name"
                valueRole: "address"
                currentIndex: page.deviceOptions.findIndex(option => option.address === page.cfg_deviceAddress)
                displayText: page.deviceOptions.length === 0
                    ? i18n("No paired devices")
                    : (currentIndex < 0 ? i18n("Choose a device…") : currentText)

                onActivated: index => {
                    const option = page.deviceOptions[index];
                    page.cfg_deviceAddress = option.address;
                    if (option.icon !== "dialog-question") {
                        page.cfg_deviceName = option.name;
                        page.cfg_deviceIcon = option.icon;
                    }
                }

                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index

                    width: deviceCombo.popup.availableWidth
                    text: modelData.name
                    icon.name: modelData.icon
                    highlighted: deviceCombo.highlightedIndex === index
                }
            }

            QQC2.Button {
                icon.name: "preferences-system-bluetooth"
                text: i18n("Bluetooth Settings…")
                onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_bluetooth")
            }
        }

        QQC2.Label {
            visible: page.cfg_deviceAddress !== ""
            text: i18n("Address: %1", page.cfg_deviceAddress)
            opacity: 0.7
        }

        QQC2.Label {
            visible: page.deviceOptions.length === 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.Wrap
            text: i18n("Pair your device in the Bluetooth settings first. It will then show up here.")
        }

        QQC2.Button {
            id: iconButton

            Kirigami.FormData.label: i18n("Icon:")

            implicitWidth: previewFrame.width + Kirigami.Units.smallSpacing * 2
            implicitHeight: previewFrame.height + Kirigami.Units.smallSpacing * 2
            hoverEnabled: true

            QQC2.ToolTip.text: page.cfg_icon ? i18n("Custom icon") : i18n("Using the device's own icon")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

            onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.open()

            KIconThemes.IconDialog {
                id: iconDialog
                onIconNameChanged: iconName => page.cfg_icon = iconName || ""
            }

            Kirigami.Icon {
                id: previewFrame
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                source: page.cfg_icon || (page.selectedOption ? page.selectedOption.icon : "preferences-system-bluetooth")
            }

            QQC2.Menu {
                id: iconMenu
                y: parent.height

                QQC2.MenuItem {
                    text: i18nc("@item:inmenu Open icon chooser dialog", "Choose…")
                    icon.name: "document-open-folder"
                    onClicked: iconDialog.open()
                }
                QQC2.MenuItem {
                    text: i18nc("@item:inmenu", "Use Device Icon")
                    icon.name: "edit-clear"
                    enabled: page.cfg_icon !== ""
                    onClicked: page.cfg_icon = ""
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Battery percentage:")
            model: [
                i18nc("@item:inlistbox battery percentage in the panel", "Hidden"),
                i18nc("@item:inlistbox battery percentage in the panel", "Badge on the icon"),
                i18nc("@item:inlistbox battery percentage in the panel", "Next to the icon"),
            ]
            // -1 means the setting predates this option, so follow the old on/off switch.
            currentIndex: page.cfg_batteryDisplay >= 0 ? page.cfg_batteryDisplay : (page.cfg_showBattery ? 2 : 0)
            onActivated: index => page.cfg_batteryDisplay = index
        }

        QQC2.CheckBox {
            id: powerOnCheck
            Kirigami.FormData.label: i18n("Behavior:")
            text: i18n("Turn on Bluetooth if it is off")
        }

        QQC2.CheckBox {
            id: notifyCheck
            text: i18n("Notify when connecting or disconnecting fails")
        }

        QQC2.CheckBox {
            id: chargeCheck
            text: i18n("Notify when the battery is charged")
        }

        QQC2.SpinBox {
            id: thresholdSpin
            Kirigami.FormData.label: i18n("Notify at:")
            enabled: chargeCheck.checked
            from: 1
            to: 100
            textFromValue: (value, locale) => i18nc("battery percentage", "%1%", value)
            valueFromText: (text, locale) => parseInt(text)
        }

        QQC2.SpinBox {
            id: resetBelowSpin
            Kirigami.FormData.label: i18n("Notify again after dropping below:")
            enabled: chargeCheck.checked
            from: 0
            to: 100
            textFromValue: (value, locale) => i18nc("battery percentage", "%1%", value)
            valueFromText: (text, locale) => parseInt(text)
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.Wrap
            enabled: chargeCheck.checked
            text: i18n("Bluetooth doesn't report whether a device is charging, so it counts as charging while its battery level goes up.")
            opacity: 0.7
        }
    }
}
