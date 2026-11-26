// e11 Home: sidebar + console cards + controller / Enhance / Sound / Smooth play cards.
// DeskCleaner palette: ground #07090c, panel #0b0e13, line #1e2530, ink #eef2f7, dim #8c97a6,
// sky #5aa9ff, lilac #b79bff, mint #5fd3a6, lemon #f2c94c, pink #ff7ab8.
// All console logic (connect, wake, PIN, hide/delete, PSN, discovery) is unchanged from before.
import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking

Pane {
    padding: 0
    id: consolePane

    readonly property color cGround: "#07090c"
    readonly property color cPanel: "#0b0e13"
    readonly property color cCard: "#0e1218"
    readonly property color cLine: "#1e2530"
    readonly property color cInk: "#eef2f7"
    readonly property color cDim: "#8c97a6"
    readonly property color cSky: "#5aa9ff"
    readonly property color cLilac: "#b79bff"
    readonly property color cMint: "#5fd3a6"
    readonly property color cLemon: "#f2c94c"
    readonly property color cPink: "#ff7ab8"
    // Sign-in saves the token from C++ (no settings change signal), so also re-check on psnTokenChanged
    property int psnTick: 0
    Connections { target: Chiaki; function onPsnTokenChanged() { consolePane.psnTick++ } }
    readonly property bool psnSignedIn: psnTick >= 0 && !!Chiaki.settings.psnAuthToken

    background: Rectangle { color: consolePane.cGround }

    // Shared with the in-stream quick menu (same category), so choices here apply to the next stream.
    Settings {
        id: e11prefs
        category: "e11_quick_menu_v2"
        property int enhanceMode: 1
        property bool soundOnComputer: true
        property bool fullHdDefaulted: false
        property bool fps60Defaulted: false
    }
    // e11: always stream 1080p (the PS5's maximum), at home and over PSN; once, so a user's later choice is kept
    Component.onCompleted: {
        if (!e11prefs.fullHdDefaulted) {
            e11prefs.fullHdDefaulted = true;
            Chiaki.settings.resolutionLocalPS5 = 4;
            Chiaki.settings.resolutionRemotePS5 = 4;
        }
        // e11: always 60 fps (30 stays an option in All settings); once, so a later choice is kept
        if (!e11prefs.fps60Defaulted) {
            e11prefs.fps60Defaulted = true;
            Chiaki.settings.fpsLocalPS5 = 60;
            Chiaki.settings.fpsRemotePS5 = 60;
            Chiaki.settings.fpsLocalPS4 = 60;
            Chiaki.settings.fpsRemotePS4 = 60;
        }
    }

    StackView.onActivated: {
        forceActiveFocus(Qt.TabFocusReason);
        if(!Chiaki.autoConnect && !root.initialAsk && !Chiaki.window.directStream)
        {
            root.initialAsk = true;
            if(Chiaki.settings.addSteamShortcutAsk && (typeof Chiaki.createSteamShortcut === "function") && Qt.platform.os !== "osx")
                root.showRemindDialog(qsTr("Official Steam artwork + controller layout"), qsTr("Would you like to either create a new non-Steam game for e11 Remote Play\nor update an existing non-Steam game with the official artwork and controller layout?") + "\n\n" + qsTr("(Note: If you select no now and want to do this later, click the button or press R3 from the main menu.)"), false, () => root.showSteamShortcutDialog(true));
            else if(Chiaki.settings.remotePlayAsk)
            {
                if(!Chiaki.settings.psnRefreshToken || !Chiaki.settings.psnAuthToken || !Chiaki.settings.psnAuthTokenExpiry || !Chiaki.settings.psnAccountId)
                    root.showRemindDialog(qsTr("Play from anywhere"), qsTr("Sign in with PlayStation Network to link your PS5 automatically and play outside your home network. A secure Sony window opens and e11 continues by itself. You can also do this later from the sidebar."), true, () => root.showPSNTokenDialog(false));
                else
                    Chiaki.settings.remotePlayAsk = false;
            }
        }
    }
    Keys.onUpPressed: {
        if(hostsView.currentItem && hostsView.currentItem.visible)
        {
            hostsView.decrementCurrentIndex()
            while(!hostsView.currentItem.visible)
                hostsView.decrementCurrentIndex()
        }
    }
    Keys.onDownPressed: {
        if(hostsView.currentItem && hostsView.currentItem.visible)
        {
            hostsView.incrementCurrentIndex()
            while(!hostsView.currentItem.visible)
                 hostsView.incrementCurrentIndex()
        }
    }
    Keys.onMenuPressed: settingsButton.clicked()
    Keys.onReturnPressed: if (hostsView.currentItem) hostsView.currentItem.connectToHost()
    Keys.onYesPressed: if (hostsView.currentItem) hostsView.currentItem.wakeUpHost()
    Keys.onNoPressed: if (hostsView.currentItem) hostsView.currentItem.deleteHost()
    Keys.onEscapePressed: root.showConfirmDialog(qsTr("Quit"), qsTr("Are you sure you want to quit?"), () => Qt.quit())
    Keys.onPressed: (event) => {
        if (event.modifiers)
            return;
        switch (event.key) {
        case Qt.Key_PageUp:
            if (hostsView.currentItem) hostsView.currentItem.setConsolePin();
            event.accepted = true;
            break;
        case Qt.Key_PageDown:
            if (Chiaki.settings.psnAuthToken) Chiaki.refreshPsnToken();
            event.accepted = true;
            break;
        case Qt.Key_F1:
            if (typeof Chiaki.createSteamShortcut === "function" && Qt.platform.os !== "osx") root.showSteamShortcutDialog(false);
            event.accepted = true;
            break;
        case Qt.Key_F2:
            root.showManualHostDialog();
            event.accepted = true;
            break;
        case Qt.Key_HomePage:
            // PS button on the controller (it is paired to this Mac, so the PS5 never sees it)
            consolePane.psButtonWake();
            event.accepted = true;
            break;
        }
    }

    // e11: the controller belongs to the Mac now, so its PS button can't wake the PS5 by itself.
    // We do it for it: wake the selected (or first) console and start playing.
    property double lastPsWake: 0
    function psButtonWake() {
        const now = Date.now();
        if (now - lastPsWake < 6000 || Chiaki.session)
            return;
        let item = hostsView.currentItem && hostsView.currentItem.visible ? hostsView.currentItem : null;
        if (!item) {
            for (let i = 0; i < hostsView.count; i++) {
                const it = hostsView.itemAtIndex(i);
                if (it && it.visible) { item = it; break; }
            }
        }
        if (!item) {
            psToast.show(qsTr("No PS5 found yet. Turn on console search or sign in with PSN."));
            return;
        }
        lastPsWake = now;
        psToast.show(qsTr("Waking %1 and starting…").arg(item.consoleName));
        item.psWake();
    }

    // ---------- small building blocks ----------
    component Ring: Rectangle {
        property color tint: consolePane.cSky
        width: 12; height: 12; radius: 6
        color: "transparent"
        border.width: 2
        border.color: tint
    }

    component NavItem: AbstractButton {
        id: nav
        property color tint: consolePane.cSky
        property bool active: false
        property string detail: ""
        Layout.fillWidth: true
        implicitHeight: 40
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        background: Rectangle {
            radius: 10
            color: nav.hovered && !nav.active ? Qt.alpha("#ffffff", 0.04) : "transparent"
            border.width: 1.5
            border.color: nav.active ? nav.tint : "transparent"
        }
        contentItem: RowLayout {
            spacing: 12
            Item { implicitWidth: 2 }
            Ring { tint: nav.tint }
            Label {
                Layout.fillWidth: true
                text: nav.text
                color: nav.active ? consolePane.cInk : "#b3bdc9"
                font.pixelSize: 14
                font.weight: nav.active ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            Label {
                visible: nav.detail !== ""
                text: nav.detail
                color: consolePane.cDim
                font.pixelSize: 11
            }
            Item { implicitWidth: 2 }
        }
    }

    component Chip: AbstractButton {
        id: chip
        property color tint: consolePane.cSky
        property color onInk: "#07131f"
        property bool on: false
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        implicitHeight: 30
        implicitWidth: chipLabel.implicitWidth + 26
        background: Rectangle {
            radius: height / 2
            color: chip.hovered && !chip.on ? Qt.alpha("#ffffff", 0.05) : "transparent"
            border.width: 1.5
            border.color: chip.on ? chip.tint : consolePane.cLine
        }
        contentItem: Label {
            id: chipLabel
            text: chip.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 12
            font.weight: chip.on ? Font.Bold : Font.Normal
            color: chip.on ? chip.tint : consolePane.cDim
        }
    }

    component PillButton: AbstractButton {
        id: pill
        property color tint: consolePane.cSky
        property bool filled: false
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        implicitHeight: 40
        implicitWidth: pillLabel.implicitWidth + 36
        background: Rectangle {
            radius: 12
            color: pill.filled ? (pill.down ? Qt.darker(pill.tint, 1.15) : pill.tint)
                               : (pill.hovered ? Qt.alpha(pill.tint, 0.10) : "transparent")
            border.width: pill.filled ? 0 : 1.5
            border.color: Qt.alpha(pill.tint, 0.7)
        }
        contentItem: Label {
            id: pillLabel
            text: pill.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 14
            font.weight: Font.Bold
            color: pill.filled ? "#07131f" : pill.tint
        }
    }

    component LinkText: Label {
        id: lt
        signal activated()
        property color tint: consolePane.cSky
        color: ltMouse.containsMouse ? Qt.lighter(lt.tint, 1.25) : lt.tint
        font.pixelSize: 12
        font.weight: Font.DemiBold
        MouseArea { id: ltMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lt.activated() }
    }

    component Card: Rectangle {
        property color tint: consolePane.cSky
        radius: 16
        color: "transparent"
        border.width: 1.5
        border.color: Qt.alpha(tint, 0.55)
    }

    component Check: RowLayout {
        id: chk
        property bool ok: true
        property bool known: true
        property string label: ""
        spacing: 6
        Rectangle {
            width: 16; height: 16; radius: 8
            color: !chk.known ? Qt.alpha(consolePane.cDim, 0.18) : chk.ok ? Qt.alpha(consolePane.cMint, 0.18) : Qt.alpha(consolePane.cLemon, 0.18)
            Label {
                anchors.centerIn: parent
                text: !chk.known ? "?" : chk.ok ? "✓" : "!"
                font.pixelSize: 10
                font.bold: true
                color: !chk.known ? consolePane.cDim : chk.ok ? consolePane.cMint : consolePane.cLemon
            }
        }
        Label {
            text: chk.label
            font.pixelSize: 13
            color: !chk.known ? consolePane.cDim : chk.ok ? consolePane.cInk : consolePane.cLemon
        }
    }

    // ---------- controller + smooth play state (polled only on this screen) ----------
    QtObject {
        id: controllerCard
        property int tick: 0
        property var smoothState: ({ bluetoothOn: false, airdropOn: false, handoffOn: false, airdropKnown: true, handoffKnown: true })
        readonly property bool anyWired: {
            tick;
            for (let i = 0; i < Chiaki.controllers.length; i++)
                if (Chiaki.controllers[i].wired())
                    return true;
            return false;
        }
        readonly property bool smoothOk: anyWired && !smoothState.bluetoothOn && !smoothState.airdropOn && !smoothState.handoffOn
        function line(c) {
            tick;
            let parts = [c.friendlyName(), c.wired() ? qsTr("USB-C") : qsTr("Bluetooth")];
            let b = c.batteryPercent();
            if (b >= 0)
                parts.push(qsTr("battery %1%").arg(b));
            return parts.join(" · ");
        }
        readonly property bool psOnUsb: {
            tick;
            for (let i = 0; i < Chiaki.controllers.length; i++) {
                let k = Chiaki.controllers[i].kind();
                if ((k === "ps5" || k === "ps5edge" || k === "ps4") && Chiaki.controllers[i].wired())
                    return true;
            }
            return false;
        }
    }
    Timer { interval: 2000; repeat: true; running: !Chiaki.session && consolePane.visible; triggeredOnStart: true
            onTriggered: { controllerCard.tick++; controllerCard.smoothState = Chiaki.window.smoothPlayStatus(); } }
    Shortcut {
        sequence: "Space"
        context: Qt.WindowShortcut
        enabled: !Chiaki.session && Qt.platform.os === "osx"
        onActivated: switchStatus.text = Chiaki.window.controllerToMac()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------- sidebar ----------
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 248
            color: consolePane.cPanel
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: consolePane.cLine }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                anchors.topMargin: 26
                spacing: 4

                Image {
                    source: "qrc:/icons/e11-wordmark.png"
                    Layout.preferredHeight: 44
                    Layout.preferredWidth: 44 * sourceSize.width / Math.max(1, sourceSize.height)
                    Layout.leftMargin: 8
                    Layout.bottomMargin: 22
                    fillMode: Image.PreserveAspectFit
                    smooth: true; mipmap: true
                }

                NavItem { text: qsTr("Play"); tint: consolePane.cSky; active: true }
                NavItem {
                    text: Chiaki.discoveryEnabled ? qsTr("Finding consoles") : qsTr("Find consoles")
                    detail: Chiaki.discoveryEnabled ? qsTr("on") : qsTr("off")
                    tint: consolePane.cLilac
                    onClicked: Chiaki.discoveryEnabled = !Chiaki.discoveryEnabled
                }
                NavItem { text: qsTr("Add a console"); tint: consolePane.cMint; onClicked: root.showManualHostDialog() }
                NavItem {
                    text: consolePane.psnSignedIn ? qsTr("Refresh PSN consoles") : qsTr("Sign in with PSN")
                    tint: consolePane.cPink
                    onClicked: consolePane.psnSignedIn ? Chiaki.refreshPsnToken() : root.showPSNTokenDialog(false)
                }
                NavItem {
                    text: qsTr("Sign out of PSN")
                    tint: consolePane.cDim
                    visible: consolePane.psnSignedIn
                    onClicked: {
                        Chiaki.settings.psnRefreshToken = ""
                        Chiaki.settings.psnAuthToken = ""
                        Chiaki.settings.psnAuthTokenExpiry = ""
                        Chiaki.settings.psnAccountId = ""
                    }
                }

                Label {
                    text: qsTr("STREAM")
                    color: consolePane.cDim
                    font.pixelSize: 10
                    font.letterSpacing: 1.6
                    font.weight: Font.DemiBold
                    Layout.leftMargin: 10
                    Layout.topMargin: 18
                    Layout.bottomMargin: 4
                }
                NavItem { text: qsTr("Smooth play"); tint: consolePane.cLemon; onClicked: smoothPopup.open() }
                // e11: every setting (video, stream, audio, keys, controllers...) in one clear place
                NavItem { id: settingsButton; text: qsTr("All settings"); tint: consolePane.cLilac; onClicked: root.showSettingsDialog() }
                NavItem {
                    text: qsTr("Steam shortcut"); tint: consolePane.cSky
                    visible: typeof Chiaki.createSteamShortcut === "function" && Qt.platform.os !== "osx"
                    onClicked: root.showSteamShortcutDialog(false)
                }

                Item { Layout.fillHeight: true }

                NavItem { text: qsTr("Quit"); tint: consolePane.cDim; onClicked: Qt.quit() }
                Label {
                    text: qsTr("e11 Remote Play %1").arg(Qt.application.version)
                    color: Qt.alpha(consolePane.cDim, 0.7)
                    font.pixelSize: 10
                    Layout.leftMargin: 10
                    Layout.topMargin: 8
                }
            }
        }

        // ---------- main ----------
        Flickable {
            id: mainFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: mainCol.implicitHeight + 72
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: mainCol
                x: 44
                y: 36
                width: Math.min(mainFlick.width - 88, 1100)
                spacing: 20

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        spacing: 4
                        Label {
                            text: hostsView.visibleCount > 0 ? qsTr("Ready to play") : qsTr("Let's find your PS5")
                            color: consolePane.cInk
                            font.pixelSize: 32
                            font.weight: Font.Black
                        }
                        Label {
                            text: (consolePane.psnSignedIn ? qsTr("Signed in with PSN") : qsTr("Home network only"))
                                  + (Chiaki.discoveryEnabled ? qsTr(" · looking for consoles") : "")
                            color: consolePane.cDim
                            font.pixelSize: 14
                        }
                    }
                    Item { Layout.fillWidth: true }
                    PillButton { text: qsTr("Add a console"); tint: consolePane.cSky; onClicked: root.showManualHostDialog() }
                }

                // ---------- consoles ----------
                ListView {
                    id: hostsView
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    interactive: false
                    keyNavigationWraps: true
                    spacing: 14
                    model: Chiaki.hosts
                    property int visibleCount: 0
                    function recount() {
                        let n = 0;
                        for (let i = 0; i < count; i++) {
                            const it = itemAtIndex(i);
                            if (it && it.visible) n++;
                        }
                        visibleCount = n;
                    }
                    Timer { interval: 500; repeat: true; running: consolePane.visible; triggeredOnStart: true; onTriggered: hostsView.recount() }
                    onCountChanged: {
                        recount();
                        if(!hostsView.currentItem)
                            hostsView.incrementCurrentIndex();
                        if(!hostsView.currentItem)
                            return;
                        if(!hostsView.currentItem.visible)
                        {
                            for(var i = 0; i < hostsView.count; i++)
                            {
                                hostsView.incrementCurrentIndex()
                                if(hostsView.currentItem.visible)
                                {
                                    break;
                                }
                            }
                        }
                    }
                    delegate: ItemDelegate {
                        id: delegate
                        visible: modelData.display
                        width: ListView.view ? ListView.view.width : 0
                        height: modelData.display ? 132 : 0
                        highlighted: ListView.isCurrentItem
                        hoverEnabled: true
                        padding: 0
                        onClicked: connectToHost()

                        readonly property string stateText: {
                            if (modelData.duid && !modelData.discovered)
                                return qsTr("Via PSN");
                            if (modelData.state === "standby")
                                return qsTr("Rest mode");
                            if (modelData.state === "ready")
                                return qsTr("Ready");
                            return modelData.state ? modelData.state : qsTr("Saved");
                        }
                        readonly property color stateTint: modelData.state === "standby" ? consolePane.cLemon
                                                          : (modelData.duid && !modelData.discovered) ? consolePane.cPink : consolePane.cMint

                        function connectToHost() {
                            if(modelData.discovered)
                                Chiaki.connectToHost(index, modelData.name);
                            else
                                Chiaki.connectToHost(index);
                        }

                        function wakeUpHost() {
                            if(!modelData.discovered && !modelData.duid)
                                Chiaki.wakeUpHost(index);
                        }

                        function deleteHost() {
                            if (modelData.manual)
                                root.showConfirmDialog(qsTr("Delete Console"), qsTr("Are you sure you want to delete this console?"), () => {Chiaki.deleteHost(index)});
                            else if (modelData.discovered && !modelData.registered)
                                root.showConfirmDialog(qsTr("Hide Console"), qsTr("Are you sure you want to hide this console?") + "\n\n" + qsTr("Note: You can unhide from the Consoles section of the Settings under Hidden Consoles"), () => Chiaki.hideHost(modelData.mac, modelData.name));
                        }

                        function setConsolePin() {
                            root.showConsolePinDialog(index);
                        }

                        readonly property string consoleName: modelData.name ? modelData.name : (modelData.ps5 ? "PS5" : "PS4")
                        function psWake() {
                            // Saved console that isn't visible on the network: send the wake packet first,
                            // then connect (connecting also wakes a console in rest mode or via PSN).
                            if (modelData.registered && !modelData.discovered && !modelData.duid)
                                Chiaki.wakeUpHost(index);
                            connectToHost();
                        }

                        background: Rectangle {
                            radius: 18
                            border.width: 1.5
                            border.color: Qt.alpha(consolePane.cSky, delegate.highlighted || delegate.hovered ? 0.8 : 0.45)
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.alpha(consolePane.cSky, delegate.hovered ? 0.11 : 0.07) }
                                GradientStop { position: 1; color: Qt.alpha(consolePane.cSky, 0.015) }
                            }
                        }

                        contentItem: RowLayout {
                            spacing: 24
                            Item { implicitWidth: 2 }
                            Rectangle {
                                Layout.preferredWidth: 92
                                Layout.preferredHeight: 92
                                radius: 20
                                color: consolePane.cCard
                                border.color: consolePane.cLine
                                Image {
                                    anchors.centerIn: parent
                                    width: 64; height: 64
                                    fillMode: Image.PreserveAspectFit
                                    source: "image://svg/console-ps" + (modelData.ps5 ? "5" : "4") + (modelData.state == "standby" ? "#light_standby" : "#light_on")
                                    sourceSize: Qt.size(width, height)
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                RowLayout {
                                    spacing: 10
                                    Label {
                                        text: modelData.name ? modelData.name : (modelData.ps5 ? "PS5" : "PS4")
                                        color: consolePane.cInk
                                        font.pixelSize: 22
                                        font.weight: Font.Black
                                    }
                                    Rectangle {
                                        implicitWidth: stateLabel.implicitWidth + 18
                                        implicitHeight: 22
                                        radius: 11
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Qt.alpha(delegate.stateTint, 0.55)
                                        Label {
                                            id: stateLabel
                                            anchors.centerIn: parent
                                            text: delegate.stateText.toUpperCase()
                                            color: delegate.stateTint
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.2
                                        }
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: consolePane.cDim
                                    font.pixelSize: 13
                                    text: {
                                        let parts = [];
                                        if (modelData.duid)
                                            parts.push(modelData.discovered ? qsTr("Links automatically with PSN") : qsTr("Plays from anywhere via PSN"));
                                        else if (modelData.discovered)
                                            parts.push(modelData.manual ? qsTr("On your network · saved") : qsTr("On your network"));
                                        else
                                            parts.push(qsTr("Saved console"));
                                        if (modelData.address)
                                            parts.push(Chiaki.settings.streamerMode ? qsTr("address hidden") : modelData.address);
                                        if (modelData.mac && !modelData.registered)
                                            parts.push(qsTr("not linked yet"));
                                        return parts.join("  ·  ");
                                    }
                                }
                                Label {
                                    visible: !!(modelData.discovered && modelData.app)
                                    text: qsTr("Playing: %1").arg(modelData.app)
                                    color: consolePane.cLilac
                                    font.pixelSize: 12
                                }
                                RowLayout {
                                    spacing: 14
                                    LinkText {
                                        visible: modelData.registered && !modelData.duid && !modelData.discovered
                                        text: qsTr("Wake up")
                                        tint: consolePane.cSky
                                        font.pixelSize: 12
                                        onActivated: delegate.wakeUpHost()
                                    }
                                    LinkText {
                                        visible: modelData.registered
                                        text: qsTr("Console PIN")
                                        tint: consolePane.cDim
                                        font.pixelSize: 12
                                        onActivated: delegate.setConsolePin()
                                    }
                                    LinkText {
                                        visible: modelData.manual || (modelData.discovered && !modelData.registered)
                                        text: (modelData.manual ? qsTr("Delete") : qsTr("Hide"))
                                        tint: consolePane.cDim
                                        font.pixelSize: 12
                                        onActivated: delegate.deleteHost()
                                    }
                                }
                            }
                            PillButton {
                                text: modelData.registered || modelData.duid ? qsTr("Play") : qsTr("Link & play")
                                filled: true
                                tint: consolePane.cSky
                                implicitHeight: 54
                                implicitWidth: Math.max(130, implicitContentWidth + 48)
                                onClicked: delegate.connectToHost()
                            }
                            Item { implicitWidth: 6 }
                        }
                    }
                }

                // empty state
                Card {
                    visible: hostsView.visibleCount === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 132
                    tint: consolePane.cLilac
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 20
                        BusyIndicator { running: Chiaki.discoveryEnabled; visible: Chiaki.discoveryEnabled; Layout.preferredWidth: 48; Layout.preferredHeight: 48 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Label { text: Chiaki.discoveryEnabled ? qsTr("Looking for your PS5 on this network…") : qsTr("Console search is off"); color: consolePane.cInk; font.pixelSize: 18; font.weight: Font.Bold }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: consolePane.cDim
                                font.pixelSize: 13
                                text: consolePane.psnSignedIn
                                      ? qsTr("Make sure the PS5 is on or in rest mode. You can also refresh your PSN consoles from the sidebar.")
                                      : qsTr("Make sure the PS5 is on or in rest mode and on the same Wi-Fi. Or sign in with PSN to play from anywhere.")
                            }
                        }
                        PillButton {
                            visible: !consolePane.psnSignedIn
                            text: qsTr("Sign in with PSN")
                            tint: consolePane.cPink
                            onClicked: root.showPSNTokenDialog(false)
                        }
                        PillButton {
                            visible: !Chiaki.discoveryEnabled
                            text: qsTr("Turn on search")
                            tint: consolePane.cLilac
                            onClicked: Chiaki.discoveryEnabled = true
                        }
                    }
                }

                // ---------- controller / enhance / sound ----------
                GridLayout {
                    Layout.fillWidth: true
                    columns: mainCol.width > 820 ? 3 : 1
                    columnSpacing: 16
                    rowSpacing: 16

                    Card {
                        tint: consolePane.cMint
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        implicitHeight: ctrlCol.implicitHeight + 36
                        ColumnLayout {
                            id: ctrlCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                            spacing: 8
                            Label { text: qsTr("Controller"); color: consolePane.cMint; font.pixelSize: 15; font.weight: Font.Black }
                            Label {
                                visible: Chiaki.controllers.length === 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Plug your controller in with USB-C, or pair it over Bluetooth.")
                                color: consolePane.cInk
                                font.pixelSize: 13
                            }
                            Repeater {
                                model: Chiaki.controllers
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { width: 8; height: 8; radius: 4; color: consolePane.cMint }
                                    Label { Layout.fillWidth: true; elide: Text.ElideRight; color: consolePane.cInk; font.pixelSize: 13; text: controllerCard.line(modelData) }
                                }
                            }
                            Label {
                                visible: Chiaki.controllers.length > 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: 12
                                color: consolePane.cMint
                                text: qsTr("Press the PS button to wake your PS5 and start playing.")
                            }
                            PillButton {
                                visible: Qt.platform.os === "osx"
                                text: qsTr("Use controller on this Mac  ·  Space")
                                tint: consolePane.cMint
                                implicitHeight: 34
                                onClicked: switchStatus.text = Chiaki.window.controllerToMac()
                            }
                            Label {
                                id: switchStatus
                                visible: Qt.platform.os === "osx"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: 11
                                color: consolePane.cDim
                                text: qsTr("Moves the controller from the PS5 to this Mac. First time: hold Create + PS for 5 s, then pair it in Bluetooth settings.")
                            }
                            Label {
                                visible: controllerCard.psOnUsb
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: 11
                                color: consolePane.cLemon
                                text: qsTr("Inputs doubled? On the PS5: Settings → Accessories → Controllers → Communication Method → Use USB Cable.")
                            }
                        }
                    }

                    Card {
                        tint: consolePane.cPink
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        implicitHeight: enhCol.implicitHeight + 36
                        ColumnLayout {
                            id: enhCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                            spacing: 10
                            Label { text: qsTr("Graphics"); color: consolePane.cPink; font.pixelSize: 15; font.weight: Font.Black }
                            RowLayout {
                                spacing: 6
                                Chip { text: qsTr("Off"); tint: consolePane.cPink; onInk: "#12060d"; on: e11prefs.enhanceMode === 0; onClicked: e11prefs.enhanceMode = 0 }
                                Chip { text: qsTr("Auto"); tint: consolePane.cPink; onInk: "#12060d"; on: e11prefs.enhanceMode === 1; onClicked: e11prefs.enhanceMode = 1 }
                                Chip { text: qsTr("Max"); tint: consolePane.cPink; onInk: "#12060d"; on: e11prefs.enhanceMode === 2; onClicked: e11prefs.enhanceMode = 2 }
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: consolePane.cDim
                                font.pixelSize: 12
                                text: e11prefs.enhanceMode === 0 ? qsTr("Plain picture, exactly as the PS5 sends it.")
                                     : e11prefs.enhanceMode === 1 ? qsTr("Apple MetalFX upscales the 1080p stream to your screen. Steps back only when it must, then comes back. Plus 120 fps Pro Motion on 120 Hz screens.")
                                     : qsTr("Apple MetalFX upscales the 1080p stream to your screen all the time. Plus 120 fps Pro Motion on 120 Hz screens.")
                            }
                        }
                    }

                    Card {
                        tint: consolePane.cLemon
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        implicitHeight: soundCol.implicitHeight + 36
                        ColumnLayout {
                            id: soundCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                            spacing: 10
                            Label { text: qsTr("Sound"); color: consolePane.cLemon; font.pixelSize: 15; font.weight: Font.Black }
                            RowLayout {
                                spacing: 6
                                Chip { text: qsTr("Mac + TV"); tint: consolePane.cLemon; onInk: "#1a1404"; on: e11prefs.soundOnComputer; onClicked: e11prefs.soundOnComputer = true }
                                Chip { text: qsTr("TV only"); tint: consolePane.cLemon; onInk: "#1a1404"; on: !e11prefs.soundOnComputer; onClicked: e11prefs.soundOnComputer = false }
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: consolePane.cDim
                                font.pixelSize: 12
                                text: e11prefs.soundOnComputer ? qsTr("Plays on this Mac and the TV, in sync. Mute the TV if you only want the Mac.")
                                                               : qsTr("The Mac stays quiet; sound comes from the TV.")
                            }
                        }
                    }
                }

                // ---------- smooth play ----------
                Card {
                    tint: consolePane.cLilac
                    Layout.fillWidth: true
                    implicitHeight: smoothCol.implicitHeight + 36
                    ColumnLayout {
                        id: smoothCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: controllerCard.smoothOk ? qsTr("Smooth play: ready") : qsTr("Smooth play check")
                                color: consolePane.cLilac
                                font.pixelSize: 15
                                font.weight: Font.Black
                            }
                            Item { Layout.fillWidth: true }
                            LinkText {
                                text: (controllerCard.smoothOk ? qsTr("Tips") : qsTr("How to fix"))
                                tint: consolePane.cLilac
                                font.pixelSize: 13
                                onActivated: smoothPopup.open()
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 22
                            Check { ok: controllerCard.anyWired; label: controllerCard.anyWired ? qsTr("USB-C controller") : qsTr("Controller not on USB-C") }
                            Check { visible: Qt.platform.os === "osx"; ok: !controllerCard.smoothState.bluetoothOn; label: controllerCard.smoothState.bluetoothOn ? qsTr("Bluetooth on") : qsTr("Bluetooth off") }
                            Check { visible: Qt.platform.os === "osx"; known: controllerCard.smoothState.airdropKnown; ok: !controllerCard.smoothState.airdropOn; label: !known ? qsTr("AirDrop: check it's off") : controllerCard.smoothState.airdropOn ? qsTr("AirDrop on") : qsTr("AirDrop off") }
                            Check { visible: Qt.platform.os === "osx"; known: controllerCard.smoothState.handoffKnown; ok: !controllerCard.smoothState.handoffOn; label: !known ? qsTr("Handoff: check it's off") : controllerCard.smoothState.handoffOn ? qsTr("Handoff on") : qsTr("Handoff off") }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: psToast
        function show(t) { psToastText.text = t; opacity = 1; psToastTimer.restart(); }
        z: 50
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
        width: psToastText.implicitWidth + 40
        height: 44
        radius: 22
        color: consolePane.cPanel
        border.color: Qt.alpha(consolePane.cMint, 0.6)
        Label { id: psToastText; anchors.centerIn: parent; color: consolePane.cInk; font.pixelSize: 14 }
        Timer { id: psToastTimer; interval: 3500; onTriggered: psToast.opacity = 0 }
    }

    // Smooth play guide: a plain overlay on this screen (dims the page, card in the middle)
    Rectangle {
        id: smoothPopup
        function open() { visible = true; }
        function close() { visible = false; }
        visible: false
        anchors.fill: parent
        z: 100
        color: "#b307090c"
        MouseArea { anchors.fill: parent; onClicked: smoothPopup.close() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 640)
            height: smoothCard.implicitHeight + 48
            radius: 18
            color: consolePane.cPanel
            border.color: consolePane.cLine
            MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: smoothCard
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            Label { text: qsTr("Smooth play on Mac"); color: consolePane.cInk; font.pixelSize: 22; font.weight: Font.Black }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: consolePane.cDim; font.pixelSize: 13
                text: qsTr("On a MacBook, Wi-Fi and Bluetooth share one radio. Anything else using it causes lag spikes and a jumpy controller.")
            }
            Repeater {
                model: [
                    { ok: controllerCard.anyWired, t: qsTr("1. Plug the controller into the Mac with USB-C"), d: qsTr("Wired is instant and never jumps to the PS5."), b: "" },
                    { ok: !controllerCard.smoothState.bluetoothOn, t: qsTr("2. Turn Bluetooth off while you play"), d: qsTr("Frees the radio for Wi-Fi. Your USB-C controller keeps working."), b: "bt" },
                    { ok: controllerCard.smoothState.airdropKnown && controllerCard.smoothState.handoffKnown && !(controllerCard.smoothState.airdropOn || controllerCard.smoothState.handoffOn), t: qsTr("3. Turn off AirDrop and Handoff"), d: qsTr("AirDrop: No One. Handoff: off. They make Wi-Fi hop channels every few seconds, the classic Mac stutter."), b: "ah" },
                    { ok: true, t: qsTr("4. Still lagging? Plug the PS5 into your router with ethernet"), d: qsTr("Then only the Mac is on Wi-Fi. Stay close to the router."), b: "" }
                ]
                delegate: RowLayout {
                    required property var modelData
                    visible: Qt.platform.os === "osx" || modelData.b === ""
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        width: 20; height: 20; radius: 10
                        color: Qt.alpha(modelData.ok ? consolePane.cMint : consolePane.cLemon, 0.18)
                        Label { anchors.centerIn: parent; text: modelData.ok ? "✓" : "!"; font.pixelSize: 12; font.bold: true; color: modelData.ok ? consolePane.cMint : consolePane.cLemon }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.t; color: consolePane.cInk; font.pixelSize: 14; font.bold: true }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.d; color: consolePane.cDim; font.pixelSize: 12 }
                    }
                    PillButton {
                        visible: modelData.b !== ""
                        text: qsTr("Open")
                        tint: consolePane.cSky
                        implicitHeight: 32
                        onClicked: modelData.b === "bt" ? Chiaki.window.openBluetoothSettings() : Chiaki.window.openAirDropHandoffSettings()
                    }
                }
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Qt.alpha(consolePane.cDim, 0.8); font.pixelSize: 11
                text: qsTr("Game Mode turns on by itself in full screen and doubles Bluetooth polling. With Bluetooth off it doesn't matter.")
                visible: Qt.platform.os === "osx"
            }
            PillButton { text: qsTr("Got it"); filled: true; tint: consolePane.cSky; Layout.alignment: Qt.AlignRight; onClicked: smoothPopup.close() }
        }
    }
    }
}
