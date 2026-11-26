// e11: outlined button used in pop-ups. primary = blue outline + blue text; otherwise grey outline.
import QtQuick
import QtQuick.Controls

AbstractButton {
    id: b
    property bool primary: false
    property color tint: "#5aa9ff"
    implicitHeight: 42
    implicitWidth: Math.max(96, lbl.implicitWidth + 36)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Keys.onReturnPressed: clicked()
    background: Rectangle {
        radius: 12
        color: b.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
        border.width: b.primary || b.visualFocus ? 1.5 : 1
        border.color: b.primary || b.visualFocus ? b.tint : "#2a3340"
    }
    contentItem: Label {
        id: lbl
        text: b.text
        color: b.primary ? b.tint : "#b3bdc9"
        font.pixelSize: 15
        font.bold: b.primary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
