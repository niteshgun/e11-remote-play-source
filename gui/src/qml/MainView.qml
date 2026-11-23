import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking

Pane {
    padding: 0
    id: consolePane
    StackView.onActivated: {
        forceActiveFocus(Qt.TabFocusReason);
        if(!Chiaki.autoConnect && !root.initialAsk && !Chiaki.window.directStream)
        {
            root.initialAsk = true;
            if(Chiaki.settings.addSteamShortcutAsk && (typeof Chiaki.createSteamShortcut === "function"))
                root.showRemindDialog(qsTr("Official Steam artwork + controller layout"), qsTr("Would you like to either create a new non-Steam game for e11 Remote Play\nor update an existing non-Steam game with the official artwork and controller layout?") + "\n\n" + qsTr("(Note: If you select no now and want to do this later, click the button or press R3 from the main menu.)"), false, () => root.showSteamShortcutDialog(true));
            else if(Chiaki.settings.remotePlayAsk)
            {
                if(!Chiaki.settings.psnRefreshToken || !Chiaki.settings.psnAuthToken || !Chiaki.settings.psnAuthTokenExpiry || !Chiaki.settings.psnAccountId)
                    root.showRemindDialog(qsTr("Remote Play via PSN"), qsTr("Would you like to connect to PSN?\nThis enables:\n- Automatic registration\n- Playing outside of your home network without port forwarding?") + "\n\n" + qsTr("(Note: If you select no now and want to do this later, go to the Config section of the settings.)"), true, () => root.showPSNTokenDialog(false));
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
            if (typeof Chiaki.createSteamShortcut === "function") root.showSteamShortcutDialog(false);
            event.accepted = true;
            break;
        case Qt.Key_F2:
            root.showManualHostDialog();
            event.accepted = true;
            break;
        }
    }

    ToolBar {
        id: toolBar
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 80

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                flat: true
                text: "×"
                font.pixelSize: 60
                focusPolicy: Qt.NoFocus
                onClicked: Qt.quit()
                Material.roundedScale: Material.SmallScale
            }

            Item { Layout.fillWidth: true }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 350
                flat: true
                text: "Create Steam Shortcut"
                focusPolicy: Qt.NoFocus
                onClicked: root.showSteamShortcutDialog(false)
                Material.roundedScale: Material.SmallScale
                visible: typeof Chiaki.createSteamShortcut === "function"
                Image {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                    }
                    width: 28
                    height: 28
                    sourceSize: Qt.size(width, height)
                    source: "qrc:/icons/l3.svg"
                }
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 400
                flat: true
                text: "Refresh PSN Hosts"
                icon.source: "qrc:/icons/r1.svg"
                focusPolicy: Qt.NoFocus
                onClicked: Chiaki.refreshPsnToken();
                Material.roundedScale: Material.SmallScale
                visible: Chiaki.settings.psnAuthToken
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 400
                flat: true
                focusPolicy: Qt.NoFocus
                Material.roundedScale: Material.SmallScale
                visible: !Chiaki.settings.psnAuthToken
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 300
                flat: true
                text: "Add Manual Host"
                focusPolicy: Qt.NoFocus
                onClicked: root.showManualHostDialog()
                Material.roundedScale: Material.SmallScale
                Image {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                    }
                    width: 28
                    height: 28
                    sourceSize: Qt.size(width, height)
                    source: "qrc:/icons/r3.svg"
                }
            }

            Button {
                id: settingsButton
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                flat: true
                icon.source: "qrc:/icons/settings-20px.svg";
                icon.width: 50
                icon.height: 50
                focusPolicy: Qt.NoFocus
                onClicked: root.showSettingsDialog()
                Material.roundedScale: Material.SmallScale
            }
        }
    }

    ListView {
        id: hostsView
        keyNavigationWraps: true
        anchors {
            top: toolBar.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: 50
        }
        clip: true
        model: Chiaki.hosts
        onCountChanged: {
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
            visible: modelData.display
            id: delegate
            width: parent ? parent.width : 0
            height: modelData.display ? 180 : 0
            highlighted: ListView.isCurrentItem
            onClicked: connectToHost()

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

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 30
                    rightMargin: 10
                    topMargin: 10
                    bottomMargin: 10
                }
                spacing: 50

                Image {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 150
                    fillMode: Image.PreserveAspectFit
                    source: "image://svg/console-ps" + (modelData.ps5 ? "5" : "4") + (modelData.state == "standby" ? "#light_standby" : "#light_on")
                    sourceSize: Qt.size(width, height)
                }

                Label {
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    text: {
                        let t = "";
                        if (modelData.name)
                            t += modelData.name + "\n";
                        if (modelData.address)
                            t += qsTr("Address: %1").arg(Chiaki.settings.streamerMode ? "hidden" : modelData.address);
                        if (modelData.mac)
                            t += "\n" + qsTr("ID: %1 (%2)").arg(Chiaki.settings.streamerMode ? "hidden" : modelData.mac).arg(modelData.registered ? qsTr("registered") : qsTr("unregistered"));
                        if (modelData.duid)
                        {
                            if(modelData.discovered)
                                t += "\n" + qsTr("Automatic Registration Available");
                            else
                                t += "\n" + qsTr("Remote Connection via PSN");
                        } 
                        else
                        {
                            t += "\n";
                            if(modelData.discovered)
                            {
                                if(modelData.manual)
                                    t += qsTr("discovered + manual")
                                else
                                    t += qsTr("discovered");
                            }
                            else
                                t += qsTr("manual");
                        }
                        return t;
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    text: {
                        let t = "";
                        if(modelData.duid)
                            return t;
                        t += qsTr("State: %1").arg(modelData.state);
                        if(!modelData.discovered)
                            return t;
                        if (modelData.app)
                            t += "\n" + qsTr("App: %1").arg(modelData.app);
                        if (modelData.titleId)
                            t += "\n" + qsTr("Title ID: %1").arg(modelData.titleId);
                        return t;
                    }
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 0

                    Button {
                        Layout.alignment: Qt.AlignCenter
                        text: modelData.manual ? qsTr("Delete") : qsTr("Hide")
                        flat: true
                        padding: 20
                        leftPadding: delegate.highlighted ? 50 : undefined
                        focusPolicy: Qt.NoFocus
                        visible: modelData.manual || (modelData.discovered && !modelData.registered)
                        onClicked: delegate.deleteHost()
                        Material.roundedScale: Material.SmallScale

                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: root.controllerButton("box")
                            visible: delegate.highlighted
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignCenter
                        text: qsTr("Wake Up")
                        flat: true
                        padding: 20
                        leftPadding: delegate.highlighted ? 50 : undefined
                        visible: modelData.registered && !modelData.duid && !modelData.discovered
                        focusPolicy: Qt.NoFocus
                        onClicked: delegate.wakeUpHost()
                        Material.roundedScale: Material.SmallScale

                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: root.controllerButton("pyramid")
                            visible: delegate.highlighted
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignCenter
                        text: qsTr("Update Console Pin")
                        flat: true
                        padding: 20
                        leftPadding: delegate.highlighted ? 50 : undefined
                        visible: modelData.registered
                        focusPolicy: Qt.NoFocus
                        onClicked: delegate.setConsolePin()
                        Material.roundedScale: Material.SmallScale

                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: "qrc:/icons/l1.svg"
                            visible: delegate.highlighted
                        }
                    }
                } 
            } 
        }
    }     

    RoundButton {
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: 20
        }
        icon.source: "qrc:/icons/discover-" + (checked ? "" : "off-") + "24px.svg"
        icon.width: 50
        icon.height: 50
        padding: 20
        focusPolicy: Qt.NoFocus
        checkable: true
        checked: Chiaki.discoveryEnabled
        onToggled: Chiaki.discoveryEnabled = !Chiaki.discoveryEnabled
        Material.background: Material.accent
    }

    Label {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 20
        }
        text: Qt.application.version
    }

    Image {
        id: logoImage
        anchors.centerIn: parent
        source: "qrc:/icons/chiaking-logo-white.svg"
        width: Math.min(parent.width, parent.height) / 2
        height: width
        fillMode: Image.PreserveAspectFit
        sourceSize.width: width * 2

        PropertyAnimation {
            target: logoImage
            property: "opacity"
            from: 0.05
            to: 0.20
            duration: 1000
            easing.type: Easing.OutCubic
            running: true
        }
    }

    // e11: controller card on the main screen (no background Bluetooth scanning)
    Rectangle {
        id: controllerCard
        property int tick: 0
        // Only poll on the main screen, never while streaming
        Timer { interval: 2000; repeat: true; running: !Chiaki.session && consolePane.visible; triggeredOnStart: true
                onTriggered: { controllerCard.tick++; controllerCard.smoothState = Chiaki.window.smoothPlayStatus(); } }
        property var smoothState: ({ bluetoothOn: false, airdropOn: false, handoffOn: false })
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
            let parts = [c.friendlyName(), c.wired() ? qsTr("USB") : qsTr("Bluetooth")];
            let b = c.batteryPercent();
            if (!c.wired() && b >= 0)
                parts.push(b + "%");
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
        z: 5
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 24
        }
        width: Math.min(parent.width - 120, 680)
        implicitHeight: cardCol.implicitHeight + 24
        height: implicitHeight
        radius: 14
        color: Qt.rgba(0.08, 0.08, 0.10, 0.88)
        border.color: Chiaki.controllers.length > 0 ? Qt.rgba(0.35, 0.82, 0.48, 0.55) : Qt.rgba(1, 1, 1, 0.16)
        border.width: 1

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                visible: Chiaki.controllers.length === 0
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: "white"
                    font.pixelSize: 14
                    text: qsTr("🎮  Connect your controller: plug it in with USB-C, or pair it over Bluetooth.")
                }
                Button {
                    text: qsTr("Bluetooth settings")
                    flat: true
                    onClicked: Chiaki.window.openBluetoothSettings()
                }
            }
            Repeater {
                model: Chiaki.controllers
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Rectangle { width: 9; height: 9; radius: 4.5; color: "#5ad17a" }
                    Label {
                        Layout.fillWidth: true
                        color: "white"
                        font.pixelSize: 14
                        text: "🎮  " + controllerCard.line(modelData) + qsTr("  ·  connected")
                    }
                }
            }
            // One click (or Space) pulls the controller from the PS5 over to this Mac (macOS only)
            RowLayout {
                visible: Qt.platform.os === "osx"
                Layout.fillWidth: true
                Button {
                    id: toMacButton
                    text: qsTr("🎮 Use controller on this Mac  (Space)")
                    highlighted: true
                    onClicked: switchStatus.text = Chiaki.window.controllerToMac()
                }
                Label {
                    id: switchStatus
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.7)
                    text: qsTr("Switches the controller from the PS5 to this Mac. One-time setup: hold Circle + PS for 5 s, then connect it in Bluetooth settings.")
                }
            }
            Shortcut {
                sequence: "Space"
                context: Qt.WindowShortcut
                enabled: !Chiaki.session && Qt.platform.os === "osx"
                onActivated: switchStatus.text = Chiaki.window.controllerToMac()
            }
            // e11: Smooth play checklist. Bluetooth + AirDrop/Handoff share the Mac's Wi-Fi radio and cause lag spikes.
            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.10) }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Label {
                    color: controllerCard.smoothOk ? "#5ad17a" : "#ffd9a8"
                    font.pixelSize: 13
                    font.bold: true
                    text: controllerCard.smoothOk ? qsTr("✓ Smooth play ready") : qsTr("⚠ Smooth play")
                }
                Label { font.pixelSize: 12; color: controllerCard.anyWired ? "#5ad17a" : "#ffd9a8"
                        text: (controllerCard.anyWired ? "✓" : "⚠") + qsTr(" USB-C") }
                Label { visible: Qt.platform.os === "osx"; font.pixelSize: 12; color: controllerCard.smoothState.bluetoothOn ? "#ffd9a8" : "#5ad17a"
                        text: controllerCard.smoothState.bluetoothOn ? qsTr("⚠ Bluetooth") : qsTr("✓ Bluetooth off") }
                Label { visible: Qt.platform.os === "osx"; font.pixelSize: 12
                        readonly property bool on: controllerCard.smoothState.airdropOn || controllerCard.smoothState.handoffOn
                        color: on ? "#ffd9a8" : "#5ad17a"
                        text: on ? qsTr("⚠ AirDrop/Handoff") : qsTr("✓ AirDrop/Handoff off") }
                Item { Layout.fillWidth: true }
                Button {
                    text: controllerCard.smoothOk ? qsTr("Tips") : qsTr("Fix lag")
                    flat: true
                    onClicked: smoothPopup.open()
                }
            }
            Label {
                visible: controllerCard.psOnUsb
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                color: "#ffd9a8"
                text: qsTr("Inputs doubled? Your PS5 may also be using this controller over Bluetooth. Fix once on the PS5: "
                         + "Settings → Accessories → Controller (General) → Communication Method → Use USB Cable.")
            }
        }

        Popup {
            id: smoothPopup
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: Math.min(parent ? parent.width - 80 : 640, 640)
            modal: true
            focus: true
            padding: 22
            background: Rectangle { radius: 16; color: Qt.rgba(0.08, 0.08, 0.10, 0.97); border.color: Qt.rgba(1, 1, 1, 0.15) }
            contentItem: ColumnLayout {
                spacing: 12
                Label { text: qsTr("Smooth play on Mac"); color: "white"; font.pixelSize: 20; font.bold: true }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Qt.rgba(1, 1, 1, 0.75); font.pixelSize: 13
                    text: qsTr("On a MacBook, Wi-Fi and Bluetooth share one radio. Anything else using it causes lag spikes and a jumpy controller.")
                }
                Repeater {
                    model: [
                        { ok: controllerCard.anyWired, t: qsTr("1. Plug the controller into the Mac with USB-C"), d: qsTr("Wired is instant and never jumps to the PS5."), b: "" },
                        { ok: !controllerCard.smoothState.bluetoothOn, t: qsTr("2. Turn Bluetooth off while you play"), d: qsTr("Frees the radio for Wi-Fi. Your USB-C controller keeps working."), b: "bt" },
                        { ok: !(controllerCard.smoothState.airdropOn || controllerCard.smoothState.handoffOn), t: qsTr("3. Turn off AirDrop and Handoff"), d: qsTr("AirDrop: No One. Handoff: off. They make Wi-Fi hop channels every few seconds, the classic Mac stutter."), b: "ah" },
                        { ok: true, t: qsTr("4. Still lagging? Plug the PS5 into your router with ethernet"), d: qsTr("Then only the Mac is on Wi-Fi. Stay close to the router."), b: "" }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        visible: Qt.platform.os === "osx" || modelData.b === ""
                        Layout.fillWidth: true
                        spacing: 10
                        Label { text: modelData.ok ? "✓" : "⚠"; color: modelData.ok ? "#5ad17a" : "#ffd9a8"; font.pixelSize: 18; Layout.alignment: Qt.AlignTop }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.t; color: "white"; font.pixelSize: 14; font.bold: true }
                            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.d; color: Qt.rgba(1, 1, 1, 0.65); font.pixelSize: 12 }
                        }
                        Button {
                            visible: modelData.b !== ""
                            text: qsTr("Open")
                            flat: true
                            onClicked: modelData.b === "bt" ? Chiaki.window.openBluetoothSettings() : Chiaki.window.openAirDropHandoffSettings()
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Qt.rgba(1, 1, 1, 0.5); font.pixelSize: 11
                    text: qsTr("Game Mode turns on by itself in full screen and doubles Bluetooth polling. With Bluetooth off it doesn't matter.")
                    visible: Qt.platform.os === "osx"
                }
                Button { text: qsTr("Got it"); highlighted: true; Layout.alignment: Qt.AlignRight; onClicked: smoothPopup.close() }
            }
        }
    }
}
