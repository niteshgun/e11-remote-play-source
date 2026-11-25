import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking

import "controls" as C

DialogView {
    title: qsTr("Add a console")
    buttonText: qsTr("Add")
    buttonEnabled: hostField.text.trim() && (consoleCombo.model[consoleCombo.currentIndex].index != -1)
    onAccepted: {
        Chiaki.addManualHost(consoleCombo.model[consoleCombo.currentIndex].index, hostField.text.trim());
        close();
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
                text: qsTr("Only needed if your console doesn't show up by itself. Find its address on the PS5: Settings › Network › Connection Status › View Connection Status (IPv4 address).")
            }
            Label { text: qsTr("Console address"); color: "#8c97a6"; font.pixelSize: 12 }

            C.TextField {
                id: hostField
                echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                Layout.fillWidth: true
                firstInFocusChain: true
                placeholderText: qsTr("for example 192.168.1.20")
            }

            Label { text: qsTr("Which console is it?"); color: "#8c97a6"; font.pixelSize: 12; Layout.topMargin: 12 }

            C.ComboBox {
                id: consoleCombo
                Layout.fillWidth: true
                lastInFocusChain: true
                textRole: "name"
                model: {
                    let m = [];
                    if(Chiaki.settings.registeredHosts.length > 0)
                    {
                        m.push({
                            name: qsTr("Choose…"),
                            index: -1,
                        });
                    }
                    let i = 0;
                    for (; i < Chiaki.settings.registeredHosts.length; ++i) {
                        let host = Chiaki.settings.registeredHosts[i];
                        m.push({
                            name: "%1 (%2)".arg(Chiaki.settings.streamerMode ? "hidden" : host.mac).arg(host.name),
                            index: i,
                        });
                    }
                    m.push({
                        name: qsTr("A new console (link it when I connect)"),
                        index: i,
                    });
                    return m;
                }
            }
        }
    }
}
