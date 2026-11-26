import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

TextField {
    id: tf
    property bool firstInFocusChain: false
    property bool lastInFocusChain: false
    property bool sendOutput: false
    readOnly: true

    // e11 look: plain dark field, hint text inside (no floating Material label)
    property string e11Hint: ""
    Component.onCompleted: { if (placeholderText !== "") { e11Hint = placeholderText; placeholderText = ""; } }
    onPlaceholderTextChanged: if (placeholderText !== "") { e11Hint = placeholderText; placeholderText = ""; }
    color: "#eef2f7"
    font.pixelSize: 15
    leftPadding: 14
    rightPadding: 14
    topPadding: 12
    bottomPadding: 12
    verticalAlignment: TextInput.AlignVCenter
    selectionColor: "#5aa9ff"
    background: Rectangle {
        implicitHeight: 46
        implicitWidth: 200
        radius: 12
        color: "#0e1218"
        border.width: tf.activeFocus ? 1.5 : 1
        border.color: tf.activeFocus ? "#5aa9ff" : "#2a3340"
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: tf.leftPadding
        width: tf.width - tf.leftPadding - tf.rightPadding
        elide: Text.ElideRight
        text: tf.e11Hint
        visible: tf.text === "" && tf.preeditText === ""
        color: "#5c6675"
        font.pixelSize: 15
    }

    onActiveFocusChanged: {
        if (!activeFocus)
            readOnly = true;
    }

    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Up:
            if (!firstInFocusChain && readOnly) {
                let item = nextItemInFocusChain(false);
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
                if(!sendOutput)
                    event.accepted = true;
            }
            break;
        case Qt.Key_Down:
            if (!lastInFocusChain && readOnly) {
                let item = nextItemInFocusChain();
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
                if(!sendOutput)
                    event.accepted = true;
            }
            break;
        case Qt.Key_Return:
            if (readOnly) {
                readOnly = false;
                Qt.inputMethod.show();
                event.accepted = true;
            } else {
                readOnly = true;
            }
            break;
        case Qt.Key_Escape:
            if (!readOnly) {
                readOnly = true;
                editingFinished();
                event.accepted = true;
            }
            break;
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: parent.readOnly
        onClicked: {
            parent.forceActiveFocus(Qt.TabFocusReason);
            parent.readOnly = false;
            Qt.inputMethod.show();
        }
    }
}
