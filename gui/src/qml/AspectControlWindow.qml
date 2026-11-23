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
        category: "e11_quick_menu_v2"
        property int posX: -1
        property int posY: -1
        property bool collapsed: false
        // Stream
        property bool autoBitrate: true
        property int manualBitrateMbps: 30
        // Performance
        property bool autoPerformance: true
        // Look: -1 = follow "Retina Vivid Colors" setting; otherwise index into lookPresets,
        // lookPresets.length = Custom
        property int colorPreset: -1
        property real customBrightness: 0.0
        property real customContrast: 1.0
        property real customSaturation: 1.0
        property real customWarmth: 0.0
        property real customSharpen: 0.0
        property real customClarity: 0.0
        property real customVibrance: 0.0
        property real customSplit: 0.0
        property real customVignette: 0.0
        property real customGrain: 0.0
        property real customBloom: 0.0
        property real customRays: 0.0
        property real customShadows: 0.6
        property bool advancedOpen: false
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

    // ---------- controllers ----------
    property int controllerTick: 0   // bumps every 2 s so battery / connection refresh
    Timer { interval: 2000; repeat: true; running: quickWindow.visible; onTriggered: quickWindow.controllerTick++ }
    function controllerLine(c) {
        controllerTick; // dependency for refresh
        let parts = [c.friendlyName(), c.wired() ? qsTr("USB") : qsTr("Bluetooth")];
        let b = c.batteryPercent();
        if (!c.wired() && b >= 0)
            parts.push(b + "%");
        return parts.join(" · ");
    }
    readonly property bool psControllerOnUsb: {
        controllerTick;
        for (let i = 0; i < Chiaki.controllers.length; i++) {
            let k = Chiaki.controllers[i].kind();
            if ((k === "ps5" || k === "ps5edge" || k === "ps4") && Chiaki.controllers[i].wired())
                return true;
        }
        return false;
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
            Chiaki.settings.bitrateLocalPS5 = 20000; // Wi-Fi safe; the PS5 still adapts down by itself
            Chiaki.settings.bitrateRemotePS5 = 0; // internet: resolution default (15 Mbps at 1080p)
        } else {
            Chiaki.settings.bitrateLocalPS5 = prefs.manualBitrateMbps * 1000;
            Chiaki.settings.bitrateRemotePS5 = prefs.manualBitrateMbps * 1000;
        }
    }

    // ---------- looks (colour + photo effects) ----------
    // b brightness, c contrast, s saturation, t temperature (negative = warmer),
    // then GPU photo effects: sh sharpen, cl clarity, vb vibrance, sp teal/orange, vg vignette, gr grain
    readonly property var lookPresets: [
        { name: qsTr("Natural"), tip: qsTr("As the game was graded"),
          b: 0.00, c: 1.00, s: 1.00, t: 0.00,  sh: 0.0, cl: 0.0, vb: 0.0, sp: 0.0, vg: 0.0, gr: 0.0, bl: 0, ry: 0, sd: 0.35 },
        { name: qsTr("Game"), tip: qsTr("Punchy and bright"),
          b: 0.03, c: 1.10, s: 1.20, t: 0.03,  sh: 0.0, cl: 0.0, vb: 0.0, sp: 0.0, vg: 0.0, gr: 0.0, bl: 0, ry: 0, sd: 0.6 },
        { name: qsTr("Game+"), tip: qsTr("Game look, crisper and deeper"),
          b: 0.03, c: 1.12, s: 1.22, t: 0.03,  sh: 0.35, cl: 0.35, vb: 0.2, sp: 0.0, vg: 0.0, gr: 0.0, bl: 0.25, ry: 0, sd: 0.7 },
        { name: qsTr("Vivid"), tip: qsTr("Rich P3 colour, sharper"),
          b: 0.01, c: 1.14, s: 1.35, t: 0.00,  sh: 0.3, cl: 0.2, vb: 0.45, sp: 0.0, vg: 0.0, gr: 0.0, bl: 0.3, ry: 0, sd: 0.6 },
        { name: qsTr("DSLR"), tip: qsTr("Photo look: clarity, vibrance, light vignette"),
          b: 0.00, c: 1.10, s: 1.08, t: -0.03, sh: 0.45, cl: 0.7, vb: 0.5, sp: 0.15, vg: 0.35, gr: 0.0, bl: 0.25, ry: 0, sd: 0.7 },
        { name: qsTr("HDR Pop"), tip: qsTr("Big local contrast, very crisp"),
          b: -0.02, c: 1.18, s: 1.25, t: 0.00, sh: 0.55, cl: 1.0, vb: 0.4, sp: 0.0, vg: 0.15, gr: 0.0, bl: 0.45, ry: 0.2, sd: 0.9 },
        { name: qsTr("Cinema"), tip: qsTr("Warm film grade, vignette and grain"),
          b: -0.03, c: 1.15, s: 0.92, t: -0.15, sh: 0.15, cl: 0.3, vb: 0.0, sp: 0.6, vg: 0.55, gr: 0.25, bl: 0.5, ry: 0.3, sd: 0.45 },
        { name: qsTr("Blockbuster"), tip: qsTr("Teal shadows, orange highlights"),
          b: -0.01, c: 1.15, s: 1.05, t: -0.04, sh: 0.25, cl: 0.4, vb: 0.2, sp: 1.2, vg: 0.4, gr: 0.1, bl: 0.55, ry: 0.35, sd: 0.55 },
        { name: qsTr("Vice Sunset"), tip: qsTr("Warm, glowing, saturated"),
          b: 0.02, c: 1.08, s: 1.30, t: -0.25, sh: 0.2, cl: 0.2, vb: 0.4, sp: 0.35, vg: 0.3, gr: 0.0, bl: 0.7, ry: 0.6, sd: 0.5 },
        { name: qsTr("Night"), tip: qsTr("Cool, moody, deep blacks"),
          b: -0.04, c: 1.20, s: 1.05, t: 0.20,  sh: 0.25, cl: 0.4, vb: 0.25, sp: 0.0, vg: 0.5, gr: 0.1, bl: 0.6, ry: 0.15, sd: 1.1 },
        { name: qsTr("Noir"), tip: qsTr("Black and white film"),
          b: 0.00, c: 1.28, s: 0.00, t: 0.00,  sh: 0.3, cl: 0.6, vb: 0.0, sp: 0.0, vg: 0.6, gr: 0.35, bl: 0.3, ry: 0.2, sd: 0.5 }
    ]
    readonly property int customLook: lookPresets.length
    readonly property int effectivePreset: prefs.colorPreset >= 0 ? prefs.colorPreset
                                         : (Chiaki.settings.retinaVivid ? 1 : 0)

    function applyLook(v) {
        Chiaki.window.setColorAdjust(v.b, v.c, v.s, v.t);
        Chiaki.window.setPhotoEffects(v.sh, v.cl, v.vb, v.sp, v.vg, v.gr);
        Chiaki.window.setLightEffects(v.bl, v.ry);
        // MacBook panels crush shadows compared with a TV, so every look lifts dark tones a bit
        Chiaki.window.setShadowDetail(v.sd);
    }
    function customLookValues() {
        return { b: prefs.customBrightness, c: prefs.customContrast, s: prefs.customSaturation, t: prefs.customWarmth,
                 sh: prefs.customSharpen, cl: prefs.customClarity, vb: prefs.customVibrance,
                 sp: prefs.customSplit, vg: prefs.customVignette, gr: prefs.customGrain,
                 bl: prefs.customBloom, ry: prefs.customRays, sd: prefs.customShadows };
    }
    function applyColor() {
        let p = effectivePreset;
        applyLook(p === customLook ? customLookValues() : lookPresets[Math.min(p, lookPresets.length - 1)]);
    }
    function pickPreset(p) {
        if (p === customLook && prefs.colorPreset !== customLook) {
            // start "Custom" from whatever look is showing now
            let v = lookPresets[Math.min(effectivePreset, lookPresets.length - 1)];
            prefs.customBrightness = v.b; prefs.customContrast = v.c;
            prefs.customSaturation = v.s; prefs.customWarmth = v.t;
            prefs.customSharpen = v.sh; prefs.customClarity = v.cl; prefs.customVibrance = v.vb;
            prefs.customSplit = v.sp; prefs.customVignette = v.vg; prefs.customGrain = v.gr;
            prefs.customBloom = v.bl; prefs.customRays = v.ry; prefs.customShadows = v.sd;
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
        return 2; // smoothness first: auto never goes above "High" (pick Sharp/Ultra by hand)
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
            }
            // Never step quality back up mid-session: every switch recompiles shaders and hitches.
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
                visible: !quickWindow.collapsed && Chiaki.controllers.length > 0
                text: "🎮 " + (Chiaki.controllers.length ? quickWindow.controllerLine(Chiaki.controllers[0]) : "")
                tip: Chiaki.controllers.length > 1 ? qsTr("%1 controllers connected").arg(Chiaki.controllers.length)
                                                   : qsTr("Controller connected")
                onClicked: quickWindow.expanded = true
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

            // ----- Looks -----
            SectionTitle { text: qsTr("Look") }

            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: quickWindow.lookPresets.length + 1
                    delegate: Chip {
                        required property int index
                        text: index === quickWindow.customLook ? qsTr("Custom") : quickWindow.lookPresets[index].name
                        tip: index === quickWindow.customLook ? qsTr("Your own mix") : quickWindow.lookPresets[index].tip
                        selected: quickWindow.effectivePreset === index
                        onClicked: quickWindow.pickPreset(index)
                    }
                }
            }
            ColumnLayout {
                visible: quickWindow.effectivePreset === quickWindow.customLook
                Layout.fillWidth: true
                spacing: 0
                SliderRow {
                    text: qsTr("Shadow detail")
                    from: 0.0; to: 2.0; stepSize: 0.05
                    value: prefs.customShadows
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customShadows = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Brightness")
                    from: -0.2; to: 0.2; stepSize: 0.01
                    value: prefs.customBrightness
                    valueText: (value >= 0 ? "+" : "") + Math.round(value * 100)
                    onMoved: { prefs.customBrightness = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Contrast")
                    from: 0.8; to: 1.4; stepSize: 0.01
                    value: prefs.customContrast
                    valueText: Math.round(value * 100) + "%"
                    onMoved: { prefs.customContrast = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Saturation")
                    from: 0.0; to: 1.8; stepSize: 0.01
                    value: prefs.customSaturation
                    valueText: Math.round(value * 100) + "%"
                    onMoved: { prefs.customSaturation = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Warmth")
                    from: -0.4; to: 0.4; stepSize: 0.01
                    value: -prefs.customWarmth
                    valueText: (value >= 0 ? "+" : "") + Math.round(value * 100)
                    // libplacebo: negative temperature = warmer
                    onMoved: { prefs.customWarmth = -value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Bloom")
                    from: 0.0; to: 1.5; stepSize: 0.05
                    value: prefs.customBloom
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customBloom = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Light rays")
                    from: 0.0; to: 1.5; stepSize: 0.05
                    value: prefs.customRays
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customRays = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Sharpen")
                    from: 0.0; to: 1.5; stepSize: 0.05
                    value: prefs.customSharpen
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customSharpen = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Clarity")
                    from: 0.0; to: 1.5; stepSize: 0.05
                    value: prefs.customClarity
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customClarity = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Vibrance")
                    from: 0.0; to: 1.2; stepSize: 0.05
                    value: prefs.customVibrance
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customVibrance = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Teal/Orange")
                    from: 0.0; to: 1.5; stepSize: 0.05
                    value: prefs.customSplit
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customSplit = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Vignette")
                    from: 0.0; to: 1.0; stepSize: 0.05
                    value: prefs.customVignette
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customVignette = value; quickWindow.applyColor(); }
                }
                SliderRow {
                    text: qsTr("Film grain")
                    from: 0.0; to: 1.0; stepSize: 0.05
                    value: prefs.customGrain
                    valueText: Math.round(value * 100)
                    onMoved: { prefs.customGrain = value; quickWindow.applyColor(); }
                }
            }

            // ----- Controller -----
            SectionTitle { text: qsTr("Controller") }
            Label {
                visible: Chiaki.controllers.length === 0
                text: qsTr("No controller connected · keyboard and mouse work too")
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.7)
            }
            Repeater {
                model: Chiaki.controllers
                delegate: Label {
                    required property var modelData
                    text: "🎮  " + quickWindow.controllerLine(modelData) + qsTr("  ·  connected")
                    font.pixelSize: 13
                    color: "white"
                }
            }
            Rectangle {
                visible: quickWindow.psControllerOnUsb
                Layout.fillWidth: true
                implicitHeight: usbTip.implicitHeight + 16
                radius: 8
                color: Qt.rgba(1.0, 0.65, 0.2, 0.14)
                border.color: Qt.rgba(1.0, 0.65, 0.2, 0.45)
                Label {
                    id: usbTip
                    anchors.fill: parent
                    anchors.margins: 8
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: "#ffd9a8"
                    text: qsTr("Inputs doubled or jumpy? Your PS5 may still be using this controller over Bluetooth. "
                             + "Fix once on the PS5: Settings → Accessories → Controller (General) → "
                             + "Communication Method → Use USB Cable.")
                }
            }

            // ----- AI Play -----
            SectionTitle { text: qsTr("AI Play") }
            Toggle {
                id: recToggle
                text: Chiaki.window.aiPlayRecording() ? qsTr("● Recording your gameplay") : qsTr("Record my gameplay for AI Play")
                checked: Chiaki.window.aiPlayRecording()
                onToggled: {
                    Chiaki.window.aiPlaySetRecording(checked);
                    aiStatus.refresh();
                    text = Chiaki.window.aiPlayRecording() ? qsTr("● Recording your gameplay") : qsTr("Record my gameplay for AI Play");
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    id: aiStatus
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.6)
                    function fmt(sec) { return Math.floor(sec / 60) + ":" + ("0" + Math.floor(sec % 60)).slice(-2); }
                    function refresh() {
                        const total = Chiaki.window.aiPlayTotalMinutes();
                        if (Chiaki.window.aiPlayRecording())
                            text = qsTr("This session %1 · %2 min recorded in total").arg(fmt(Chiaki.window.aiPlayFramesRecorded() / 15)).arg(total.toFixed(0));
                        else
                            text = total > 0 ? qsTr("%1 min recorded. Play more of one activity (like driving) for better AI.").arg(total.toFixed(0))
                                             : qsTr("Play normally while recording; the AI learns from you. Story mode only.");
                    }
                    Component.onCompleted: refresh()
                    Timer {
                        interval: 1000; repeat: true
                        running: quickWindow.expanded && quickWindow.visible
                        onTriggered: aiStatus.refresh()
                    }
                }
                Chip {
                    text: qsTr("Folder")
                    tip: qsTr("Open your recordings")
                    onClicked: Chiaki.window.aiPlayOpenFolder()
                }
            }

            // ----- Advanced (everything here is automatic by default) -----
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: 30
                radius: 8
                color: advHover.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: (prefs.advancedOpen ? "▾ " : "▸ ") + qsTr("Advanced")
                          + (prefs.advancedOpen ? "" : qsTr("  ·  all automatic"))
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font.pixelSize: 12
                }
                MouseArea {
                    id: advHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: prefs.advancedOpen = !prefs.advancedOpen
                }
            }
            ColumnLayout {
                visible: prefs.advancedOpen
                Layout.fillWidth: true
                spacing: 6
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
                    text: qsTr("Neural Engine upscaling (Apple ML)")
                    enabled: Chiaki.window.neuralUpscaleAvailable()
                    checked: Chiaki.settings.neuralUpscale && enabled
                    onToggled: Chiaki.settings.neuralUpscale = checked
                }
                Label {
                    id: neuralStatus
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.55)
                    text: Chiaki.window.neuralUpscaleStatus()
                    Timer {
                        interval: 1000; repeat: true
                        running: quickWindow.expanded && quickWindow.visible
                        onTriggered: neuralStatus.text = Chiaki.window.neuralUpscaleStatus()
                    }
                }
                Toggle {
                    text: qsTr("V-Sync (no tearing, slightly more latency)")
                    checked: Chiaki.settings.vSyncEnabled
                    onToggled: Chiaki.settings.vSyncEnabled = checked
                }
            }
        }
    }
}
