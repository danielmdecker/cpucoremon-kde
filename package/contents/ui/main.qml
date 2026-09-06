import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---- state ----
    property string errorText: ""           // non-empty when /proc/stat could not be read
    property real overallUsage: 0           // 0..100 across all cores
    property string cpuModel: ""            // /proc/cpuinfo model name, for the popup header

    // Bumped after every completed sample. Graphs repaint on the change; the
    // histories themselves live in a plain JS object, which has no change signal.
    property int sampleTick: 0

    // Previous /proc/stat jiffy counters, keyed by cpu name ("cpu", "cpu0", ...).
    property var prevTotals: ({})
    // Rolling usage history, keyed the same way: [{t: msSinceEpoch, v: percent}].
    property var histories: ({})

    // Guards against piling up reads if one sample outlives its interval, and
    // against sampling before the data source is live (property-change handlers
    // can run before the component is complete).
    property bool sampling: false
    property double samplingSince: 0
    property bool ready: false

    // Expose the view model to the full representation.
    property alias listModel: coreModel

    readonly property int overallLevel: usageLevel(overallUsage)

    // True whenever the graphs are on screen: the popup is open, or the widget
    // sits on the desktop, where the full representation is always shown.
    readonly property bool graphsVisible: root.expanded
        || Plasmoid.formFactor === PlasmaCore.Types.Planar

    // Bundled round CPU icon, used in the widget list and the popup's empty state.
    readonly property url cpuIcon: Qt.resolvedUrl("../icons/cpucoremon.svg")

    Plasmoid.icon: cpuIcon
    Plasmoid.title: i18n("CPU Core Monitor")
    toolTipMainText: i18n("CPU Core Monitor")
    toolTipSubText: {
        if (errorText.length > 0) {
            return errorText
        }
        var s = i18n("Total: %1%", Math.round(overallUsage))
        if (coreModel.count > 0) {
            s += "\n" + i18np("%1 logical core", "%1 logical cores", coreModel.count)
        }
        if (cpuModel.length > 0) {
            s += "\n" + cpuModel
        }
        return s
    }

    preferredRepresentation: compactRepresentation

    ListModel { id: coreModel }

    // ---- command execution (Plasma 6 executable engine) ----
    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        property var callbacks: ({})

        onNewData: function (sourceName, data) {
            var cb = callbacks[sourceName]
            delete callbacks[sourceName]
            disconnectSource(sourceName)
            if (cb) {
                cb(data["stdout"] || "", data["stderr"] || "", data["exit code"])
            }
        }

        // Run `cmd` once; `cb(stdout, stderr, exitCode)` is optional (null = fire and forget).
        function run(cmd, cb) {
            if (cb) {
                callbacks[cmd] = cb
            }
            connectSource(cmd)
        }
    }

    // ---- usage levels ----
    // 0 = idle (green), 1 = light (yellow), 2 = busy (orange), 3 = saturated (red).
    function usageLevel(percent) {
        if (percent < Plasmoid.configuration.thresholdGreen) {
            return 0
        }
        if (percent < Plasmoid.configuration.thresholdYellow) {
            return 1
        }
        if (percent < Plasmoid.configuration.thresholdOrange) {
            return 2
        }
        return 3
    }

    // Breeze's standard icon colours, so the bands stay legible in light and dark schemes.
    function levelColor(level) {
        switch (level) {
        case 0: return "#27ae60"
        case 1: return "#c9ce3b"
        case 2: return "#f67400"
        default: return "#da4453"
        }
    }

    function historyWindowMs() {
        return Math.max(5, Plasmoid.configuration.historySeconds) * 1000
    }

    // Samples for one cpu key, oldest first. Empty until the second sample:
    // usage is a delta, so a single reading says nothing.
    function historyFor(key) {
        return histories[key] || []
    }

    function pushHistory(key, t, v) {
        var arr = histories[key] || []
        arr.push({ t: t, v: v })
        // Keep one sample older than the window so the trace reaches the left edge.
        var cutoff = t - historyWindowMs()
        while (arr.length > 2 && arr[1].t < cutoff) {
            arr.shift()
        }
        histories[key] = arr
    }

    // ---- sampling ----
    function sample() {
        if (!ready) {
            return
        }
        // A reply that never arrives must not wedge the widget for good.
        if (sampling && Date.now() - samplingSince < 5000) {
            return
        }
        sampling = true
        samplingSince = Date.now()
        executable.run("cat /proc/stat", function (stdout, stderr, code) {
            root.sampling = false
            if (code !== 0) {
                root.errorText = (stderr.trim() || i18n("Could not read /proc/stat."))
                return
            }
            root.errorText = ""
            root.parseStat(stdout)
        })
    }

    // Per-cpu jiffy counters: user nice system idle iowait irq softirq steal ...
    // Usage is the share of non-idle jiffies since the previous sample. guest and
    // guest_nice are already folded into user/nice, so they are deliberately dropped.
    function parseStat(stdout) {
        var now = Date.now()
        var lines = stdout.split("\n")
        var totals = ({})
        var keys = []

        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].trim().split(/\s+/)
            var key = parts[0]
            if (!/^cpu[0-9]*$/.test(key) || parts.length < 5) {
                continue
            }
            var idle = Number(parts[4]) + (Number(parts[5]) || 0)   // idle + iowait
            var total = idle
            for (var f = 1; f <= 8; f++) {
                if (f === 4 || f === 5) {
                    continue
                }
                total += Number(parts[f]) || 0
            }
            totals[key] = { idle: idle, total: total }
            if (key !== "cpu") {
                keys.push(key)
            }
        }

        keys.sort(function (a, b) {
            return Number(a.substring(3)) - Number(b.substring(3))
        })

        var usages = ({})
        for (var key in totals) {
            var prev = prevTotals[key]
            var cur = totals[key]
            if (!prev) {
                continue
            }
            var dTotal = cur.total - prev.total
            var dIdle = cur.idle - prev.idle
            // A zero (or negative, after a suspend) delta carries no information;
            // hold the previous reading rather than dropping to 0%.
            if (dTotal <= 0) {
                var hist = historyFor(key)
                usages[key] = hist.length > 0 ? hist[hist.length - 1].v : 0
            } else {
                usages[key] = Math.max(0, Math.min(100, (dTotal - dIdle) / dTotal * 100))
            }
            pushHistory(key, now, usages[key])
        }
        prevTotals = totals

        if ("cpu" in usages) {
            overallUsage = usages["cpu"]
        }

        // Update in place so the GridView keeps its scroll position across samples.
        var rebuild = coreModel.count !== keys.length
        if (rebuild) {
            coreModel.clear()
        }
        for (var k = 0; k < keys.length; k++) {
            var name = keys[k]
            var usage = (name in usages) ? usages[name] : 0
            var row = {
                coreId: name,
                label: i18n("Core %1", name.substring(3)),
                usage: usage,
                level: usageLevel(usage)
            }
            if (rebuild) {
                coreModel.append(row)
            } else {
                coreModel.set(k, row)
            }
        }

        sampleTick++
    }

    function readCpuModel() {
        executable.run("grep -m1 '^model name' /proc/cpuinfo",
            function (stdout, stderr, code) {
                if (code !== 0) {
                    return
                }
                var idx = stdout.indexOf(":")
                if (idx >= 0) {
                    root.cpuModel = stdout.substring(idx + 1).trim()
                }
            })
    }

    // ---- representations ----
    compactRepresentation: MouseArea {
        id: compact

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property bool showText: Plasmoid.configuration.showPanelUsage && !vertical

        Layout.minimumWidth: vertical ? 0 : compactRow.implicitWidth
        Layout.preferredWidth: vertical ? 0 : compactRow.implicitWidth
        Layout.minimumHeight: vertical ? width : 0
        Layout.preferredHeight: vertical ? width : 0
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            // Circular gauge: the disc carries the usage band colour, the white
            // ring inside its rim tracks the exact overall percentage.
            Canvas {
                id: gauge

                readonly property color base: root.levelColor(root.overallLevel)
                readonly property real fraction: Math.max(0, Math.min(1, root.overallUsage / 100))

                Layout.fillHeight: true
                Layout.preferredWidth: compact.height
                antialiasing: true
                opacity: compact.containsMouse ? 1.0 : 0.92

                onBaseChanged: requestPaint()
                onFractionChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()

                    var size = Math.min(width, height)
                    if (size <= 0) {
                        return
                    }
                    var cx = width / 2
                    var cy = height / 2
                    var radius = size / 2 - 1
                    var ring = Math.max(1.5, size * 0.14)
                    var ringR = radius - ring / 2

                    // Disc
                    ctx.beginPath()
                    ctx.arc(cx, cy, radius, 0, Math.PI * 2)
                    ctx.fillStyle = base
                    ctx.fill()
                    ctx.lineWidth = Math.max(1, size * 0.04)
                    ctx.strokeStyle = Qt.darker(base, 1.5)
                    ctx.stroke()

                    // Ring track, then the filled portion, from 12 o'clock clockwise.
                    ctx.beginPath()
                    ctx.arc(cx, cy, ringR, 0, Math.PI * 2)
                    ctx.lineWidth = ring
                    ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.22)
                    ctx.stroke()

                    if (fraction > 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, ringR, -Math.PI / 2,
                                -Math.PI / 2 + Math.PI * 2 * fraction)
                        ctx.lineWidth = ring
                        ctx.lineCap = "butt"
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.9)
                        ctx.stroke()
                    }
                }
            }

            PlasmaComponents.Label {
                visible: compact.showText
                text: i18n("%1%", Math.round(root.overallUsage))
                color: root.overallLevel >= 3 ? Kirigami.Theme.negativeTextColor
                     : root.overallLevel === 2 ? Kirigami.Theme.neutralTextColor
                     : Kirigami.Theme.textColor
            }
        }
    }

    fullRepresentation: FullRepresentation {
        backend: root
    }

    // ---- lifecycle ----
    Component.onCompleted: {
        ready = true
        readCpuModel()
        sample()
    }

    // Fast sampling while the popup is open, for a smooth 10-second trend.
    Timer {
        interval: Math.max(100, Plasmoid.configuration.sampleInterval)
        repeat: true
        running: root.graphsVisible
        onTriggered: root.sample()
    }

    // Slow sampling while collapsed: the panel gauge and tooltip stay live without
    // a CPU monitor becoming a meaningful CPU consumer of its own.
    Timer {
        interval: Math.max(1, Plasmoid.configuration.idleSampleInterval) * 1000
        repeat: true
        running: !root.graphsVisible
        onTriggered: root.sample()
    }

    // The graphs are time-based, so the coarse idle samples would show up as a
    // flat run across the window. Start the trend fresh each time the popup opens.
    onGraphsVisibleChanged: {
        if (root.graphsVisible) {
            root.histories = ({})
            root.sample()
        }
    }
}
