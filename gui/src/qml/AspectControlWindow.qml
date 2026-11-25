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
        property bool autoPerformance2: true
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
        property bool showStats: false
    }

    visible: shown
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    modality: Qt.NonModal
    width: Math.max(pill.implicitWidth, expanded ? 700 : 0)
    height: pill.implicitHeight + (expanded ? card.implicitHeight + 8 : 0)

    Material.theme: Material.Dark
    Material.accent: "#2f8cff"

    Component.onCompleted: {
        collapsed = prefs.collapsed;
        applyBitratePolicy();
        if (streaming) {
            applyColor();
            perf.start();
        }
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
        }
    }
    // Auto performance follows the stream session, not the panel's visibility
    // (it keeps working when the panel is hidden or the in-game menu is open).
    readonly property bool streaming: !!Chiaki.session
    onStreamingChanged: {
        if (streaming) {
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

    // ---------- live stats ----------
    property int fps: 0
    // Stats are sampled once a second into a plain string, so the panel redraws at most 1x/s
    // and only when stats are shown. Nothing here runs while stats are off.
    property string statsLine: ""
    Timer {
        interval: 1000; repeat: true; running: quickWindow.visible && prefs.showStats && !quickWindow.collapsed
        onTriggered: { quickWindow.fps = Chiaki.window.takeFrameCount(); quickWindow.statsLine = quickWindow.statsText(); }
    }
    function statsText() {
        // Honest number: frames that actually reached the screen this second (arrived minus dropped)
        let shown = Math.max(0, fps - Chiaki.window.droppedFrames);
        let parts = [shown + " fps shown"];
        if (Chiaki.session) {
            parts.push(Chiaki.session.measuredBitrate.toFixed(1) + " Mbps");
            let loss = isFinite(Chiaki.session.averagePacketLoss) ? Chiaki.session.averagePacketLoss * 100 : 0;
            parts.push(loss.toFixed(1) + "% loss");
        }
        if (Chiaki.window.droppedFrames > 0)
            parts.push(Chiaki.window.droppedFrames + " dropped");
        return parts.join(" · ");
    }

    // ---------- controllers ----------
    property int controllerTick: 0   // bumps every 2 s so battery / connection refresh
    // Controller info refreshes only while the quick menu is open, never in the background during play
    Timer { interval: 2000; repeat: true; running: quickWindow.visible && quickWindow.expanded; onTriggered: quickWindow.controllerTick++ }
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
    // e11: one look only, "Game". Colour work is done by libplacebo for free; the only shader
    // pass left is a single cheap shadow lift (no bloom/rays/blur passes), so it costs ~nothing.
    readonly property var lookPresets: [
        { name: qsTr("Game"), tip: "",
          b: 0.03, c: 1.10, s: 1.20, t: 0.03,  sh: 0.0, cl: 0.0, vb: 0.0, sp: 0.0, vg: 0.0, gr: 0.0, bl: 0, ry: 0, sd: 0.6 }
    ]
    readonly property int customLook: lookPresets.length
    readonly property int effectivePreset: 0

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
        return 1; // smoothness first: auto starts at "Balanced" and drops to "Fast" if frames drop
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

    // ---------- Auto performance ----------
    // Smart and live: V-Sync + Neural Engine on, then quality goes UP after 20 clean seconds and
    // DOWN after 3 bad seconds. A level that drops frames right after a step up is remembered
    // as this Mac's ceiling for the session, so it settles instead of bouncing.
    QtObject {
        id: perf
        property int ceiling: 4          // highest level allowed this session (learned)
        property int badSeconds: 0
        property int goodSeconds: 0
        property int sinceStepUp: 999    // seconds since the last step up
        property bool neuralTried: false
        property int neuralOffTest: 0    // >0: seconds left to see if turning the Neural Engine off helped
        property int cleanStreak: 0      // seconds without drops, to forgive a learned ceiling
        property string status: ""
        function start() {
            ceiling = 4;
            badSeconds = 0;
            goodSeconds = 0;
            sinceStepUp = 999;
            neuralTried = false;
            neuralOffTest = 0;
            cleanStreak = 0;
            if (prefs.autoPerformance2) {
                Chiaki.settings.vSyncEnabled = true;
                if (Chiaki.window.neuralUpscaleAvailable())
                    Chiaki.settings.neuralUpscale = true;
                quickWindow.setLevel(quickWindow.chipMaxLevel());
                status = qsTr("Auto: tuning for this Mac…");
            }
            perfTimer.start();
        }
        function stop() { perfTimer.stop(); }
    }
    Timer {
        id: perfTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (!prefs.autoPerformance2) {
                perf.status = "";
                return;
            }
            perf.sinceStepUp++;
            let dropped = Chiaki.window.droppedFrames;
            if (dropped >= 3) {
                perf.badSeconds++;
                perf.goodSeconds = 0;
                perf.cleanStreak = 0;
            } else {
                perf.goodSeconds++;
                perf.badSeconds = 0;
                perf.cleanStreak++;
            }
            // A Wi-Fi blip shouldn't cap quality forever: after 2 clean minutes, allow one level more
            if (perf.cleanStreak >= 120 && perf.ceiling < 4) {
                perf.ceiling++;
                perf.cleanStreak = 0;
            }
            // Neural Engine experiment: if it's still dropping without it, it wasn't the cause
            if (perf.neuralOffTest > 0) {
                perf.neuralOffTest--;
                if (dropped >= 3 && Chiaki.window.neuralUpscaleAvailable()) {
                    Chiaki.settings.neuralUpscale = true;
                    perf.neuralOffTest = 0;
                } else if (perf.neuralOffTest === 0 && perf.goodSeconds > 0) {
                    perf.status = qsTr("Auto: Fast · smooth without Neural Engine");
                }
            }
            let lvl = quickWindow.currentLevel();
            let name = quickWindow.qualityNames[lvl];
            // Step down: quicker right after a step up (that level is too much for this Mac)
            let limit = perf.sinceStepUp <= 20 ? 2 : 3;
            if (perf.badSeconds >= limit) {
                perf.badSeconds = 0;
                if (lvl > 0) {
                    if (perf.sinceStepUp <= 20)
                        perf.ceiling = lvl - 1;
                    quickWindow.setLevel(lvl - 1);
                    perf.status = qsTr("Auto: %1 (lowered to stay smooth)").arg(quickWindow.qualityNames[lvl - 1]);
                } else if (Chiaki.settings.neuralUpscale && !perf.neuralTried) {
                    // Already at Fast and still dropping: try without the Neural Engine once
                    perf.neuralTried = true;
                    perf.neuralOffTest = 8;
                    Chiaki.settings.neuralUpscale = false;
                    perf.status = qsTr("Auto: Fast, Neural Engine off (network or Mac busy)");
                } else {
                    perf.status = qsTr("Auto: Fast (frames are dropping: check Wi-Fi)");
                }
                return;
            }
            // Step up after a long clean stretch, never past what failed before
            if (perf.goodSeconds >= 20 && lvl < perf.ceiling) {
                perf.goodSeconds = 0;
                perf.sinceStepUp = 0;
                quickWindow.setLevel(lvl + 1);
                perf.status = qsTr("Auto: trying %1…").arg(quickWindow.qualityNames[lvl + 1]);
                return;
            }
            if (perf.goodSeconds >= 5 && perf.sinceStepUp > 20)
                perf.status = qsTr("Auto: %1 · smooth").arg(name);
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

            Label {
                visible: prefs.showStats
                text: quickWindow.statsLine
                color: quickWindow.fps >= 55 || quickWindow.fps === 0 ? "#bfeccb" : "#ffd28a"
                font.pixelSize: 12
                font.family: "Menlo"
                leftPadding: 4
                rightPadding: 6
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
                id: shotChip
                // e11: screenshot. ✓ = saved (click again to open the folder), ⚠ = failed.
                property string flash: ""
                property string message: ""
                visible: !quickWindow.collapsed
                text: flash !== "" ? flash : "📷"
                tip: message !== "" ? message : qsTr("Screenshot (⌘P). Saved to Pictures › e11 Screenshots")
                onClicked: {
                    if (flash === "✓")
                        Chiaki.window.openScreenshotFolder()
                    else
                        Chiaki.window.takeScreenshot()
                }
                Timer {
                    id: shotFlashTimer
                    interval: 3000
                    onTriggered: { shotChip.flash = ""; shotChip.message = "" }
                }
                Connections {
                    target: Chiaki.window
                    function onScreenshotSaved(path) {
                        shotChip.flash = "✓"
                        shotChip.message = qsTr("Saved: %1").arg(path)
                        shotFlashTimer.restart()
                    }
                    function onScreenshotFailed(reason) {
                        shotChip.flash = "⚠"
                        shotChip.message = reason
                        shotFlashTimer.restart()
                    }
                }
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
        width: 700
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 18
                ColumnLayout {
                    Layout.preferredWidth: 330
                    Layout.maximumWidth: 330
                    Layout.alignment: Qt.AlignTop
                    spacing: 6
                    // ----- Looks -----
                    SectionTitle { text: qsTr("Look") }

                    Label {
                        text: qsTr("Game  ✓  (tuned for Mac screens)")
                        color: "white"
                        font.pixelSize: 13
                    }
                    Flow {
                        visible: false
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
                        visible: false
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
                }
                Rectangle { Layout.fillHeight: true; width: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 6
                    // ----- Display -----
                    SectionTitle { text: qsTr("Display") }
                    Toggle {
                        text: qsTr("Stats on panel (FPS, bitrate, loss)")
                        checked: prefs.showStats
                        onToggled: prefs.showStats = checked
                    }
                    Toggle {
                        text: qsTr("Detailed stats overlay")
                        checked: Chiaki.settings.showStreamStats
                        onToggled: Chiaki.settings.showStreamStats = checked
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
                            checked: prefs.autoPerformance2
                            onToggled: {
                                prefs.autoPerformance2 = checked;
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
                                        prefs.autoPerformance2 = false;
                                        quickWindow.setLevel(index);
                                        Chiaki.settings.videoPreset = index;
                                    }
                                }
                            }
                        }
                        Label {
                            visible: prefs.autoPerformance2 && perf.status !== ""
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
    }
}
