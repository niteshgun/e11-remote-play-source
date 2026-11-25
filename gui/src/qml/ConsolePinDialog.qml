import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking

import "controls" as C

DialogView {
    property var consoleIndex
    title: qsTr("Console PIN")
    buttonText: qsTr("Save")
    buttonEnabled: pin.acceptableInput
    onAccepted: {
        Chiaki.setConsolePin(consoleIndex, pin.text.trim());
        stack.pop();
    }
    Item {
        ColumnLayout {
            width: Math.min(parent.width - 80, 560)
            x: (parent.width - width) / 2
            y: 32
            spacing: 8
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: "#b3bdc9"
                font.pixelSize: 13
                Layout.bottomMargin: 10
                text: qsTr("If your console asks for a 4-digit Remote Play PIN when you connect, save it here so e11 enters it for you.")
            }
            Label { text: qsTr("Console PIN (4 digits)"); color: "#8c97a6"; font.pixelSize: 12 }
            TextField {
                id: pin
                validator: RegularExpressionValidator { regularExpression: /[0-9]{4}/ }
                echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                Layout.fillWidth: true
                placeholderText: qsTr("1234")
            }
        }
    }
}
