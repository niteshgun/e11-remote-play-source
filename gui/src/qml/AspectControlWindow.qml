// e11: floating, draggable quick menu shown while streaming.
// Picture (Fit/Stretch), stream bitrate (auto/manual), performance (auto quality for the
// Mac's chip, render quality, V-Sync) and colour filters for the Retina display.
import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Window

import org.streetpea.chiaking

Window {
    id: quickWindow

    property bool shown: false
    property var hostWindow: null
    property bool collapsed: false
    property bool expanded: false
    // refresh the speaker list each time the menu opens (AirPods may have just connected)
    onExpandedChanged: if (expanded) Chiaki.settings.refreshAudioDevices()

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
        // e11 Enhance: 0 Off, 1 Auto (default), 2 Max
        property int enhanceMode: 1
        // e11 Sound: true = this computer + TV (default), false = TV only (computer muted)
        property bool soundOnComputer: true
        property bool showAdvancedVideo: false
        // Look: -1 = follow "Retina Vivid Colors" setting; otherwise index into lookPresets,
        // lookPresets.length = Custom
        property int colorPreset: -1
        // e11 Picture "Off": no colour grade, no look, no shadow lift (the picture exactly as the PS5 sends it)
        property bool pictureOff: false
        // e11 Mac resolution while playing: "" = keep the System Settings resolution
        property string macResolution: ""
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
        property int menuTab: 1
        property bool gameLookDefaulted: false
        property bool showStats: false
    }

    visible: shown
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    modality: Qt.NonModal
    width: Math.max(pill.implicitWidth, (expanded && !confirmLeave) ? 760 : 0)
    height: pill.implicitHeight + (confirmLeave ? leaveCard.implicitHeight + 8 : (expanded ? card.implicitHeight + 8 : 0))

    Material.theme: Material.Dark
    Material.accent: "#5aa9ff"

    Component.onCompleted: {
        // e11: Game is the default colour grade (once; the user's later choice is kept)
        if (!prefs.gameLookDefaulted) {
            prefs.gameLookDefaulted = true;
            Chiaki.window.setLookLut("");
        }
        collapsed = prefs.collapsed;
        applyBitratePolicy();
        if (streaming) {
            applyColor();
            Chiaki.window.setComputerSoundMuted(!prefs.soundOnComputer);
            if (Chiaki.window.aiPlayRecording())
                Chiaki.window.aiPlaySetRecording(false);
            enh.start();
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
        rightX = x + width;
        keepOnScreen();
    }

    // The bar grows and shrinks (Show/Hide, menu open). Keep its right edge where it was,
    // so it grows to the left, and never let any part go past the screen edge.
    property real rightX: -1
    property bool adjusting: false
    function keepOnScreen() {
        if (!visible)
            return;
        if (rightX < 0)
            rightX = x + width;
        let nx = rightX - width;
        let ny = y;
        const s = quickWindow.screen;
        if (s) {
            nx = Math.max(s.virtualX + 8, Math.min(nx, s.virtualX + s.width - width - 8));
            ny = Math.max(s.virtualY + 8, Math.min(ny, s.virtualY + s.height - height - 8));
        }
        adjusting = true;
        if (nx !== x) x = nx;
        if (ny !== y) y = ny;
        adjusting = false;
    }
    onWidthChanged: keepOnScreen()
    onHeightChanged: keepOnScreen()

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
            applyMacResolution();
            applyColor();
            Chiaki.window.setComputerSoundMuted(!prefs.soundOnComputer);
            if (Chiaki.window.aiPlayRecording())
                Chiaki.window.aiPlaySetRecording(false);
            enh.start();
            perf.start();
        } else {
            perf.stop();
            enh.stop();
            Chiaki.window.restoreDisplayMode(); // back to the System Settings resolution
        }
    }

    // ---------- e11 Mac resolution ----------
    property var macModes: []
    function refreshMacModes() { macModes = Chiaki.window.displayModes(); }
    function applyMacResolution() {
        const wasFull = Chiaki.window.visibility === Window.FullScreen;
        Chiaki.window.setDisplayMode(prefs.macResolution);
        refreshMacModes();
        // a resolution change can drop the window out of full screen: put it back
        if (wasFull)
            refullTimer.start();
        Chiaki.window.updateEnhanceTarget();
    }
    Timer {
        id: refullTimer
        interval: 700
        onTriggered: {
            if (Chiaki.window.visibility !== Window.FullScreen)
                Chiaki.window.showFullScreen();
            Chiaki.window.updateEnhanceTarget();
        }
    }
    // The system drag (startSystemMove) owns the mouse, so save on every position change
    onXChanged: if (visible) { prefs.posX = x; if (!adjusting) rightX = x + width; }
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
        onTriggered: { quickWindow.fps = Chiaki.window.takeFrameCount(); quickWindow.statsLine = quickWindow.statsText(); quickWindow.updateStatSlots(); }
    }
    // Fixed slots for the bar: each number has its own fixed-width cell, so the bar never changes size
    property string sFps: "–"
    property string sRes: "–"
    property string sMbps: "–"
    property string sLoss: "–"
    property int sDropped: 0
    property int sShown: 0
    function updateStatSlots() {
        let pm = Chiaki.window.proMotionActive();
        let dropped = Math.max(0, Chiaki.window.droppedFrames - Chiaki.window.proMotionSurplus());
        let shown = Math.max(0, Math.min(pm ? fps * 2 : fps, Chiaki.window.displayHz()) - dropped);
        sShown = shown;
        let r = Chiaki.window.streamResolution();
        sRes = r !== "" ? r : "–";
        sFps = String(shown);
        sDropped = dropped;
        if (Chiaki.session) {
            sMbps = Chiaki.session.measuredBitrate.toFixed(1);
            let loss = isFinite(Chiaki.session.averagePacketLoss) ? Chiaki.session.averagePacketLoss * 100 : 0;
            sLoss = loss.toFixed(1);
        }
    }
    function statsText() {
        // Honest number: frames that actually reached the screen this second (arrived minus dropped).
        // e11 Pro Motion doubles the frames; the ones a 60 Hz screen can't show aren't "drops".
        let pm = Chiaki.window.proMotionActive();
        let dropped = Math.max(0, Chiaki.window.droppedFrames - Chiaki.window.proMotionSurplus());
        let shown = Math.max(0, Math.min(pm ? fps * 2 : fps, Chiaki.window.displayHz()) - dropped);
        let parts = [shown + " fps shown"];
        if (Chiaki.session) {
            parts.push(Chiaki.session.measuredBitrate.toFixed(1) + " Mbps");
            let loss = isFinite(Chiaki.session.averagePacketLoss) ? Chiaki.session.averagePacketLoss * 100 : 0;
            parts.push(loss.toFixed(1) + "% loss");
        }
        if (pm)
            parts.push("Pro Motion");
        if (dropped > 0)
            parts.push(dropped + " dropped");
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
            Chiaki.settings.bitrateLocalPS5 = 30000; // ceiling at home; the PS5 adapts down by itself from loss reports
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
    readonly property var neutralLook: ({ b: 0.0, c: 1.0, s: 1.0, t: 0.0, sh: 0.0, cl: 0.0, vb: 0.0, sp: 0.0, vg: 0.0, gr: 0.0, bl: 0, ry: 0, sd: 0.0 })
    function applyColor() {
        if (prefs.pictureOff) {
            applyLook(neutralLook);
            return;
        }
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
    // 0 Fast, 1 Default, 2 High Quality, 3 e11 FSR (HQ + AMD FSR, the default), 4 HQ + neural (FSRCNNX) upscaling
    readonly property var qualityNames: [qsTr("Fast"), qsTr("Balanced"), qsTr("High"), qsTr("e11 FSR"), qsTr("Ultra")]
    readonly property var qualityPresets: [ChiakiWindow.VideoPreset.Fast, ChiakiWindow.VideoPreset.Default,
        ChiakiWindow.VideoPreset.HighQuality, ChiakiWindow.VideoPreset.HighQualitySpatial,
        ChiakiWindow.VideoPreset.HighQualityAdvancedSpatial]
    readonly property string chip: Chiaki.window.chipName()

    // Best level this Mac should handle comfortably at 1080p60
    function chipMaxLevel() {
        return 3; // e11 FSR by default (light AMD FSR sharpening); Auto still steps down the moment frames drop
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
    // ---------- e11 Enhance ----------
    // One button for a sharper, cleaner picture. Tiers (cheapest first):
    //   0 Off, 1 Clean (Apple temporal noise filter: less blockiness),
    //   2 Sharp (MetalFX spatial upscale to the screen's real size), 3 Sharp + Clean.
    // Auto: starts at Sharp, steps DOWN after 2 bad seconds (1 right after a step up, and that
    // level becomes this session's ceiling), steps UP after 20 clean seconds, forgives the ceiling
    // after 2 clean minutes. On battery / Low Power Mode it stays at Sharp or below; when the Mac
    // gets hot it backs off at once. Max = the highest tier this Mac allows, no stepping.
    // MetalFX temporal / frame interpolation / denoised scaler need the game's depth and motion
    // vectors, which a video stream doesn't have, so they are not used.
    QtObject {
        id: enh
        readonly property var names: [qsTr("Off"), qsTr("Clean"), qsTr("Sharp"), qsTr("Sharp + Clean")]
        readonly property var modeNames: [qsTr("Off"), qsTr("Auto"), qsTr("Max")]
        property int tier: 0
        property int ceiling: 3
        property int bad: 0
        property int good: 0
        property int cleanStreak: 0
        property int sinceUp: 999
        property int metalWait: 0
        property bool proMotionDropped: false // Auto turned Pro Motion off this session to stay smooth
        property string status: ""
        // Pro Motion (60 -> 120 fps) only helps on a 100 Hz+ screen (ProMotion MacBook Pro, 120 Hz monitor)
        function proMotionOk() {
            return Chiaki.window.proMotionAvailable() && Chiaki.window.screenRefreshHz() >= 100;
        }
        function apply(t) {
            tier = t;
            const mfx = t >= 2 && Chiaki.window.metalFXAvailable();
            const clean = (t === 1 || t === 3) && Chiaki.window.cleanPictureAvailable();
            if (mfx)
                Chiaki.settings.neuralUpscale = false; // one upscaler at a time
            if (Chiaki.settings.metalFXUpscale !== mfx)
                Chiaki.settings.metalFXUpscale = mfx;
            if (Chiaki.settings.cleanPicture !== clean)
                Chiaki.settings.cleanPicture = clean;
            if (clean)
                Chiaki.settings.cleanPictureStrength = t === 3 ? 0.5 : 0.25;
            metalWait = 0;
            bad = 0;
            good = 0;
            perf.badSeconds = 0; // don't let Smart Auto also step down for the same drops
        }
        function cap() {
            let c = ceiling;
            // Max: only back off when the Mac is critically hot
            if (prefs.enhanceMode === 2)
                return Chiaki.window.thermalLevel() >= 3 ? 0 : 3;
            if (Chiaki.window.onBatteryPower() || Chiaki.window.lowPowerMode())
                c = Math.min(c, 2);
            const heat = Chiaki.window.thermalLevel();
            if (heat >= 3)
                c = Math.min(c, 0);
            else if (heat >= 2)
                c = Math.min(c, 1);
            return c;
        }
        function detail() {
            if (tier >= 2) // Sharp tiers use MetalFX: show it working, or why not
                return " · " + Chiaki.window.metalFXStatus(); // "MetalFX on: 1080p → 1440p" or why it is off
            return "";
        }
        property int slowSeconds: 0
        function start() {
            ceiling = 3;
            cleanStreak = 0;
            sinceUp = 999;
            slowSeconds = 0;
            // Zero-lag rule: Pro Motion delays every real frame by half a frame and its extra
            // frames can't be shown below 100 Hz, so it is always off on such screens.
            if (Chiaki.settings.proMotion && Chiaki.window.screenRefreshHz() < 100)
                Chiaki.settings.proMotion = false;
            Chiaki.window.updateEnhanceTarget();
            proMotionDropped = false;
            if (prefs.enhanceMode === 0) {
                status = "";
                enhTimer.stop();
                return;
            }
            apply(prefs.enhanceMode === 2 ? cap() : Math.min(2, cap()));
            // Auto and Max use Pro Motion too, on screens that can show 120 fps
            if (proMotionOk() && !Chiaki.settings.proMotion)
                Chiaki.settings.proMotion = true;
            status = qsTr("%1: %2").arg(modeNames[prefs.enhanceMode]).arg(names[tier]);
            enhTimer.start();
        }
        function stop() { enhTimer.stop(); }
        function setMode(m) {
            prefs.enhanceMode = m;
            if (m === 0) {
                apply(0);
                if (Chiaki.settings.proMotion)
                    Chiaki.settings.proMotion = false; // Off = the picture exactly as the PS5 sends it
            }
            if (quickWindow.streaming)
                start();
        }
    }
    Timer {
        id: enhTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (prefs.enhanceMode === 0)
                return;
            Chiaki.window.updateEnhanceTarget();
            // Pro Motion's extra frames can't be shown on a 60 Hz screen: no point paying for them
            if (Chiaki.settings.proMotion && Chiaki.window.proMotionSurplus() > 0)
                Chiaki.settings.proMotion = false;
            enh.sinceUp++;
            const dropped = Math.max(0, Chiaki.window.droppedFrames - Chiaki.window.proMotionSurplus());
            // Only blame the Mac's picture work for dropped frames when the network is clean and the
            // upscaler is actually taking time: Wi-Fi loss (Bluetooth sharing the radio etc.) drops
            // frames too, and turning MetalFX off doesn't fix that.
            const netLoss = Chiaki.session && isFinite(Chiaki.session.averagePacketLoss) ? Chiaki.session.averagePacketLoss : 0;
            const macsFault = netLoss < 0.002 && (enh.tier < 2 || Chiaki.window.metalFXP95Ms() > 5.0);
            if (dropped >= 3 && macsFault) {
                enh.bad++;
                enh.good = 0;
                enh.cleanStreak = 0;
            } else if (dropped < 3) {
                enh.good++;
                enh.bad = 0;
                enh.cleanStreak++;
            }
            if (enh.cleanStreak >= 120 && enh.ceiling < 3) {
                enh.ceiling++;
                enh.cleanStreak = 0;
            }
            // MetalFX not running (screen not bigger than the stream, or it switched itself off)
            if (enh.tier >= 2) {
                enh.metalWait = Chiaki.window.metalFXActive() ? 0 : enh.metalWait + 1;
                if (enh.metalWait >= 6) {
                    enh.ceiling = Math.min(enh.ceiling, 1);
                    enh.apply(Math.min(enh.tier === 3 ? 1 : 0, enh.cap()));
                    enh.status = qsTr("%1: %2 · %3")
                        .arg(enh.modeNames[prefs.enhanceMode]).arg(enh.names[enh.tier]).arg(Chiaki.window.metalFXStatus());
                    return;
                }
            }
            // Lag budget (Auto only; Max means max): the upscaler may take at most ~10 ms (95th
            // percentile) of a 16.7 ms frame before it starts costing frames
            if (prefs.enhanceMode === 1 && enh.tier >= 2 && Chiaki.window.metalFXP95Ms() > 10.0) {
                if (++enh.slowSeconds >= 3) {
                    enh.slowSeconds = 0;
                    enh.ceiling = Math.min(enh.ceiling, enh.tier - 1);
                    enh.sinceUp = 999;
                    enh.apply(enh.tier - 1);
                    enh.status = qsTr("%1: %2 (kept lag-free)").arg(enh.modeNames[prefs.enhanceMode]).arg(enh.names[enh.tier]);
                    return;
                }
            } else {
                enh.slowSeconds = 0;
            }
            const c = enh.cap();
            if (enh.tier > c) {
                enh.apply(c);
                enh.status = qsTr("%1: %2 (saving power / cooling down)").arg(enh.modeNames[prefs.enhanceMode]).arg(enh.names[enh.tier]);
                return;
            }
            if (prefs.enhanceMode === 2) {
                if (enh.tier < c && enh.good >= 5)
                    enh.apply(c);
                enh.status = qsTr("Max: %1%2").arg(enh.names[enh.tier]).arg(enh.detail());
                return;
            }
            const limit = enh.sinceUp <= 20 ? 1 : 2;
            // Dropping frames: Pro Motion is the first thing to go (it costs the most), then the picture tier
            if (enh.bad >= limit && Chiaki.settings.proMotion) {
                Chiaki.settings.proMotion = false;
                enh.proMotionDropped = true;
                enh.bad = 0;
                enh.status = qsTr("Auto: Pro Motion off to stay smooth");
                return;
            }
            if (enh.bad >= limit && enh.tier > 0) {
                if (enh.sinceUp <= 20)
                    enh.ceiling = enh.tier - 1; // only the level that just failed is blamed
                enh.sinceUp = 999;
                enh.apply(enh.tier - 1);
                enh.status = qsTr("Auto: %1 (lowered to stay smooth)").arg(enh.names[enh.tier]);
                return;
            }
            if (enh.good >= 20 && enh.tier < c) {
                enh.sinceUp = 0;
                enh.apply(enh.tier + 1);
                enh.status = qsTr("Auto: trying %1…").arg(enh.names[enh.tier]);
                return;
            }
            if (enh.good >= 3)
                enh.status = qsTr("Auto: %1 · smooth%2").arg(enh.names[enh.tier]).arg(enh.detail());
        }
    }

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
                if (Chiaki.window.neuralUpscaleAvailable() && !Chiaki.settings.metalFXUpscale && prefs.enhanceMode === 0)
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
            let dropped = Math.max(0, Chiaki.window.droppedFrames - Chiaki.window.proMotionSurplus());
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
                if (dropped >= 3 && Chiaki.window.neuralUpscaleAvailable() && !Chiaki.settings.metalFXUpscale && prefs.enhanceMode === 0) {
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
        property color tint: "#5aa9ff"
        property bool bold: false
        signal clicked()
        implicitHeight: 32
        implicitWidth: chipLabel.implicitWidth + 24
        radius: 10
        // Selected = coloured outline and text only, never a filled background
        color: chipHover.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
        border.width: 1.5
        border.color: selected ? tint : "#1e2530"
        Label {
            id: chipLabel
            anchors.centerIn: parent
            text: chipRoot.text
            font.pixelSize: 13
            font.bold: chipRoot.selected || chipRoot.bold
            color: chipRoot.selected ? chipRoot.tint : "#b3bdc9"
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
        color: "#8c97a6"
        Layout.topMargin: 8
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

    // Top bar: fixed size so it never moves when the numbers change
    Rectangle {
        id: pill
        anchors.left: parent.left
        width: implicitWidth
        implicitWidth: row.implicitWidth + 20
        implicitHeight: 50
        radius: 14
        color: "#eb0b0e13"
        border.color: "#1e2530"
        border.width: 1

        RowLayout {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 6

            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 32
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: 3
                    Repeater {
                        model: 6
                        Rectangle { width: 3; height: 3; radius: 1.5; color: "#8c97a6" }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    onPressed: quickWindow.startSystemMove()
                }
            }

            Rectangle {
                visible: prefs.showStats
                Layout.preferredHeight: 34
                Layout.preferredWidth: statsRow.implicitWidth
                radius: 9
                color: "#07090c"
                border.color: "#1e2530"
                Row {
                    id: statsRow
                    anchors.verticalCenter: parent.verticalCenter
                    component StatCell: Label {
                        width: 92
                        height: 34
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 10
                        font.pixelSize: 12
                        font.family: "Menlo"
                        color: "#eef2f7"
                        elide: Text.ElideNone
                    }
                    StatCell { width: 70; text: quickWindow.sRes; color: "#eef2f7" }
                    Rectangle { width: 1; height: 34; color: "#1e2530" }
                    StatCell { width: 80; text: quickWindow.sFps + " fps"; color: quickWindow.sShown >= 55 || quickWindow.fps === 0 ? "#5fd3a6" : "#f2c94c" }
                    Rectangle { width: 1; height: 34; color: "#1e2530" }
                    StatCell { width: 104; text: quickWindow.sMbps + " Mbps" }
                    Rectangle { width: 1; height: 34; color: "#1e2530" }
                    StatCell { width: 104; text: quickWindow.sLoss + "% loss" }
                    Rectangle { width: 1; height: 34; color: "#1e2530" }
                    StatCell { width: 112; text: quickWindow.sDropped + " dropped"; color: quickWindow.sDropped > 0 ? "#f2c94c" : "#8c97a6" }
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
                // Graphics (MetalFX / Neural Engine): click to cycle Off -> Auto -> Max
                visible: !quickWindow.collapsed && Qt.platform.os === "osx"
                Layout.preferredWidth: 128
                text: qsTr("Graphics: %1").arg(enh.modeNames[prefs.enhanceMode])
                tint: "#ff7ab8"
                selected: true
                tip: qsTr("Sharper picture with MetalFX. Click to switch Off / Auto / Max")
                onClicked: enh.setMode((prefs.enhanceMode + 1) % 3)
            }
            Label {
                visible: !quickWindow.collapsed
                Layout.preferredWidth: 150
                elide: Text.ElideRight
                font.pixelSize: 12
                color: "#8c97a6"
                text: Chiaki.controllers.length ? quickWindow.controllerLine(Chiaki.controllers[0]) : qsTr("No controller")
                leftPadding: 4
            }
            Chip {
                id: shotChip
                // screenshot: "Saved" (click again to open the folder) or "Failed"
                property string flash: ""
                property string message: ""
                visible: !quickWindow.collapsed
                Layout.preferredWidth: 96
                text: flash === "ok" ? qsTr("Saved") : flash === "err" ? qsTr("Failed") : qsTr("Screenshot")
                selected: flash !== ""
                tint: flash === "err" ? "#f2c94c" : "#5fd3a6"
                tip: message !== "" ? message : qsTr("Screenshot (⌘P). Saved to Pictures › e11 Screenshots")
                onClicked: {
                    if (flash === "ok")
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
                        shotChip.flash = "ok"
                        shotChip.message = qsTr("Saved: %1").arg(path)
                        shotFlashTimer.restart()
                    }
                    function onScreenshotFailed(reason) {
                        shotChip.flash = "err"
                        shotChip.message = reason
                        shotFlashTimer.restart()
                    }
                }
            }
            Chip {
                visible: !quickWindow.collapsed
                text: qsTr("Home")
                tint: "#f2c94c"
                selected: true
                tip: qsTr("Stop streaming and go back to Home")
                onClicked: { quickWindow.expanded = false; quickWindow.confirmLeave = !quickWindow.confirmLeave; }
            }
            Chip {
                visible: !quickWindow.collapsed
                text: qsTr("Settings")
                tip: qsTr("Picture, graphics, sound, stream")
                selected: quickWindow.expanded
                onClicked: { quickWindow.confirmLeave = false; quickWindow.expanded = !quickWindow.expanded; }
            }
            Chip {
                // the full in-game menu (same as the controller's Create + Options)
                visible: !quickWindow.collapsed
                text: qsTr("More")
                tip: qsTr("All in-game options")
                onClicked: { quickWindow.confirmLeave = false; quickWindow.expanded = false; Chiaki.window.menuRequested(); }
            }
            Chip {
                Layout.preferredWidth: 64
                text: quickWindow.collapsed ? qsTr("Show") : qsTr("Hide")
                tip: quickWindow.collapsed ? qsTr("Show the bar") : qsTr("Shrink the bar")
                onClicked: { quickWindow.confirmLeave = false; quickWindow.collapsed = !quickWindow.collapsed; }
            }
        }
    }

    // Expanded quick menu: tabs on the left, one page at a time (DeskCleaner colours)
    readonly property var tabDefs: [
        { name: qsTr("Picture"), color: "#5aa9ff" },
        { name: qsTr("Graphics"), color: "#ff7ab8" },
        { name: qsTr("Sound"), color: "#f2c94c" },
        { name: qsTr("Stream"), color: "#b79bff" },
        { name: qsTr("Controller"), color: "#5fd3a6" },
        { name: qsTr("Display"), color: "#8c97a6" }
    ]
    property bool confirmLeave: false
    Rectangle {
        id: leaveCard
        visible: quickWindow.confirmLeave
        anchors.top: pill.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        width: pill.width
        implicitHeight: leaveCol.implicitHeight + 40
        height: implicitHeight
        radius: 18
        color: "#f50b0e13"
        border.color: "#1e2530"
        ColumnLayout {
            id: leaveCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 10
            Label { text: qsTr("Back to main menu?"); color: "#eef2f7"; font.pixelSize: 20; font.weight: Font.Black }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: "#8c97a6"
                font.pixelSize: 13
                text: qsTr("The stream stops. Your game keeps running on the PS5, so you can jump straight back in.")
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Chip { text: qsTr("Keep playing"); implicitHeight: 36; onClicked: quickWindow.confirmLeave = false }
                Chip { text: qsTr("Home"); tint: "#f2c94c"; selected: true; implicitHeight: 36
                        onClicked: { quickWindow.confirmLeave = false; Chiaki.stopSession(false); } }
            }
        }
    }

    Rectangle {
        id: card
        visible: quickWindow.expanded && !quickWindow.confirmLeave
        anchors.top: pill.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        width: Math.max(pill.width, 760)
        implicitHeight: 470
        height: implicitHeight
        radius: 18
        color: "#f50b0e13"
        border.color: "#1e2530"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0
            ColumnLayout {
                Layout.preferredWidth: 170
                Layout.maximumWidth: 170
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.margins: 12
                spacing: 4
                Label {
                    text: qsTr("LIVE · %1 Mbps · %2").arg(Chiaki.session ? Chiaki.session.measuredBitrate.toFixed(1) : "–").arg(quickWindow.chip.toUpperCase())
                    color: "#8c97a6"
                    font.pixelSize: 10
                    font.family: "Menlo"
                    Layout.leftMargin: 8
                    Layout.bottomMargin: 8
                    Layout.maximumWidth: 160
                    elide: Text.ElideRight
                }
                Repeater {
                    model: quickWindow.tabDefs
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: prefs.menuTab === index
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 10
                        color: "transparent"
                        border.width: 1.5
                        border.color: on ? modelData.color : (tabHover.containsMouse ? "#1e2530" : "transparent")
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 10
                            Rectangle { width: 11; height: 11; radius: 5.5; color: "transparent"; border.width: 2; border.color: modelData.color }
                            Label { text: modelData.name; color: on ? "#eef2f7" : "#b3bdc9"; font.pixelSize: 14; font.weight: on ? Font.DemiBold : Font.Normal; Layout.fillWidth: true }
                        }
                        MouseArea { id: tabHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: prefs.menuTab = index }
                    }
                }
                Item { Layout.fillHeight: true }
            }
            Rectangle { Layout.fillHeight: true; width: 1; color: "#1e2530" }
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 18
                currentIndex: prefs.menuTab
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: pg0.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: pg0
                    width: parent.width - 12
                    spacing: 8
                    Label { text: qsTr("Picture"); color: "#5aa9ff"; font.pixelSize: 20; font.weight: Font.Black; Layout.bottomMargin: 4 }

                    // e11 colour grade: Game (tuned for Mac screens, the default), built-in looks or your own .cube file
                    Label {
                        text: qsTr("Colour grade")
                        color: "#8c97a6"
                        font.pixelSize: 12
                    }
                    Flow {
                        id: lutFlow
                        Layout.fillWidth: true
                        spacing: 4
                        property string current: Chiaki.window.lookLut()
                        property string error: ""
                        Connections {
                            target: Chiaki.window
                            function onLookLutChanged() { lutFlow.current = Chiaki.window.lookLut() }
                        }
                        Chip {
                            text: qsTr("Off")
                            selected: prefs.pictureOff
                            onClicked: { prefs.pictureOff = true; Chiaki.window.setLookLut(""); quickWindow.applyColor(); }
                        }
                        Chip {
                            text: qsTr("Game")
                            selected: !prefs.pictureOff && lutFlow.current === ""
                            onClicked: { prefs.pictureOff = false; Chiaki.window.setLookLut(""); quickWindow.applyColor(); }
                        }
                        Repeater {
                            model: Chiaki.window.builtinLuts()
                            delegate: Chip {
                                required property var modelData
                                text: modelData.name
                                selected: !prefs.pictureOff && lutFlow.current === modelData.id
                                onClicked: { prefs.pictureOff = false; quickWindow.applyColor(); Chiaki.window.setLookLut(modelData.id) }
                            }
                        }
                        Chip {
                            readonly property bool custom: lutFlow.current !== "" && !lutFlow.current.startsWith("builtin:")
                            text: custom ? "🎨 " + lutFlow.current.split("/").pop() : qsTr("Import .cube…")
                            selected: !prefs.pictureOff && custom
                            onClicked: lutDialog.open()
                        }
                    }
                    Label {
                        visible: lutFlow.error !== ""
                        text: lutFlow.error
                        color: "#ffd28a"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    FileDialog {
                        id: lutDialog
                        title: qsTr("Choose a colour grade (.cube LUT)")
                        nameFilters: [qsTr("3D LUT (*.cube)")]
                        onAccepted: {
                            lutFlow.error = Chiaki.window.setLookLut(selectedFile.toString())
                                ? "" : qsTr("That file isn't a valid .cube LUT")
                            if (lutFlow.error === "") { prefs.pictureOff = false; quickWindow.applyColor(); }
                        }
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

                }
            }
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: pg1.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: pg1
                    width: parent.width - 12
                    spacing: 8
                    Label { text: qsTr("Graphics"); color: "#ff7ab8"; font.pixelSize: 20; font.weight: Font.Black; Layout.bottomMargin: 4 }
                    Flow {
                        visible: Qt.platform.os === "osx"
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: enh.modeNames
                            delegate: Chip {
                                required property int index
                                required property string modelData
                                text: modelData
                                selected: prefs.enhanceMode === index
                                onClicked: enh.setMode(index)
                            }
                        }
                    }
                    Label {
                        visible: Qt.platform.os === "osx"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.6)
                        text: prefs.enhanceMode === 0 ? qsTr("Off: the stream as the PS5 sends it.")
                            : (enh.status !== "" ? enh.status
                               : (prefs.enhanceMode === 1 ? qsTr("Auto: picks the best picture this Mac can hold, live.")
                                                          : qsTr("Max: always the strongest this Mac allows.")))
                    }
                    Label {
                        text: prefs.showAdvancedVideo ? qsTr("▾ Advanced picture options") : qsTr("▸ Advanced picture options")
                        visible: Qt.platform.os === "osx"
                        font.pixelSize: 11
                        color: Material.accent
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: prefs.showAdvancedVideo = !prefs.showAdvancedVideo
                        }
                    }
                    ColumnLayout {
                        // advanced: the separate switches the Enhance button drives
                        visible: prefs.showAdvancedVideo || Qt.platform.os !== "osx"
                        Layout.fillWidth: true
                        spacing: 6
                    Toggle {
                        text: qsTr("Neural Engine upscaling (Apple ML)")
                        enabled: Chiaki.window.neuralUpscaleAvailable()
                        checked: Chiaki.settings.neuralUpscale && enabled
                        onToggled: { prefs.enhanceMode = 0; enh.stop(); Chiaki.settings.neuralUpscale = checked }
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
                    // e11 MetalFX upscaling (GPU spatial scaler); either this or the Neural Engine
                    Toggle {
                        text: qsTr("MetalFX upscaling (GPU, lighter than Neural Engine)")
                        enabled: Chiaki.window.metalFXAvailable()
                        checked: Chiaki.settings.metalFXUpscale && enabled
                        onToggled: { prefs.enhanceMode = 0; enh.stop(); Chiaki.settings.metalFXUpscale = checked }
                    }
                    Label {
                        id: metalFXStatus
                        visible: Chiaki.settings.metalFXUpscale
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.55)
                        text: Chiaki.window.metalFXStatus()
                        Timer {
                            interval: 1000; repeat: true
                            running: quickWindow.expanded && quickWindow.visible && Chiaki.settings.metalFXUpscale
                            onTriggered: metalFXStatus.text = Chiaki.window.metalFXStatus()
                        }
                    }
                    // e11 Pro Motion: 60 -> 120 fps frame generation (Apple ML, macOS 26+)
                    Toggle {
                        text: qsTr("e11 Pro Motion (120 fps frame generation)")
                        enabled: Chiaki.window.proMotionAvailable()
                        checked: Chiaki.settings.proMotion && enabled
                        onToggled: Chiaki.settings.proMotion = checked
                    }
                    Label {
                        id: proMotionStatus
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.55)
                        text: Chiaki.window.proMotionStatus()
                        Timer {
                            interval: 1000; repeat: true
                            running: quickWindow.expanded && quickWindow.visible
                            onTriggered: proMotionStatus.text = Chiaki.window.proMotionStatus()
                        }
                    }
                    // e11: Clean picture (Apple ML temporal noise filter, macOS 26+)
                    Toggle {
                        text: qsTr("Clean picture (removes blockiness and noise)")
                        enabled: Chiaki.window.cleanPictureAvailable()
                        checked: Chiaki.settings.cleanPicture && enabled
                        onToggled: { prefs.enhanceMode = 0; enh.stop(); Chiaki.settings.cleanPicture = checked }
                    }
                    Flow {
                        visible: Chiaki.settings.cleanPicture && Chiaki.window.cleanPictureAvailable()
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [
                                { name: qsTr("Light"), value: 0.25 },
                                { name: qsTr("Medium"), value: 0.5 },
                                { name: qsTr("Strong"), value: 0.85 }
                            ]
                            delegate: Chip {
                                required property var modelData
                                text: modelData.name
                                selected: Math.abs(Chiaki.settings.cleanPictureStrength - modelData.value) < 0.05
                                onClicked: Chiaki.settings.cleanPictureStrength = modelData.value
                            }
                        }
                    }
                    Label {
                        id: cleanStatus
                        visible: Chiaki.settings.cleanPicture
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.55)
                        text: Chiaki.window.cleanPictureStatus()
                        Timer {
                            interval: 1000; repeat: true
                            running: quickWindow.expanded && quickWindow.visible && Chiaki.settings.cleanPicture
                            onTriggered: cleanStatus.text = Chiaki.window.cleanPictureStatus()
                        }
                    }
                    }
                }
            }
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: pg2.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: pg2
                    width: parent.width - 12
                    spacing: 8
                    Label { text: qsTr("Sound"); color: "#f2c94c"; font.pixelSize: 20; font.weight: Font.Black; Layout.bottomMargin: 4 }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Chip {
                            text: Qt.platform.os === "osx" ? qsTr("Mac + TV") : qsTr("PC + TV")
                            selected: prefs.soundOnComputer
                            onClicked: { prefs.soundOnComputer = true; Chiaki.window.setComputerSoundMuted(false) }
                        }
                        Chip {
                            text: qsTr("TV only")
                            selected: !prefs.soundOnComputer
                            onClicked: { prefs.soundOnComputer = false; Chiaki.window.setComputerSoundMuted(true) }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.55)
                        text: (Qt.platform.os === "osx"
                               ? qsTr("Sound only on the Mac? Mute your TV: the PS5 always sends sound to it.")
                               : qsTr("Sound only on the PC? Mute your TV: the PS5 always sends sound to it."))
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: prefs.soundOnComputer
                        Label {
                            text: Qt.platform.os === "osx" ? qsTr("Mac speaker") : qsTr("Speaker")
                            color: "white"
                            font.pixelSize: 13
                        }
                        ComboBox {
                            id: speakerBox
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            model: [qsTr("System default (follows the sound menu)")].concat(Chiaki.settings.availableAudioOutDevices)
                            currentIndex: Math.max(0, model.indexOf(Chiaki.settings.audioOutDevice))
                            onActivated: (index) => Chiaki.settings.audioOutDevice = index ? model[index] : ""
                        }
                    }
                    Label {
                        visible: prefs.soundOnComputer
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.55)
                        text: Chiaki.settings.audioOutDevice === ""
                            ? qsTr("Switch speakers or AirPods any time from the sound menu in the menu bar.")
                            : qsTr("A chosen speaker is used from the next time you connect.")
                    }
                }
            }
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: pg3.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: pg3
                    width: parent.width - 12
                    spacing: 8
                    Label { text: qsTr("Stream"); color: "#b79bff"; font.pixelSize: 20; font.weight: Font.Black; Layout.bottomMargin: 4 }
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
                                                              qsTr("e11 FSR: sharp, light upscaling (default)"),
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
                                                text: qsTr("V-Sync (no tearing, slightly more latency)")
                                                checked: Chiaki.settings.vSyncEnabled
                                                onToggled: Chiaki.settings.vSyncEnabled = checked
                                            }
                }
            }
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: pg4.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: pg4
                    width: parent.width - 12
                    spacing: 8
                    Label { text: qsTr("Controller"); color: "#5fd3a6"; font.pixelSize: 20; font.weight: Font.Black; Layout.bottomMargin: 4 }
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
                            text: quickWindow.controllerLine(modelData) + qsTr("  ·  connected")
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
            }
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: pg5.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: pg5
                    width: parent.width - 12
                    spacing: 8
                    Label { text: qsTr("Display"); color: "#eef2f7"; font.pixelSize: 20; font.weight: Font.Black; Layout.bottomMargin: 4 }
                    // e11: the Mac screen's resolution while playing (same list as System Settings > Displays)
                    Label {
                        visible: Qt.platform.os === "osx"
                        text: qsTr("Mac resolution while playing")
                        color: "#8c97a6"
                        font.pixelSize: 12
                    }
                    Flow {
                        visible: Qt.platform.os === "osx"
                        Layout.fillWidth: true
                        spacing: 4
                        Component.onCompleted: quickWindow.refreshMacModes()
                        Chip {
                            text: qsTr("Mac setting")
                            selected: prefs.macResolution === ""
                            onClicked: { prefs.macResolution = ""; quickWindow.applyMacResolution(); }
                        }
                        Repeater {
                            model: quickWindow.macModes
                            delegate: Chip {
                                required property var modelData
                                text: modelData.label
                                selected: prefs.macResolution === modelData.key
                                onClicked: { prefs.macResolution = modelData.key; quickWindow.applyMacResolution(); }
                            }
                        }
                    }
                    Label {
                        visible: Qt.platform.os === "osx"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: "#8c97a6"
                        font.pixelSize: 11
                        text: qsTr("Only while e11 is streaming: your Mac goes back to its own setting when the stream ends or e11 quits. The top size is the sharpest.")
                    }
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

                }
            }
            }
        }
    }
}
