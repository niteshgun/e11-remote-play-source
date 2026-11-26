import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Button {
    property bool firstInFocusChain: false
    property bool lastInFocusChain: false
    property bool sendOutput: false

    // e11: outlined buttons everywhere (no filled Material buttons)
    hoverEnabled: true
    background: Rectangle {
        implicitHeight: 40
        implicitWidth: 96
        radius: 12
        color: parent.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
        border.width: parent.visualFocus ? 1.5 : 1
        border.color: parent.visualFocus ? "#5aa9ff" : "#2a3340"
    }
    contentItem: Label {
        text: parent.text
        color: parent.enabled ? "#eef2f7" : "#5c6675"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    Component.onDestruction: {
        if (visualFocus) {
            let item = nextItemInFocusChain();
            if (item)
                item.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Up:
            if (!firstInFocusChain) {
                let item = nextItemInFocusChain(false);
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
                if(!sendOutput)
                    event.accepted = true;
            }
            break;
        case Qt.Key_Down:
            if (!lastInFocusChain) {
                let item = nextItemInFocusChain();
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
                if(!sendOutput)
                    event.accepted = true;
            }
            break;
        case Qt.Key_Return:
            if (visualFocus) {
                clicked();
            }
            event.accepted = true;
            break;
        }
    }
}
