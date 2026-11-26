import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

ComboBox {
    id: cb
    property bool firstInFocusChain: false
    property bool lastInFocusChain: false
    // e11 look: same dark field as text boxes
    font.pixelSize: 15
    Material.foreground: "#eef2f7"
    background: Rectangle {
        implicitHeight: 46
        implicitWidth: 200
        radius: 12
        color: cb.hovered ? "#121721" : "#0e1218"
        border.width: cb.visualFocus || cb.popup.visible ? 1.5 : 1
        border.color: cb.visualFocus || cb.popup.visible ? "#5aa9ff" : "#2a3340"
    }
    implicitContentWidthPolicy: ComboBox.WidestText

    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Up:
            if (!popup.visible) {
                let item = nextItemInFocusChain(false);
                if (!firstInFocusChain && item)
                    item.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            }
            break;
        case Qt.Key_Down:
            if (!popup.visible) {
                let item = nextItemInFocusChain();
                if (!lastInFocusChain && item)
                    item.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            }
            break;
        case Qt.Key_Return:
            if (popup.visible) {
                activated(highlightedIndex);
                popup.close();
            } else {
                popup.open();
            }
            event.accepted = true;
            break;
        }
    }

    Keys.onReleased: (event) => {
        if (event.key == Qt.Key_Return)
            event.accepted = true;
    }
}
