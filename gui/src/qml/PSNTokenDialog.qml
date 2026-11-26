import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking

import "controls" as C

DialogView {
    id: dialog
    property var psnurl
    property var expired
    property bool closing: false
    title: {
        if(expired)
            qsTr("Sign in again with PlayStation Network")
        else
            qsTr("Sign in with PlayStation Network")
    }
    buttonText: qsTr("Setup")
    buttonEnabled: url.text.trim()
    buttonVisible: false
    onAccepted: dialog.startAuth(url.text.trim())
    property bool authStarted: false
    function startAuth(u) {
        if (authStarted)
            return;
        authStarted = true;
        clipWatch.running = false;
        logArea.text = "";
        // Mac: the result shows in the sign-in panel itself (no extra pop-up)
        const onMac = Qt.platform.os === "osx";
        if (onMac)
            macPanel.phase = "working";
        else {
            logDialog.phase = "working";
            logDialog.open()
        }
        Chiaki.initPsnAuth(u, function(msg, ok, done) {
            if(ok)
                Chiaki.settings.remotePlayAsk = false;
            logArea.text += msg + "\n";
            if (done) {
                if (onMac)
                    macPanel.phase = ok ? "ok" : "failed";
                else
                    logDialog.phase = ok ? "ok" : "failed";
                if (!ok)
                    dialog.authStarted = false;
            }
        });
    }
    StackView.onActivated: {
        if (Qt.platform.os === "osx") {
            macPanel.start();
            return;
        }
        Chiaki.settings.remotePlayAsk = true;
        nativeTokenForm.visible = true;
        nativeTokenForm.forceActiveFocus(Qt.TabFocusReason);
        // e11: on Mac the sign-in opens inside the app and the result is picked up
        // automatically (no copy/paste). Linux keeps the external browser.
        if(Qt.platform.os == "linux")
            extBrowserButton.clicked();
    }
    function close() {
        Chiaki.closeMacPsnSignIn();
        if(webView.web)
        {
            dialog.closing = true;
            if(Chiaki.settings.remotePlayAsk)
                reloadTimer.start();
            else
                cacheClearTimer.start();
        }
        else
            root.closeDialog();
    }

    Item {
        MacSignInPanel {
            id: macPanel
            anchors.fill: parent
            z: 100
            visible: Qt.platform.os === "osx"
            onRedirect: (u) => dialog.startAuth(u)
            onCancelled: dialog.close()
            onDone: root.showMainView()
            onAddConsole: { root.showMainView(); root.showManualHostDialog(); }
        }
        Item {
            id: nativeTokenForm
            visible: false
            Keys.onPressed: (event) => {
                if (event.modifiers)
                    return;
                switch (event.key) {
                case Qt.Key_PageUp:
                    reloadButton.clicked();
                    event.accepted = true;
                    break;
                case Qt.Key_PageDown:
                    extBrowserButton.clicked();
                    event.accepted = true;
                    break;
                }
            }
            anchors.fill: parent
            ToolBar {
                id: psnTokenToolbar
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: 80

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                    }
                    Button {
                        id: reloadButton
                        Layout.fillHeight: true
                        Layout.preferredWidth: 350
                        flat: true
                        text: qsTr("Start over")
                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: "qrc:/icons/l1.svg"
                        }
                        onClicked: reloadTimer.start()
                        Material.roundedScale: Material.SmallScale
                        focusPolicy: Qt.NoFocus
                    }
                    ProgressBar {
                        id: browserProgresss
                        Layout.fillHeight: true
                        Layout.preferredWidth: 300
                        from: 0
                        to: 100
                        value: webView.web.loadProgress
                        Material.roundedScale: Material.SmallScale
                        focusPolicy: Qt.NoFocus
                    }
                    Button {
                        id: extBrowserButton
                        Layout.fillHeight: true
                        Layout.preferredWidth: 300
                        flat: true
                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: "qrc:/icons/r1.svg"
                        }
                        focusPolicy: Qt.NoFocus
                        text: qsTr("Use my browser instead")
                        onClicked: {
                            nativeTokenForm.visible = false;
                            psnTokenToolbar.visible = false;
                            nativeErrorGrid.visible = false;
                            webView.visible = false;
                            linkgrid.visible = true;
                            dialog.buttonVisible = true;
                            psnurl = Chiaki.openPsnLink();
                            if(psnurl)
                            {
                                openurl.selectAll();
                                openurl.copy();
                            }
                            pasteUrl.forceActiveFocus(Qt.TabFocusReason);
                            clipWatch.running = true;
                        }
                    }
                }
            }
            // e11: when the browser sign-in finishes, the user only copies the final
            // address and comes back; we read the clipboard once when the app is
            // active again (no polling, so no repeated paste prompts) and continue.
            TextField { id: clipProbe; visible: false }
            Item {
                id: clipWatch
                property bool running: false
                function check() {
                    if (!running)
                        return;
                    clipProbe.text = "";
                    clipProbe.paste();
                    const t = clipProbe.text.trim();
                    if (t && Chiaki.checkPsnRedirectURL(t)) {
                        url.text = t;
                        dialog.startAuth(t);
                    }
                }
                Connections {
                    target: Qt.application
                    function onStateChanged() {
                        if (Qt.application.state === Qt.ApplicationActive)
                            clipWatch.check();
                    }
                }
            }
            Timer {
                id: reloadTimer
                interval: 0
                running: false
                onTriggered: {
                    Chiaki.clearCookies(webView.web.profile);
                    webView.web.profile.clearHttpCache();
                }
            }

            Timer {
                id: cacheClearTimer
                interval: 0
                running: false
                onTriggered: {
                    webView.web.profile.clearHttpCache();
                }
            }

            GridLayout {
                id: nativeErrorGrid
                visible: false
                anchors {
                    top: psnTokenToolbar.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 50
                }
                columns: 2
                rowSpacing: 10
                columnSpacing: 20
                Label {
                    id: nativeErrorHeader
                    text: "Retrieving PSN account ID failed with error: "
                    Layout.fillHeight: true
                    Layout.preferredWidth: 400
                    Layout.leftMargin: 20
                }

                Label {
                    id: nativeErrorLabel
                    Layout.fillHeight: true
                    Layout.preferredWidth: 400
                    Layout.leftMargin: 20
                }

                Label {
                    id: retryButton
                    text: "Retry process"
                    Layout.fillHeight: true
                    Layout.preferredWidth: 300
                    Layout.leftMargin: 20
                }
                C.Button {
                    firstInFocusChain: true
                    lastInFocusChain: true
                    text: "Retry"
                    onClicked: {
                        nativeErrorGrid.visible = false;
                        nativeErrorLabel.text = "";
                        nativeErrorLabel.visible = false;
                        webView.visible = true;
                        webView.web.url = Chiaki.psnLoginUrl();
                    }
                    Layout.preferredWidth: 200
                    Layout.fillHeight: true
                    Layout.leftMargin: 20
                }
            }
            Item {
                id: webView
                property Item web: null
                anchors {
                    top: psnTokenToolbar.bottom
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                    leftMargin: 10
                    rightMargin: 10
                }
                property bool started: false
                Component.onCompleted: {
                    if (Qt.platform.os === "osx")
                        return; // e11: Mac signs in with the native Apple window (MacSignInPanel)
                    try {
                        web = Qt.createQmlObject("
                        import QtWebEngine
                        import QtQuick.Controls
                        import org.streetpea.chiaking
                        WebEngineView {
                            profile {
                                offTheRecord: false
                                storageName: 'psn-token'
                                onClearHttpCacheCompleted: {
                                    if(dialog.closing)
                                        root.closeDialog();
                                    else
                                        webView.web.reload();
                                }
                            }
                            settings {
                                // Load larger touch icons
                                touchIconsEnabled: true
                                localContentCanAccessRemoteUrls: true
                            }

                            onContextMenuRequested: (request) => request.accepted = true;
                            onNavigationRequested: (request) => {
                                if (Chiaki.checkPsnRedirectURL(request.url)) {
                                    dialog.startAuth(request.url);
                                    request.reject();
                                }
                                else
                                    request.accept();
                            }
                            onCertificateError: console.error(error.description);
                        }", webView, "webView");
                        Chiaki.setWebEngineHints(web.profile);
                        web.url = Chiaki.psnLoginUrl();
                        web.anchors.fill = webView;
                    } catch (error) {
                        console.error('Create webengine view failed with error:' + error);
                        extBrowserButton.clicked();
                    }
                }
            }
        }
        GridLayout {
            id: linkgrid
            visible: false
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                topMargin: 50
            }
            columns: 2
            rowSpacing: 10
            columnSpacing: 20

            Label {
                text: qsTr("Open Web Browser with copied URL")
                visible: psnurl
            }

            TextField {
                id: openurl
                text: psnurl
                echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                visible: false
                Layout.preferredWidth: 400
            }

            C.Button {
                id: copyUrl
                text: qsTr("Click to Re-Copy URL")
                onClicked: {
                    openurl.selectAll()
                    openurl.copy()
                }
                KeyNavigation.priority: KeyNavigation.BeforeItem
                KeyNavigation.up: copyUrl
                KeyNavigation.down: url
                visible: psnurl
            }

            Label {
                Layout.maximumWidth: 420
                wrapMode: Text.WordWrap
                text: qsTr("Sign in in your browser. When it shows a blank page, copy its address. e11 picks it up by itself.")
            }

            TextField {
                id: url
                echoMode: Chiaki.settings.streamerMode ? TextInput.Password : TextInput.Normal
                Layout.preferredWidth: 400
                KeyNavigation.priority: {
                    if(readOnly)
                        KeyNavigation.BeforeItem
                    else
                        KeyNavigation.AfterItem
                }
                KeyNavigation.up: {
                    if(psnurl)
                        copyUrl
                    else
                        url
                }
                KeyNavigation.down: url
                KeyNavigation.right: pasteUrl
                C.Button {
                    id: pasteUrl
                    text: qsTr("Click to Paste URL")
                    anchors {
                        left: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                    }
                    onClicked: url.paste()
                    KeyNavigation.priority: KeyNavigation.BeforeItem
                    KeyNavigation.left: url
                    KeyNavigation.up: {
                        if(psnurl)
                            copyUrl
                        else
                            pasteUrl
                    }
                    KeyNavigation.down: pasteUrl
                }
            }
        }

        Item {
            E11Dialog {
                id: logDialog
                // working -> ok | failed
                property string phase: "working"
                property bool addConsoleNext: false
                title: phase === "ok" ? qsTr("Successfully signed in")
                     : phase === "failed" ? qsTr("Couldn't sign in")
                     : qsTr("Signing in…")
                closePolicy: Popup.NoAutoClose
                onOpened: (phase === "ok" ? addBtn : doneBtn).forceActiveFocus(Qt.TabFocusReason)
                onPhaseChanged: if (phase === "ok") addBtn.forceActiveFocus(Qt.TabFocusReason)
                onClosed: {
                    root.showMainView();
                    if (addConsoleNext) {
                        addConsoleNext = false;
                        root.showManualHostDialog();
                    }
                }

                ColumnLayout {
                    width: parent.width
                    spacing: 18

                    RowLayout {
                        visible: logDialog.phase === "working"
                        spacing: 14
                        BusyIndicator { running: logDialog.phase === "working"; implicitWidth: 28; implicitHeight: 28; Material.accent: "#5aa9ff" }
                        Label { text: qsTr("Connecting your PlayStation account…"); color: "#8c97a6"; font.pixelSize: 15 }
                    }

                    Label {
                        visible: logDialog.phase === "ok"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: "#8c97a6"
                        font.pixelSize: 15
                        text: qsTr("You're connected to PlayStation Network. Next, add your PS5 so you can play.")
                    }

                    Label {
                        visible: logDialog.phase === "failed"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: "#8c97a6"
                        font.pixelSize: 15
                        text: qsTr("Sony didn't accept the sign-in. Wait a minute and try again.")
                    }

                    // Raw messages kept for troubleshooting, hidden from normal view
                    Label { id: logArea; visible: false }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Item { Layout.fillWidth: true }
                        C.E11Button {
                            id: doneBtn
                            text: logDialog.phase === "working" ? qsTr("Cancel") : qsTr("Done")
                            onClicked: logDialog.close()
                        }
                        C.E11Button {
                            id: addBtn
                            visible: logDialog.phase === "ok"
                            primary: true
                            tint: "#5fd3a6"
                            text: qsTr("Add a console")
                            onClicked: { logDialog.addConsoleNext = true; logDialog.close(); }
                        }
                    }
                }
            }
        }
    }
}