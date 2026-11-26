// e11 (Mac): PSN sign-in happens in a native Apple window (WebKit). This panel sits in the dialog
// while that window is open and hands the result back. Nothing to copy or paste.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import org.streetpea.chiaking

Rectangle {
    id: panel
    signal redirect(var url)
    signal cancelled()
    signal addConsole()
    signal done()
    // sony: Sony window open · closed: window closed before finishing
    // working: checking with Sony · ok: signed in · failed: Sony said no
    property string phase: "sony"
    readonly property bool waiting: phase === "sony"
    color: "#07090c"

    function start() {
        phase = "sony";
        Chiaki.startMacPsnSignIn();
    }

    Connections {
        target: Chiaki
        enabled: panel.visible
        function onMacPsnRedirect(url) {
            panel.phase = "working";
            panel.redirect(url);
        }
        function onMacPsnSignInClosed() {
            if (panel.phase === "sony")
                panel.phase = "closed";
        }
    }

    MouseArea { anchors.fill: parent }

    component PanelButton: AbstractButton {
        id: pb
        property bool primary: false
        property color tint: "#5aa9ff"
        implicitHeight: 44
        implicitWidth: pbLabel.implicitWidth + 40
        hoverEnabled: true
        background: Rectangle {
            radius: 12
            color: pb.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
            border.width: pb.primary ? 1.5 : 1
            border.color: pb.primary ? pb.tint : "#2a3340"
        }
        contentItem: Label {
            id: pbLabel
            text: pb.text
            color: pb.primary ? pb.tint : "#b3bdc9"
            font.pixelSize: 15
            font.bold: pb.primary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        spacing: 16

        RowLayout {
            spacing: 14
            BusyIndicator {
                visible: panel.phase === "working"
                running: visible
                implicitWidth: 30; implicitHeight: 30
            }
            Label {
                Layout.fillWidth: true
                text: panel.phase === "ok" ? qsTr("Successfully signed in")
                    : panel.phase === "failed" ? qsTr("Couldn't sign in")
                    : panel.phase === "working" ? qsTr("Signing in…")
                    : panel.phase === "closed" ? qsTr("Sign in with PlayStation Network")
                    : qsTr("Finish signing in in the Sony window")
                color: panel.phase === "ok" ? "#5fd3a6" : "#eef2f7"
                font.pixelSize: 26
                font.weight: Font.Black
                wrapMode: Text.WordWrap
            }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: "#b3bdc9"
            font.pixelSize: 15
            lineHeight: 1.3
            text: panel.phase === "ok" ? qsTr("You're connected to PlayStation Network. Next, add your PS5 so you can play.")
                : panel.phase === "failed" ? qsTr("Sony didn't accept the sign-in. Wait a minute and try again.")
                : panel.phase === "working" ? qsTr("Connecting your PlayStation account…")
                : panel.phase === "closed" ? qsTr("The sign-in window was closed. Open it again to continue.")
                : qsTr("A secure Sony sign-in window is open. Sign in there and e11 continues by itself. Your password goes straight to Sony; e11 only keeps a sign-in token on this Mac.")
        }
        RowLayout {
            spacing: 10
            visible: panel.phase !== "working"
            PanelButton {
                primary: true
                tint: panel.phase === "ok" ? "#5fd3a6" : "#5aa9ff"
                text: panel.phase === "ok" ? qsTr("Add a console")
                    : panel.phase === "failed" ? qsTr("Try again")
                    : panel.waiting ? qsTr("Show sign-in window") : qsTr("Open sign-in window")
                onClicked: panel.phase === "ok" ? panel.addConsole() : panel.start()
            }
            PanelButton {
                text: panel.phase === "ok" ? qsTr("Done") : qsTr("Cancel")
                onClicked: {
                    if (panel.phase === "ok") { panel.done(); return; }
                    Chiaki.closeMacPsnSignIn();
                    panel.phase = "closed";
                    panel.cancelled();
                }
            }
        }
    }
}
