import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking

import "controls" as C

DialogView {
    property bool ps5: true
    property alias host: hostField.text
    title: qsTr("Link your console")
    buttonText: qsTr("Link")
    buttonEnabled: hostField.text.trim() && pin.acceptableInput && cpin.acceptableInput && (!onlineId.visible || onlineId.text.trim()) && (!accountId.visible || accountId.text.trim())
    StackView.onActivated: {
        if(Chiaki.settings.psnAccountId)
            accountId.text = Chiaki.settings.psnAccountId
    }
    onAccepted: {
        let psnId = onlineId.visible ? onlineId.text.trim() : accountId.text.trim();
        let registerOk = Chiaki.registerHost(hostField.text.trim(), psnId, pin.text.trim(), cpin.text.trim(), hostField.text.trim() == "255.255.255.255", consoleButtons.checkedButton.target, function(msg, ok, done) {
            if (!done)
                logArea.text += msg + "\n";
            else
                logDialog.standardButtons = Dialog.Close;
        });
        if (registerOk) {
            logArea.text = "";
            logDialog.open();
        }
    }

    property bool showPs4: !ps5
    Item {
        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: form.implicitHeight + 60
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: form
            width: Math.min(parent.width - 80, 560)
            x: (parent.width - width) / 2
            y: 32
            spacing: 18

            // What to do on the console, in plain words
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: howCol.implicitHeight + 32
                radius: 16
                color: "transparent"
                border.width: 1.5
                border.color: "#8c5aa9ff"
                ColumnLayout {
                    id: howCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 6
                    Label { text: qsTr("Link this Mac to your console"); color: "#5aa9ff"; font.pixelSize: 16; font.weight: Font.Black }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: "#b3bdc9"
                        font.pixelSize: 13
                        text: ps5_0.checked
                              ? qsTr("On your PS5: Settings › System › Remote Play › Link Device. Type the 8-digit code it shows below. You only do this once.")
                              : qsTr("On your PS4: Settings › Remote Play Connection Settings › Add Device. Type the 8-digit code it shows below. You only do this once.")
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: qsTr("Console address"); color: "#8c97a6"; font.pixelSize: 12 }
                C.TextField {
                    id: hostField
                    echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                    Layout.fillWidth: true
                    firstInFocusChain: true
                    placeholderText: qsTr("for example 192.168.1.20")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: onlineId.visible
                Label { text: qsTr("PSN username (case-sensitive)"); color: "#8c97a6"; font.pixelSize: 12 }
                C.TextField {
                    id: onlineId
                    echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                    visible: ps4_7.checked
                    Layout.fillWidth: true
                }
            }

            // Signed in with PSN: the account is filled in for you, nothing to type
            RowLayout {
                visible: !ps4_7.checked && !!Chiaki.settings.psnAccountId
                spacing: 10
                Rectangle {
                    width: 20; height: 20; radius: 10
                    color: "#2e5fd3a6"
                    Label { anchors.centerIn: parent; text: "✓"; color: "#5fd3a6"; font.pixelSize: 12; font.bold: true }
                }
                Label { text: qsTr("Using your PSN account"); color: "#eef2f7"; font.pixelSize: 14 }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: accountId.visible
                Label { text: qsTr("PSN account ID"); color: "#8c97a6"; font.pixelSize: 12 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    C.TextField {
                        id: accountId
                        visible: !ps4_7.checked && !Chiaki.settings.psnAccountId
                        echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                        placeholderText: qsTr("sign in to fill this automatically")
                        Layout.fillWidth: true
                        KeyNavigation.priority: {
                            if(readOnly)
                                KeyNavigation.BeforeItem
                            else
                                KeyNavigation.AfterItem
                        }
                        KeyNavigation.up: hostField
                        KeyNavigation.right: loginButton
                        KeyNavigation.down: pin
                    }
                    C.Button {
                        id: loginButton
                        text: qsTr("Sign in with PSN")
                        onClicked: stack.push(psnLoginDialogComponent, {login: true, callback: (id) => accountId.text = id})
                        visible: !Chiaki.settings.psnAccountId
                        KeyNavigation.priority: KeyNavigation.BeforeItem
                        KeyNavigation.up: hostField
                        KeyNavigation.left: accountId
                        KeyNavigation.right: lookupButton
                        KeyNavigation.down: pin
                    }
                    C.Button {
                        id: lookupButton
                        text: qsTr("Look up")
                        onClicked: stack.push(psnLoginDialogComponent, {login: false, callback: (id) => accountId.text = id})
                        visible: !Chiaki.settings.psnAccountId
                        KeyNavigation.up: hostField
                        KeyNavigation.priority: KeyNavigation.BeforeItem
                        KeyNavigation.left: loginButton
                        KeyNavigation.right: lookupButton
                        KeyNavigation.down: pin
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: qsTr("8-digit code from the console"); color: "#8c97a6"; font.pixelSize: 12 }
                C.TextField {
                    id: pin
                    validator: RegularExpressionValidator { regularExpression: /[0-9]{8}/ }
                    Layout.fillWidth: true
                    placeholderText: qsTr("12345678")
                    echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                    KeyNavigation.priority: {
                        if(readOnly)
                            KeyNavigation.BeforeItem
                        else
                            KeyNavigation.AfterItem
                    }
                    KeyNavigation.up: accountId
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: qsTr("Console PIN (only if you set one on the console)"); color: "#8c97a6"; font.pixelSize: 12 }
                C.TextField {
                    id: cpin
                    echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                    validator: RegularExpressionValidator { regularExpression: /^$|[0-9]{4}/ }
                    Layout.fillWidth: true
                    placeholderText: qsTr("leave empty if you don't use one")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: qsTr("Console"); color: "#8c97a6"; font.pixelSize: 12 }
                C.RadioButton {
                    id: ps5_0
                    property int target: 1000100
                    text: qsTr("PS5")
                    checked: ps5
                }
                Label {
                    visible: !showPs4
                    text: qsTr("Linking a PS4 instead?")
                    color: "#5aa9ff"
                    font.pixelSize: 13
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: showPs4 = true }
                }
                C.RadioButton {
                    id: ps4_8
                    visible: showPs4
                    property int target: 1000
                    text: qsTr("PS4 (system software 8.0 or newer)")
                    checked: !ps5
                }
                C.RadioButton {
                    id: ps4_75
                    visible: showPs4
                    property int target: 900
                    text: qsTr("PS4 (7.x)")
                }
                C.RadioButton {
                    id: ps4_7
                    visible: showPs4
                    property int target: 800
                    lastInFocusChain: true
                    text: qsTr("PS4 (older than 7.0)")
                }
            }
        }
        }

        ButtonGroup {
            id: consoleButtons
            buttons: [ps4_7, ps4_75, ps4_8, ps5_0]
        }

        Item {
            Dialog {
                id: logDialog
                parent: Overlay.overlay
                x: Math.round((root.width - width) / 2)
                y: Math.round((root.height - height) / 2)
                title: qsTr("Linking your console")
                modal: true
                // e11 dark card
                Overlay.modal: Rectangle { color: "#b307090c" }
                background: Rectangle { radius: 18; color: "#0b0e13"; border.color: "#1e2530"; border.width: 1 }
                closePolicy: Popup.NoAutoClose
                standardButtons: Dialog.Cancel
                Material.roundedScale: Material.MediumScale
                onOpened: logArea.forceActiveFocus(Qt.TabFocusReason)
                onClosed: stack.pop();

                Flickable {
                    id: logFlick
                    implicitWidth: 600
                    implicitHeight: 400
                    clip: true
                    contentWidth: logArea.contentWidth
                    contentHeight: logArea.contentHeight
                    flickableDirection: Flickable.AutoFlickIfNeeded
                    ScrollBar.vertical: ScrollBar {
                        id: logScrollbar
                        policy: ScrollBar.AlwaysOn
                        visible: logFlick.contentHeight > logFlick.implicitHeight
                    }

                    Label {
                        id: logArea
                        width: logFlick.width
                        wrapMode: TextEdit.Wrap
                        Keys.onReturnPressed: if (logDialog.standardButtons == Dialog.Close) logDialog.close()
                        Keys.onEscapePressed: logDialog.close()
                        Keys.onPressed: (event) => {
                            switch (event.key) {
                            case Qt.Key_Up:
                                if(logScrollbar.position > 0.001)
                                    logFlick.flick(0, 500);
                                event.accepted = true;
                                break;
                            case Qt.Key_Down:
                                if(logScrollbar.position < 1.0 - logScrollbar.size - 0.001)
                                    logFlick.flick(0, -500);
                                event.accepted = true;
                                break;
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: psnLoginDialogComponent
            PSNLoginDialog { }
        }
    }
}
