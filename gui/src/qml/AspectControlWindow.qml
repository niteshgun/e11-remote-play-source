// e11: floating, draggable quick menu shown while streaming.
// Picture (Fit/Stretch), stream bitrate (auto/manual), performance (auto quality for the
// Mac's chip, render quality, V-Sync) and colour filters for the Retina display.
import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window

import org.streetpea.chiaking

Window {
    id: quickWindow

    property bool shown: false
    property var hostWindow: null
    property bool collapsed: false
    property bool expanded: false

    // ---------- persisted preferences ----------
    Settings {
        id: prefs
        category: "e11_quick_menu"
        property int posX: -1
        property int posY: -1
        property bool collapsed: false
        // Stream
        property bool autoBitrate: true
        property int manualBitrateMbps: 30
        // Performance
        property bool autoPerformance: true
        // Colour: -1 = follow "Retina Vivid Colors" setting, 0 Natural, 1 Vivid, 2 Cinema, 3 Game, 4 Custom
        property int colorPreset: -1
        property real customBrightness: 0.0
        property real customContrast: 1.0
        property real customSaturation: 1.0
        property real customWarmth: 0.0
    }

    visible: shown
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    modality: Qt.NonModal
    width: Math.max(pill.implicitWidth, expanded ? 360 : 0)
    height: pill.implicitHeight + (expanded ? card.implicitHeight + 8 : 0)

    Material.theme: Material.Dark
    Material.accent: "#2f8cff"

    Component.onCompleted: {
        collapsed = prefs.collapsed;
        applyBitratePolicy();
    }

    function placeDefault() {
        if (prefs.posX >= 0 && prefs.posY >= 0) {
            x = prefs.posX;
            y = prefs.posY;
        } else if (hostWindow) {
            x = hostWindow.x + hostWindow.width - pill.implicitWidth - 24;
            y = hostWindow.y + 48;
        }
    }

    onVisibleChanged: {
        if (visible) {
            placeDefault();
            applyColor();
            perf.start();
        } else {
            perf.stop();
        }
    }
    // The system drag (startSystemMove) owns the mouse, so save on every position change
    onXChanged: if (visible) prefs.posX = x
    onYChanged: if (visible) prefs.posY = y
    onCollapsedChanged: {
        prefs.collapsed = collapsed;
        if (collapsed)
            expanded = false;
    }

    // ---------- picture ----------
    function setMode(mode) {
        // Stretch should cover the whole screen, title-bar area included
        if (mode === ChiakiWindow.VideoMode.Stretch)
            Chiaki.window.fullscreenTime();
        Chiaki.window.videoMode = mode;
    }

    // ---------- stream bitrate ----------
    // Bitrate is agreed with the PS5 when the stream starts, so changes apply on the next connect.
    // Auto: start at a high ceiling on the home network; the PS5 then lowers/raises its encoder
    // bitrate by itself from the packet-loss reports we send every 200 ms.
    function applyBitratePolicy() {
        if (prefs.autoBitrate) {
            Chiaki.settings.bitrateLocalPS5 = 40000;
            Chiaki.settings.bitrateRemotePS5 = 0; // internet: resolution default (15 Mbps at 1080p)
        } else {
            Chiaki.settings.bitrateLocalPS5 = prefs.manualBitrateMbps * 1000;
            Chiaki.settings.bitrateRemotePS5 = prefs.manualBitrateMbps * 1000;
        }
    }

    // ---------- colour filters ----------
    readonly property var colorPresets: [
        { name: qsTr("Natural"), b: 0.00, c: 1.00, s: 1.00, t: 0.00 },
        { name: qsTr("Vivid"),   b: 0.00, c: 1.05, s: 1.15, t: 0.00 },
        { name: qsTr("Cinema"),  b: -0.02, c: 1.08, s: 0.95, t: -0.08 },
        { name: qsTr("Game"),    b: 0.03, c: 1.10, s: 1.20, t: 0.03 }
    ]
    readonly property int effectivePreset: prefs.colorPreset >= 0 ? prefs.colorPreset
                                         : (Chiaki.settings.retinaVivid ? 1 : 0)

    function applyColor() {
        let p = effectivePreset;
        if (p === 4)
            Chiaki.window.setColorAdjust(prefs.customBrightness, prefs.customContrast,
                                         prefs.customSaturation, prefs.customWarmth);
        else {
            let v = colorPresets[p];
            Chiaki.window.setColorAdjust(v.b, v.c, v.s, v.t);
        }
    }
    function pickPreset(p) {
        if (p === 4 && prefs.colorPreset !== 4 && effectivePreset < 4) {
            // start "Custom" from whatever is showing now
            let v = colorPresets[effectivePreset];
            prefs.customBrightness = v.b; prefs.customContrast = v.c;
            prefs.customSaturation = v.s; prefs.customWarmth = v.t;
        }
        prefs.colorPreset = p;
        applyColor();
    }

    // ---------- performance ----------
    // Render quality levels map to ChiakiWindow.VideoPreset:
    // 0 Fast, 1 Default, 2 High Quality, 3 HQ + FSR sharpening, 4 HQ + neural (FSRCNNX) upscaling
    readonly property var qualityNames: [qsTr("Fast"), qsTr("Balanced"), qsTr("High"), qsTr("Sharp"), qsTr("Ultra")]
    readonly property var qualityPresets: [ChiakiWindow.VideoPreset.Fast, ChiakiWindow.VideoPreset.Default,
        ChiakiWindow.VideoPreset.HighQuality, ChiakiWindow.VideoPreset.HighQualitySpatial,
        ChiakiWindow.VideoPreset.HighQualityAdvancedSpatial]
    readonly property string chip: Chiaki.window.chipName()

    // Best level this Mac should handle comfortably at 1080p60
    function chipMaxLevel() {
        let c = chip.toUpperCase();
        if (/M[3-9]/.test(c) || c.indexOf("PRO") >= 0 || c.indexOf("MAX") >= 0 || c.indexOf("ULTRA") >= 0)
            return 4; // newer / bigger GPUs: neural upscaling
        if (/M[12]/.test(c))
            return 3; // M1/M2: FSR sharpening
        return 2;
    }
    function currentLevel() {
        let i = qualityPresets.indexOf(Chiaki.window.videoPreset);
        return i < 0 ? 2 : i;
    }
    function setLevel(l) {
        l = Math.max(0, Math.min(4, l));
        Chiaki.window.videoPreset = qualityPresets[l];
    }

    QtObject {
        id: perf
        property int maxLevel: 2
        property int badSeconds: 0
        property int goodSeconds: 0
        property string status: ""
        function start() {
            maxLevel = quickWindow.chipMaxLevel();
            badSeconds = 0;
            goodSeconds = 0;
            if (prefs.autoPerformance)
                quickWindow.setLevel(maxLevel);
            perfTimer.start();
        }
        function stop() { perfTimer.stop(); }
    }
    // Watches dropped frames every second: steps quality down if the Mac can't keep up,
    // and back up after a long clean stretch.
    Timer {
        id: perfTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (!prefs.autoPerformance) {
                perf.status = "";
                return;
            }
            let dropped = Chiaki.window.droppedFrames;
            if (dropped >= 3) {
                perf.badSeconds++;
                perf.goodSeconds = 0;
            } else {
                perf.goodSeconds++;
                perf.badSeconds = 0;
            }
            let lvl = quickWindow.currentLevel();
            if (perf.badSeconds >= 3 && lvl > 1) {
                quickWindow.setLevel(lvl - 1);
                perf.badSeconds = 0;
                perf.status = qsTr("Lowered quality to keep it smooth");
            } else if (perf.goodSeconds >= 45 && lvl < perf.maxLevel) {
                quickWindow.setLevel(lvl + 1);
                perf.goodSeconds = 0;
                perf.status = qsTr("Raised quality");
            }
        }
    }

    // ---------- UI ----------
    component Chip: Rectangle {
        id: chipRoot
        property string text
        property bool selected: false
        property string tip: ""
        signal clicked()
        implicitHeight: 28
        implicitWidth: chipLabel.implicitWidth + 20
        radius: 14
        color: selected ? Material.accent : (chipHover.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.05))
        Label {
            id: chipLabel
            anchors.centerIn: parent
            text: chipRoot.text
            font.pixelSize: 12
            font.bold: chipRoot.selected
            color: "white"
        }
        MouseArea {
            id: chipHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chipRoot.clicked()
        }
        ToolTip.visible: tip !== "" && chipHover.containsMouse
        ToolTip.delay: 600
        ToolTip.text: tip
    }

    component SectionTitle: Label {
        font.pixelSize: 11
        font.bold: true
        font.capitalization: Font.AllUppercase
        color: Qt.rgba(1, 1, 1, 0.55)
        Layout.topMargin: 6
    }

    component Toggle: RowLayout {
        id: toggleRoot
        property string text
        property alias checked: sw.checked
        signal toggled()
        Layout.fillWidth: true
        Label { text: toggleRoot.text; color: "white"; font.pixelSize: 13; Layout.fillWidth: true }
        Switch { id: sw; onToggled: toggleRoot.toggled() }
    }

    component SliderRow: RowLayout {
        id: sliderRoot
        property string text
        property alias from: sl.from
        property alias to: sl.to
        property alias value: sl.value
        property alias stepSize: sl.stepSize
        property string valueText: ""
        signal moved()
        Layout.fillWidth: true
        Label { text: sliderRoot.text; color: "white"; font.pixelSize: 12; Layout.preferredWidth: 78 }
        Slider { id: sl; Layout.fillWidth: true; onMoved: sliderRoot.moved() }
        Label { text: sliderRoot.valueText; color: Qt.rgba(1, 1, 1, 0.7); font.pixelSize: 12; Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight }
    }

    // Top pill: grip, Fit / Stretch, menu, collapse
    Rectangle {
        id: pill
        anchors.right: parent.right
        implicitWidth: row.implicitWidth + 16
        implicitHeight: 44
        radius: 22
        color: Qt.rgba(0.08, 0.08, 0.10, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1

        RowLayout {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 4

            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 32
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: 3
                    Repeater {
                        model: 6
                        Rectangle { width: 3; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.55) }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    onPressed: quickWindow.startSystemMove()
                }
            }

            Chip {
                visible: !quickWindow.collapsed
                text: qsTr("Fit")
                tip: qsTr("Original 16:9 shape, bars if the screen is taller")
                selected: Chiaki.window.videoMode === ChiakiWindow.VideoMode.Normal
                onClicked: quickWindow.setMode(ChiakiWindow.VideoMode.Normal)
            }
            Chip {
                visible: !quickWindow.collapsed
                text: qsTr("Stretch")
                tip: qsTr("Go full screen and stretch the picture to fill it")
                selected: Chiaki.window.videoMode === ChiakiWindow.VideoMode.Stretch
                onClicked: quickWindow.setMode(ChiakiWindow.VideoMode.Stretch)
            }
            Chip {
                visible: !quickWindow.collapsed
                text: "⚙"
                tip: qsTr("Quick menu: bitrate, performance, colour")
                selected: quickWindow.expanded
                onClicked: quickWindow.expanded = !quickWindow.expanded
            }
            Chip {
                text: quickWindow.collapsed ? "⤢" : "–"
                tip: quickWindow.collapsed ? qsTr("Show") : qsTr("Shrink")
                onClicked: quickWindow.collapsed = !quickWindow.collapsed
            }
        }
    }

    // Expanded quick menu
    Rectangle {
        id: card
        visible: quickWindow.expanded
        anchors.top: pill.bottom
        anchors.topMargin: 8
        anchors.right: parent.right
        width: 360
        implicitHeight: content.implicitHeight + 24
        radius: 16
        color: Qt.rgba(0.08, 0.08, 0.10, 0.92)
        border.color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 6

            // ----- Live stats -----
            Label {
                Layout.fillWidth: true
                color: Qt.rgba(1, 1, 1, 0.75)
                font.pixelSize: 12
                text: qsTr("Live: %1 Mbps · %2 dropped/s · %3")
                      .arg(Chiaki.session ? Chiaki.session.measuredBitrate.toFixed(1) : "–")
                      .arg(Chiaki.window.droppedFrames)
                      .arg(quickWindow.chip)
            }

            // ----- Stream -----
            SectionTitle { text: qsTr("Stream bitrate") }
            Toggle {
                text: qsTr("Auto (PS5 adapts to your network)")
                checked: prefs.autoBitrate
                onToggled: { prefs.autoBitrate = checked; quickWindow.applyBitratePolicy(); }
            }
            SliderRow {
                visible: !prefs.autoBitrate
                text: qsTr("Manual")
                from: 5; to: 100; stepSize: 1
                value: prefs.manualBitrateMbps
                valueText: value + " Mbps"
                onMoved: { prefs.manualBitrateMbps = value; quickWindow.applyBitratePolicy(); }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.5)
                text: qsTr("Bitrate is set when the stream starts; changes apply next time you connect.")
            }

            // ----- Performance -----
            SectionTitle { text: qsTr("Performance") }
            Toggle {
                text: qsTr("Auto (best quality this Mac can hold)")
                checked: prefs.autoPerformance
                onToggled: {
                    prefs.autoPerformance = checked;
                    if (checked)
                        perf.start();
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: quickWindow.qualityNames
                    delegate: Chip {
                        required property int index
                        required property string modelData
                        text: modelData
                        selected: quickWindow.currentLevel() === index
                        tip: [qsTr("Lowest GPU use"), qsTr("Good quality, light"), qsTr("High quality scaling"),
                              qsTr("High quality + FSR sharpening for Retina"),
                              qsTr("High quality + neural upscaling (FSRCNNX on the GPU)")][index]
                        onClicked: {
                            prefs.autoPerformance = false;
                            quickWindow.setLevel(index);
                            Chiaki.settings.videoPreset = index;
                        }
                    }
                }
            }
            Label {
                visible: prefs.autoPerformance && perf.status !== ""
                text: perf.status
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            Toggle {
                text: qsTr("V-Sync (no tearing, slightly more latency)")
                checked: Chiaki.settings.vSyncEnabled
                onToggled: Chiaki.settings.vSyncEnabled = checked
            }

            // ----- Colour -----
            SectionTitle { text: qsTr("Colour (Retina display)") }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [qsTr("Natural"), qsTr("Vivid"), qsTr("Cinema"), qsTr("Game"), qsTr("Custom")]
                    delegate: Chip {
                        required property int index
                        required property string modelData
                        text: modelData
                        selected: quickWindow.effectivePreset === index
                        onClicked: quickWindow.pickPreset(index)
                    }
                }
            }
            ColumnLayout {
                visible: quickWindow.effectivePreset === 4
                Layout.fillWidth: true
                spacing: 0
                SliderRow {
                    text: qsTr("Brightness")
                    from: -0.2; to: 0.2; stepSize: 0.01
                    value: prefs.customBrightness
                    valueText: (value >= 0 ? "+" : "") + Math.round(value * 100)
                    onMoved: { prefs.customBrightness = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Contrast")
                    from: 0.8; to: 1.3; stepSize: 0.01
                    value: prefs.customContrast
                    valueText: Math.round(value * 100) + "%"
                    onMoved: { prefs.customContrast = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Saturation")
                    from: 0.5; to: 1.6; stepSize: 0.01
                    value: prefs.customSaturation
                    valueText: Math.round(value * 100) + "%"
                    onMoved: { prefs.customSaturation = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Warmth")
                    from: -0.3; to: 0.3; stepSize: 0.01
                    value: -prefs.customWarmth
                    valueText: (value >= 0 ? "+" : "") + Math.round(value * 100)
                    // libplacebo: negative temperature = warmer
                    onMoved: { prefs.customWarmth = -value; quickWindow.applyColor(); }
                }
            }
        }
    }
}
