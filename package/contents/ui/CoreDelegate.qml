import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One card: a core's label, its current usage, and the trend over the
// configured window. Also used for the combined all-cores graph.
Item {
    id: delegate

    property var backend

    // Roles provided by the ListModel in main.qml; the aggregate card, which is
    // not part of the model, assigns them where it is declared instead.
    required property string coreId
    required property string label
    required property real usage
    required property int level

    readonly property color levelColor: backend.levelColor(level)

    implicitHeight: Kirigami.Units.gridUnit * 4.5

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(Kirigami.Units.smallSpacing / 2)
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.alternateBackgroundColor
        border.width: 1
        border.color: Qt.rgba(delegate.levelColor.r, delegate.levelColor.g,
                              delegate.levelColor.b, hoverHandler.hovered ? 0.9 : 0.35)

        HoverHandler { id: hoverHandler }

        QQC2.ToolTip.visible: hoverHandler.hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        QQC2.ToolTip.text: {
            var pts = delegate.backend.historyFor(delegate.coreId)
            if (pts.length === 0) {
                return delegate.label
            }
            var min = 100, max = 0, sum = 0
            for (var i = 0; i < pts.length; i++) {
                min = Math.min(min, pts[i].v)
                max = Math.max(max, pts[i].v)
                sum += pts[i].v
            }
            return i18n("%1 — now %2%, avg %3%, min %4%, max %5%",
                        delegate.label, Math.round(delegate.usage),
                        Math.round(sum / pts.length), Math.round(min), Math.round(max))
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: delegate.label
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.8
                }

                PlasmaComponents.Label {
                    text: i18n("%1%", Math.round(delegate.usage))
                    color: delegate.levelColor
                    font.weight: Font.Bold
                    font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.95)
                }
            }

            // Trend graph. Points are plotted against their timestamps, so the
            // trace stays true to the window even if the sampling rate changes.
            Canvas {
                id: graph

                Layout.fillWidth: true
                Layout.fillHeight: true
                antialiasing: true

                readonly property color traceColor: delegate.levelColor

                onTraceColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: delegate.backend
                    function onSampleTickChanged() {
                        graph.requestPaint()
                    }
                }

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    if (width <= 0 || height <= 0) {
                        return
                    }

                    // Baseline and the 50% guide.
                    ctx.lineWidth = 1
                    ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r,
                                              Kirigami.Theme.textColor.g,
                                              Kirigami.Theme.textColor.b, 0.15)
                    ctx.beginPath()
                    ctx.moveTo(0, Math.round(height / 2) + 0.5)
                    ctx.lineTo(width, Math.round(height / 2) + 0.5)
                    ctx.moveTo(0, height - 0.5)
                    ctx.lineTo(width, height - 0.5)
                    ctx.stroke()

                    var pts = delegate.backend.historyFor(delegate.coreId)
                    if (pts.length < 2) {
                        return
                    }

                    var win = delegate.backend.historyWindowMs()
                    var now = pts[pts.length - 1].t
                    function px(t) {
                        return width * (1 - Math.max(0, Math.min(1, (now - t) / win)))
                    }
                    function py(v) {
                        return height - (Math.max(0, Math.min(100, v)) / 100) * (height - 1) - 0.5
                    }

                    // Filled area under the trace.
                    ctx.beginPath()
                    ctx.moveTo(px(pts[0].t), height)
                    for (var i = 0; i < pts.length; i++) {
                        ctx.lineTo(px(pts[i].t), py(pts[i].v))
                    }
                    ctx.lineTo(px(pts[pts.length - 1].t), height)
                    ctx.closePath()
                    ctx.fillStyle = Qt.rgba(traceColor.r, traceColor.g, traceColor.b, 0.25)
                    ctx.fill()

                    // The trace itself.
                    ctx.beginPath()
                    ctx.moveTo(px(pts[0].t), py(pts[0].v))
                    for (var j = 1; j < pts.length; j++) {
                        ctx.lineTo(px(pts[j].t), py(pts[j].v))
                    }
                    ctx.lineWidth = 1.5
                    ctx.lineJoin = "round"
                    ctx.strokeStyle = traceColor
                    ctx.stroke()

                    // Current value marker at the right edge.
                    ctx.beginPath()
                    ctx.arc(px(now), py(pts[pts.length - 1].v), 2, 0, Math.PI * 2)
                    ctx.fillStyle = traceColor
                    ctx.fill()
                }
            }
        }
    }
}
