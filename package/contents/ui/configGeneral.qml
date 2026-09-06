import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configPage

    // The plasmoid config system loads/saves these `cfg_<key>` properties automatically.
    property alias cfg_sampleInterval: sampleSpin.value
    property alias cfg_idleSampleInterval: idleSpin.value
    property alias cfg_historySeconds: historySpin.value
    property alias cfg_showPanelUsage: panelUsageCheck.checked
    property alias cfg_showAggregate: aggregateCheck.checked
    property alias cfg_columns: columnsSpin.value
    property alias cfg_thresholdGreen: greenSpin.value
    property alias cfg_thresholdYellow: yellowSpin.value
    property alias cfg_thresholdOrange: orangeSpin.value

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: panelUsageCheck
            Kirigami.FormData.label: i18n("Panel:")
            text: i18n("Show total usage percentage next to the icon")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: aggregateCheck
            Kirigami.FormData.label: i18n("Popup:")
            text: i18n("Show a combined all-cores graph")
        }

        QQC2.SpinBox {
            id: columnsSpin
            Kirigami.FormData.label: i18n("Graph columns:")
            from: 0
            to: 8
            editable: true
            textFromValue: function (value) {
                return value === 0 ? i18n("Automatic") : String(value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10) || 0
            }
        }

        QQC2.SpinBox {
            id: historySpin
            Kirigami.FormData.label: i18n("Graphed trend:")
            from: 5
            to: 120
            editable: true
            textFromValue: function (value) {
                return i18np("%1 second", "%1 seconds", value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: sampleSpin
            Kirigami.FormData.label: i18n("Sample every:")
            from: 100
            to: 5000
            stepSize: 100
            editable: true
            textFromValue: function (value) {
                return i18n("%1 ms (popup open)", value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        QQC2.SpinBox {
            id: idleSpin
            from: 1
            to: 60
            editable: true
            textFromValue: function (value) {
                return i18np("%1 second (popup closed)", "%1 seconds (popup closed)", value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: greenSpin
            Kirigami.FormData.label: i18n("Green below:")
            from: 1
            to: 100
            editable: true
            textFromValue: function (value) {
                return i18n("%1%", value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        QQC2.SpinBox {
            id: yellowSpin
            Kirigami.FormData.label: i18n("Yellow below:")
            from: 1
            to: 100
            editable: true
            textFromValue: function (value) {
                return i18n("%1%", value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        QQC2.SpinBox {
            id: orangeSpin
            Kirigami.FormData.label: i18n("Orange below:")
            from: 1
            to: 100
            editable: true
            textFromValue: function (value) {
                return i18n("%1%", value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        QQC2.Label {
            text: i18n("At or above the orange threshold, cores are shown in red.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        }
    }
}
