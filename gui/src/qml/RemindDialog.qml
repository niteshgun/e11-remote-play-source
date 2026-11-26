import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import "controls" as C

import org.streetpea.chiaking

E11Dialog {
    id: dialog
    property alias text: label.text
    property var remotePlay
    property var callback
    property bool newDialogOpen: false
    property Item restoreFocusItem
    onOpened: label.forceActiveFocus(Qt.TabFocusReason)
    onAccepted: {
        newDialogOpen = true;
        restoreFocus();
        callback();
    }
    onRejected: {
        if(dialog.remotePlay)
            Chiaki.settings.remotePlayAsk = false;
        else
            Chiaki.settings.addSteamShortcutAsk = false;
    }
    onClosed: {
        if(newDialogOpen)
            return;
        restoreFocus();
        if(!remotePlay && Chiaki.settings.remotePlayAsk)
        {
            if(!Chiaki.settings.psnRefreshToken || !Chiaki.settings.psnAuthToken || !Chiaki.settings.psnAuthTokenExpiry || !Chiaki.settings.psnAccountId)
                root.showRemindDialog(qsTr("Play from anywhere"), qsTr("Sign in with PlayStation Network to link your PS5 automatically and play outside your home network. A secure Sony window opens and e11 continues by itself."), true, () => root.showPSNTokenDialog(false));
            else
                Chiaki.settings.remotePlayAsk = false;
        }
    }

    function restoreFocus() {
        if (restoreFocusItem)
            restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
        label.focus = false;
    }

    ColumnLayout {
        width: parent.width
        spacing: 22

        Label {
            id: label
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: "#b3bdc9"
            font.pixelSize: 14
            lineHeight: 1.3
            Keys.onEscapePressed: dialog.reject()
            Keys.onReturnPressed: dialog.accept()
            Keys.onYesPressed: dialog.close()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            C.E11Button {
                text: dialog.remotePlay ? qsTr("Don't ask again") : qsTr("No thanks")
                onClicked: dialog.reject()
            }
            Item { Layout.fillWidth: true }
            C.E11Button {
                text: qsTr("Later")
                onClicked: dialog.close()
            }
            C.E11Button {
                text: dialog.remotePlay ? qsTr("Sign in") : qsTr("Yes")
                primary: true
                onClicked: dialog.accept()
            }
        }
    }
}
