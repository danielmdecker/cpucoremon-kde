import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: fullRep

    property var backend

    // Graph columns: configured, or a roughly square grid for the core count.
    readonly property int columns: {
        var configured = Plasmoid.configuration.columns
        if (configured > 0) {
            return configured
        }
        var n = Math.max(1, backend.listModel.count)
        return Math.min(6, Math.max(2, Math.round(Math.sqrt(n))))
    }

    readonly property int cellHeight: Kirigami.Units.gridUnit * 4.5

    // Tall enough for the whole grid where it fits on screen; Plasma clamps the
    // popup to the available height and the grid scrolls beyond that.
    readonly property real preferredHeightUnits: {
        var rows = Math.ceil(Math.max(1, backend.listModel.count) / columns)
        var units = 4.5 + rows * 4.5 + (Plasmoid.configuration.showAggregate ? 5.5 : 0)
        return Math.max(14, Math.min(32, units))
    }

    // Size hints read by the Plasma popup.
    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    Layout.preferredWidth: Kirigami.Units.gridUnit * (5.5 * columns + 1)
    Layout.preferredHeight: Kirigami.Units.gridUnit * preferredHeightUnits
    implicitWidth: Kirigami.Units.gridUnit * (5.5 * columns + 1)
    implicitHeight: Kirigami.Units.gridUnit * preferredHeightUnits

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ---- header: title, CPU model, overall usage ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 2
                    text: i18n("CPU Cores")
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: fullRep.backend.cpuModel.length > 0
                    text: fullRep.backend.cpuModel
                    elide: Text.ElideRight
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }

            PlasmaComponents.Label {
                text: i18n("%1%", Math.round(fullRep.backend.overallUsage))
                color: fullRep.backend.levelColor(fullRep.backend.overallLevel)
                font.weight: Font.Bold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            }
        }

        // ---- error banner ----
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            text: fullRep.backend.errorText
            visible: fullRep.backend.errorText.length > 0
        }

        // ---- combined all-cores graph ----
        CoreDelegate {
            Layout.fillWidth: true
            Layout.preferredHeight: fullRep.cellHeight
            visible: Plasmoid.configuration.showAggregate
            backend: fullRep.backend
            coreId: "cpu"
            label: i18n("All cores (%1)", fullRep.backend.listModel.count)
            usage: fullRep.backend.overallUsage
            level: fullRep.backend.overallLevel
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showAggregate
        }

        // ---- per-core graphs ----
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: gridView
                clip: true
                model: fullRep.backend.listModel
                cellWidth: Math.floor(width / fullRep.columns)
                cellHeight: fullRep.cellHeight
                boundsBehavior: Flickable.StopAtBounds

                delegate: CoreDelegate {
                    width: gridView.cellWidth
                    height: gridView.cellHeight
                    backend: fullRep.backend
                }

                // Empty state. Built from primitives rather than
                // Kirigami.PlaceholderMessage, which can fail to load inside a
                // running Plasma session (IconPropertiesGroup type conflict).
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Kirigami.Units.gridUnit * 2,
                                    Kirigami.Units.gridUnit * 16)
                    spacing: Kirigami.Units.smallSpacing
                    visible: gridView.count === 0 && fullRep.backend.errorText.length === 0

                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Kirigami.Units.iconSizes.large
                        implicitHeight: Kirigami.Units.iconSizes.large
                        source: fullRep.backend.cpuIcon
                        opacity: 0.5
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        text: i18n("Waiting for the first CPU sample…")
                    }
                }
            }
        }

        // ---- footer: window length ----
        PlasmaComponents.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            opacity: 0.6
            font: Kirigami.Theme.smallFont
            text: i18np("Last %1 second", "Last %1 seconds",
                        Plasmoid.configuration.historySeconds)
        }
    }
}
