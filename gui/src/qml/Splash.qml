import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// e11 launch screen: headlight flash in the style of e11hours AI Game Studio,
// DeskCleaner colours. Shown once at start, then fades into the main view.
Rectangle {
    id: splash
    color: "#07090c"
    property int holdMs: 2600
    property real progress: 0
    signal finished()

    readonly property real s: Math.max(0.6, Math.min(1.4, Math.min(width / 1280, height / 800)))

    MouseArea { anchors.fill: parent; onClicked: splash.dismiss() }

    function dismiss() {
        if (fadeOut.running || !visible)
            return;
        fadeOut.start();
    }

    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -10 * splash.s
        spacing: 22 * splash.s

        Image {
            Layout.alignment: Qt.AlignHCenter
            source: "qrc:/icons/e11-wordmark.png"
            Layout.preferredHeight: 64 * splash.s
            Layout.preferredWidth: 64 * splash.s * sourceSize.width / Math.max(1, sourceSize.height)
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true
        }

        Item {
            id: car
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 660 * splash.s
            Layout.preferredHeight: Layout.preferredWidth * 500 / 1020
            Layout.topMargin: -18 * splash.s
            Layout.bottomMargin: -22 * splash.s
            property bool lit: true

            Image { anchors.fill: parent; source: "qrc:/icons/e11-car-off.png"; smooth: true; mipmap: true }
            Image { anchors.fill: parent; source: "qrc:/icons/e11-car-on.png"; smooth: true; mipmap: true; visible: car.lit }
            Image {
                visible: car.lit
                source: "qrc:/icons/e11-flare.png"
                width: car.width * 0.62; height: width / 2
                x: car.width * 0.588 - width / 2; y: car.height * 0.58 - height / 2
                smooth: true
            }
            Image {
                visible: car.lit
                source: "qrc:/icons/e11-flare.png"
                width: car.width * 0.40; height: width / 2
                x: car.width * 0.887 - width / 2; y: car.height * 0.51 - height / 2
                smooth: true
            }
            Timer { interval: 450; running: splash.visible; repeat: true; onTriggered: car.lit = !car.lit }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Your PlayStation 5.\nNow on your Mac.")
            color: "#eef2f7"
            font.pixelSize: 46 * splash.s
            font.weight: Font.Black
            font.letterSpacing: -0.5
            lineHeight: 1.05
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            Repeater {
                model: [ { t: qsTr("SMOOTH PLAY"), c: "#5aa9ff" }, { t: qsTr("ENHANCE"), c: "#5fd3a6" }, { t: qsTr("ZERO LAG"), c: "#f2c94c" } ]
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: chipText.implicitWidth + 26
                    implicitHeight: chipText.implicitHeight + 10
                    radius: height / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(modelData.c, 0.45)
                    Label {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData.t
                        color: modelData.c
                        font.pixelSize: 11 * Math.max(1, splash.s)
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.8
                        font.family: "Menlo"
                    }
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 420 * splash.s
            Layout.maximumWidth: 420 * splash.s
            Layout.topMargin: 4
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 6; height: 6; radius: 3; color: "#5aa9ff"
                    SequentialAnimation on opacity { loops: Animation.Infinite; running: splash.visible
                        NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
                }
                Label { text: qsTr("Getting ready"); color: "#eef2f7"; font.pixelSize: 12 * Math.max(1, splash.s); font.family: "Menlo"; Layout.fillWidth: true }
                Label { text: Math.round(splash.progress * 100) + "%"; color: "#eef2f7"; font.pixelSize: 12 * Math.max(1, splash.s); font.family: "Menlo" }
            }
            Rectangle {
                Layout.fillWidth: true; height: 3; radius: 2; color: "#1e2530"; clip: true
                Rectangle {
                    height: parent.height; radius: 2
                    width: parent.width * splash.progress
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#5aa9ff" } GradientStop { position: 1; color: "#b79bff" } }
                }
            }
        }
    }

    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: disclaimer.top; bottomMargin: 10 }
        text: qsTr("Tip: plug your controller in with USB-C for zero-lag input.")
        color: "#8c97a6"
        font.pixelSize: 11 * Math.max(1, splash.s)
        font.family: "Menlo"
    }
    Label {
        id: disclaimer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 10; leftMargin: 28; rightMargin: 28 }
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: qsTr("PlayStation and PS5 are trademarks of Sony Interactive Entertainment Inc. e11 Remote Play is an independent app and is not affiliated with or endorsed by Sony.")
        color: "#5c6675"
        font.pixelSize: 10 * Math.max(1, splash.s)
    }

    NumberAnimation on progress { from: 0; to: 1; duration: splash.holdMs; easing.type: Easing.OutCubic; running: true }
    Timer { interval: splash.holdMs + 150; running: true; onTriggered: splash.dismiss() }
    NumberAnimation { id: fadeOut; target: splash; property: "opacity"; to: 0; duration: 350
        onFinished: { splash.visible = false; splash.finished(); } }
}
