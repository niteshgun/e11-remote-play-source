// e11: base for every pop-up question (dark card, plain title, outlined buttons; no controller-button icons)
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

Dialog {
    id: d
    // Centred on the window. (Binding x/y/width to Overlay.overlay left some pop-ups with no size:
    // see-through and stuck in the top-left corner.)
    anchors.centerIn: parent
    width: 520
    Component.onCompleted: if (Overlay.overlay) parent = Overlay.overlay
    onAboutToShow: if (Overlay.overlay && parent !== Overlay.overlay) parent = Overlay.overlay
    modal: true
    padding: 28
    topPadding: 8
    Overlay.modal: Rectangle { color: "#b307090c" }
    background: Rectangle {
        radius: 18
        color: "#0b0e13"
        border.color: "#1e2530"
        border.width: 1
    }
    header: Label {
        text: d.title
        visible: text !== ""
        leftPadding: 28
        rightPadding: 28
        topPadding: 26
        bottomPadding: 6
        wrapMode: Text.WordWrap
        color: "#eef2f7"
        font.pixelSize: 22
        font.weight: Font.Black
    }
}
