import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import "controls" as C

E11Dialog {
    id: dialog
    property alias text: label.text
    property var callback
    property var rejectCallback
    property string yesText: qsTr("Yes")
    property string noText: qsTr("Cancel")
    property bool newDialogOpen: false
    property Item restoreFocusItem
    onOpened: label.forceActiveFocus(Qt.TabFocusReason)
    onAccepted: {
        newDialogOpen = true;
        restoreFocus();
        callback();
    }
    onClosed: if(!newDialogOpen) { restoreFocus() }

    onRejected: {
        if(rejectCallback)
        {
            newDialogOpen = true;
            restoreFocus();
            rejectCallback();
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
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Item { Layout.fillWidth: true }
            C.E11Button {
                text: dialog.noText
                onClicked: dialog.reject()
            }
            C.E11Button {
                text: dialog.yesText
                primary: true
                onClicked: dialog.accept()
            }
        }
    }
}
