import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "preferences-system-bluetooth"
        source: "ConfigGeneral.qml"
    }
}
