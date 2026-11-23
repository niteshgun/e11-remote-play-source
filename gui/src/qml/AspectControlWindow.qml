// e11: floating, draggable aspect-ratio control shown while streaming.
import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window

import org.streetpea.chiaking

Window {
    id: aspectWindow

    property bool shown: false
    property var hostWindow: null
    property bool collapsed: false

    // Remember where the user left it (global screen position) and whether it was collapsed
    Settings {
        id: aspectPrefs
        category: "e11_aspect_control"
        property int posX: -1
        property int posY: -1
        property bool collapsed: false
    }

    visible: shown
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    modality: Qt.NonModal
    width: panel.implicitWidth
    height: panel.implicitHeight

    Component.onCompleted: collapsed = aspectPrefs.collapsed

    function placeDefault() {
        if (aspectPrefs.posX >= 0 && aspectPrefs.posY >= 0) {
            x = aspectPrefs.posX;
            y = aspectPrefs.posY;
        } else if (hostWindow) {
            // top-right corner of the stream, out of the way of most game HUDs' centre
            x = hostWindow.x + hostWindow.width - width - 24;
            y = hostWindow.y + 48;
        }
    }

    onVisibleChanged: if (visible) placeDefault()
    // The system drag (startSystemMove) owns the mouse, so save on every position change
    onXChanged: if (visible) aspectPrefs.posX = x
    onYChanged: if (visible) aspectPrefs.posY = y
    onCollapsedChanged: aspectPrefs.collapsed = collapsed

    function setMode(mode) {
        if (mode === ChiakiWindow.VideoMode.Zoom)
            Chiaki.window.ZoomFactor = -1; // auto: fill the screen, keep the shape
        Chiaki.window.videoMode = mode;
    }

    Rectangle {
        id: panel
        implicitWidth: row.implicitWidth + 16
        implicitHeight: 44
        radius: 22
        color: Qt.rgba(0.08, 0.08, 0.10, 0.82)
        border.color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1

        RowLayout {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 4

            // Drag grip: press and drag to move the panel anywhere
            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 32
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: 3
                    Repeater {
                        model: 6
                        Rectangle { width: 3; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.55) }
                    }
                }
                MouseArea {
                    id: dragArea
                    property bool dragging: false
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    onPressed: {
                        dragging = true;
                        aspectWindow.startSystemMove();
                    }
                    onReleased: {
                        dragging = false;
                        aspectPrefs.posX = aspectWindow.x;
                        aspectPrefs.posY = aspectWindow.y;
                    }
                    onCanceled: {
                        dragging = false;
                        aspectPrefs.posX = aspectWindow.x;
                        aspectPrefs.posY = aspectWindow.y;
                    }
                }
            }

            Repeater {
                model: aspectWindow.collapsed ? [] : [
                    { label: qsTr("Fit"),     tip: qsTr("Original 16:9 shape, bars if the screen is taller"), mode: ChiakiWindow.VideoMode.Normal },
                    { label: qsTr("Fill"),    tip: qsTr("Fill the screen, keep the shape (crops edges)"),     mode: ChiakiWindow.VideoMode.Zoom },
                    { label: qsTr("Stretch"), tip: qsTr("Fill the screen by stretching the picture"),          mode: ChiakiWindow.VideoMode.Stretch }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: Chiaki.window.videoMode === modelData.mode
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: label.implicitWidth + 22
                    radius: 15
                    color: selected ? Material.accent : (hover.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent")
                    Label {
                        id: label
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 13
                        font.bold: selected
                        color: "white"
                    }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: aspectWindow.setMode(modelData.mode)
                    }
                    ToolTip.visible: hover.containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: modelData.tip
                }
            }

            // Collapse / expand
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: collapseHover.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                Label {
                    anchors.centerIn: parent
                    text: aspectWindow.collapsed ? "⤢" : "–"
                    color: "white"
                    font.pixelSize: 15
                }
                MouseArea {
                    id: collapseHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: aspectWindow.collapsed = !aspectWindow.collapsed
                }
            }
        }
    }
}
