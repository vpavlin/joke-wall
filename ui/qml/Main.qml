import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 640
    height: 720
    color: "#0f1117"

    readonly property color colBg:      "#0f1117"
    readonly property color colSurface: "#1a1d27"
    readonly property color colBorder:  "#2d3148"
    readonly property color colPrimary: "#7c6ef5"
    readonly property color colSuccess: "#3ecf8e"
    readonly property color colWarning: "#f5a623"
    readonly property color colError:   "#e05252"
    readonly property color colText:    "#e8e9f0"
    readonly property color colMuted:   "#6b7280"
    readonly property int   radius:     10

    // ── Toast ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: toast
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 20 }
        width: toastLabel.implicitWidth + 32; height: 38; radius: 19
        color: toastSuccess ? root.colSuccess : root.colError
        opacity: 0; z: 10
        property bool toastSuccess: true
        Label { id: toastLabel; anchors.centerIn: parent; color: "#fff"; font.pixelSize: 13 }
        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 180 }
            PauseAnimation  { duration: 2800 }
            NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 350 }
        }
        function show(msg, ok) { toastSuccess = ok; toastLabel.text = msg; toastAnim.restart() }
    }

    Connections {
        target: backend
        function onTxSuccess(op, hash) {
            toast.show("✓ " + op + " — " + hash.substring(0, 10) + "…", true)
            if (op === "submit_joke") submitContent.text = ""
            if (op === "create_session") {
                // Auto-add the new session based on admin PDA (derived on-chain)
                backend.refreshState()
            }
        }
        function onTxError(op, err) { toast.show("✗ " + err, false) }
    }

    // ── Root layout: sessions sidebar + main area ─────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Sessions sidebar ──────────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 160
            Layout.fillHeight: true
            color: root.colSurface
            border.color: root.colBorder

            ColumnLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 6

                Label {
                    text: "SESSIONS"
                    color: root.colMuted
                    font { pixelSize: 10; capitalization: Font.AllUppercase; letterSpacing: 1 }
                }

                Repeater {
                    model: backend.sessions
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: sessionCol.implicitHeight + 12
                        radius: 6
                        color: modelData.pda === backend.currentSessionPda
                               ? root.colPrimary + "33" : "transparent"
                        border.color: modelData.pda === backend.currentSessionPda
                               ? root.colPrimary : root.colBorder

                        ColumnLayout {
                            id: sessionCol
                            anchors { fill: parent; margins: 6 }
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: root.colText
                                    font { pixelSize: 11; bold: modelData.pda === backend.currentSessionPda }
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    width: 6; height: 6; radius: 3
                                    color: modelData.is_active ? root.colSuccess : root.colMuted
                                }
                            }
                            Label {
                                text: modelData.joke_count + " jokes"
                                color: root.colMuted
                                font.pixelSize: 9
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: backend.selectSession(modelData.pda)
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }

                // Add session row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    TextField {
                        id: newSessionPda
                        Layout.fillWidth: true
                        placeholderText: "Session PDA…"
                        placeholderTextColor: root.colMuted
                        color: root.colText
                        font.pixelSize: 10
                        leftPadding: 6; rightPadding: 6
                        background: Rectangle { radius: 5; color: root.colBg; border.color: root.colBorder }
                    }
                    Rectangle {
                        width: 24; height: 24; radius: 5
                        color: newSessionPda.text !== "" ? root.colPrimary : root.colBorder
                        Label { anchors.centerIn: parent; text: "+"; color: "#fff"; font.pixelSize: 14 }
                        MouseArea {
                            anchors.fill: parent
                            enabled: newSessionPda.text !== ""
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                backend.addSession(newSessionPda.text.trim(), "")
                                newSessionPda.text = ""
                            }
                        }
                    }
                }

                Label {
                    visible: backend.sessions.length === 0
                    text: "No sessions.\nPaste a PDA above."
                    color: root.colMuted
                    font { pixelSize: 10; italic: true }
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item { Layout.fillHeight: true }

                // Status / busy indicator
                RowLayout {
                    spacing: 4
                    BusyIndicator {
                        width: 16; height: 16
                        running: backend.busy || backend.polling
                        visible: backend.busy || backend.polling
                        palette.dark: root.colPrimary
                    }
                    Label {
                        text: backend.busy    ? "Submitting…"
                            : backend.polling ? "Fetching…"
                            : backend.lastError !== "" ? "⚠"
                            : "●"
                        color: backend.lastError !== "" ? root.colError : root.colMuted
                        font.pixelSize: 10
                    }
                }
            }
        }

        // ── Main area ─────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                height: 48
                color: root.colSurface
                border.color: root.colBorder

                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    Label {
                        text: "🎭 JokeWall"
                        color: root.colPrimary
                        font { pixelSize: 18; bold: true }
                    }
                    Label {
                        text: backend.currentSessionPda !== ""
                              ? (backend.sessionExists ? backend.description : "No session at this PDA")
                              : "Select or add a session →"
                        color: backend.sessionExists ? root.colText : root.colMuted
                        font { pixelSize: 12; italic: !backend.sessionExists }
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        width: statusLabel.implicitWidth + 12; height: 22; radius: 11
                        color: backend.isActive ? root.colSuccess + "22" : root.colError + "22"
                        border.color: backend.isActive ? root.colSuccess + "88" : root.colError + "88"
                        visible: backend.sessionExists
                        Label {
                            id: statusLabel
                            anchors.centerIn: parent
                            text: backend.isActive ? "OPEN" : "CLOSED"
                            color: backend.isActive ? root.colSuccess : root.colError
                            font { pixelSize: 10; bold: true }
                        }
                    }
                }
            }

            // Tab bar
            Rectangle {
                Layout.fillWidth: true
                height: 36
                color: root.colSurface
                border.color: root.colBorder

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 4
                    Repeater {
                        model: ["Jokes", "Submit", "Admin", "Accounts"]
                        delegate: Rectangle {
                            height: 26
                            width: tabLbl.implicitWidth + 18
                            radius: 5
                            color: mainTabs.currentIndex === index ? root.colPrimary : "transparent"
                            border.color: mainTabs.currentIndex === index ? "transparent" : root.colBorder
                            Label {
                                id: tabLbl
                                anchors.centerIn: parent
                                text: modelData
                                color: mainTabs.currentIndex === index ? "#fff" : root.colMuted
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: mainTabs.currentIndex = index
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // Refresh button
                    Rectangle {
                        width: 26; height: 26; radius: 5
                        color: "transparent"; border.color: root.colBorder
                        Label { anchors.centerIn: parent; text: "↻"; color: root.colMuted; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: backend.refreshState(); cursorShape: Qt.PointingHandCursor }
                    }
                }
            }

            // Error bar
            Rectangle {
                Layout.fillWidth: true
                height: 28
                color: root.colError + "22"
                border.color: root.colError + "55"
                visible: backend.lastError !== ""
                Label {
                    anchors { fill: parent; leftMargin: 10 }
                    verticalAlignment: Text.AlignVCenter
                    text: backend.lastError
                    color: root.colError
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // Tabs
            StackLayout {
                id: mainTabs
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: 0

                // ── Jokes tab ─────────────────────────────────────────────────
                Item {
                    Flickable {
                        anchors { fill: parent; margins: 12 }
                        contentHeight: jokeCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: jokeCol
                            width: parent.width
                            spacing: 8

                            Label {
                                visible: backend.jokes.length === 0
                                text: !backend.sessionExists
                                      ? (backend.currentSessionPda !== "" ? "No session at this PDA yet." : "Add a session in the sidebar.")
                                      : "No jokes yet — be the first!"
                                color: root.colMuted
                                font { pixelSize: 13; italic: true }
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: backend.jokes
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: jRow.implicitHeight + 20
                                    radius: 8
                                    color: modelData.rank === 1 && modelData.vote_count > 0
                                           ? root.colPrimary + "18" : root.colBg
                                    border.color: modelData.rank === 1 && modelData.vote_count > 0
                                           ? root.colPrimary + "88" : root.colBorder

                                    RowLayout {
                                        id: jRow
                                        anchors { fill: parent; margins: 10 }
                                        spacing: 10

                                        // Rank badge
                                        Rectangle {
                                            width: 36; height: 36; radius: 8
                                            color: modelData.rank === 1 && modelData.vote_count > 0 ? root.colPrimary
                                                 : modelData.rank === 2 && modelData.vote_count > 0 ? root.colPrimary + "88"
                                                 : modelData.rank === 3 && modelData.vote_count > 0 ? root.colPrimary + "55"
                                                 : root.colPrimary + "22"
                                            Label {
                                                anchors.centerIn: parent
                                                text: modelData.rank === 1 && modelData.vote_count > 0 ? "🥇"
                                                    : modelData.rank === 2 && modelData.vote_count > 0 ? "🥈"
                                                    : modelData.rank === 3 && modelData.vote_count > 0 ? "🥉"
                                                    : "#" + modelData.rank
                                                color: "#fff"
                                                font { pixelSize: modelData.rank <= 3 && modelData.vote_count > 0 ? 16 : 11; bold: true }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 2
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.content
                                                color: root.colText
                                                font.pixelSize: 13
                                                wrapMode: Text.WordWrap
                                            }
                                            Label {
                                                text: "#" + modelData.index + " · " + modelData.submitter
                                                color: root.colMuted; font.pixelSize: 10
                                            }
                                        }

                                        // Vote count
                                        ColumnLayout {
                                            spacing: 2
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.vote_count
                                                color: modelData.vote_count > 0 ? root.colPrimary : root.colMuted
                                                font { pixelSize: 18; bold: modelData.vote_count > 0 }
                                            }
                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "votes"
                                                color: root.colMuted; font.pixelSize: 9
                                            }
                                        }

                                        Rectangle {
                                            width: 56; height: 34; radius: 6
                                            color: (backend.isActive && !backend.busy && backend.voterId !== "")
                                                ? root.colPrimary : root.colBorder
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            Label { anchors.centerIn: parent; text: "Vote"; color: "#fff"; font { pixelSize: 12; bold: true } }
                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: backend.isActive && !backend.busy && backend.voterId !== ""
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: backend.vote(modelData.index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Submit tab ────────────────────────────────────────────────
                ColumnLayout {
                    anchors.margins: 14
                    spacing: 10

                    Label {
                        text: !backend.sessionExists ? "Create or select a session first."
                            : !backend.isActive ? "Session is closed."
                            : backend.submitterId === "" ? "Generate a submitter account in the Accounts tab."
                            : "Submit your joke to the session."
                        color: root.colMuted; font.pixelSize: 12
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 40; radius: 8
                        color: root.colBg; border.color: root.colBorder
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            Label { text: "Submitter:"; color: root.colMuted; font.pixelSize: 11 }
                            Label {
                                Layout.fillWidth: true
                                text: backend.submitterId !== "" ? backend.submitterId : "— not set —"
                                color: backend.submitterId !== "" ? root.colText : root.colMuted
                                font.pixelSize: 11; elide: Text.ElideMiddle
                            }
                        }
                    }

                    JwTextField { id: submitContent; placeholderText: "Your joke…" }

                    JwButton {
                        text: "Submit Joke"; accent: true
                        enabled: backend.isActive && !backend.busy
                              && backend.submitterId !== "" && submitContent.text !== ""
                        onClicked: backend.submitJoke(submitContent.text.trim())
                    }

                    Item { Layout.fillHeight: true }
                }

                // ── Admin tab ─────────────────────────────────────────────────
                ColumnLayout {
                    anchors.margins: 14
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true; height: 40; radius: 8
                        color: root.colBg; border.color: root.colBorder
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            Label { text: "Admin:"; color: root.colMuted; font.pixelSize: 11 }
                            Label {
                                Layout.fillWidth: true
                                text: backend.adminId !== "" ? backend.adminId : "— not set (generate in Accounts tab) —"
                                color: backend.adminId !== "" ? root.colText : root.colMuted
                                font.pixelSize: 11; elide: Text.ElideMiddle
                            }
                        }
                    }

                    Label { text: "Create session"; color: root.colText; font.pixelSize: 13 }
                    JwTextField { id: createDesc; placeholderText: "Session description" }
                    JwButton {
                        text: "Create Session"; accent: true
                        enabled: !backend.busy && backend.adminId !== "" && createDesc.text !== ""
                        onClicked: {
                            backend.createSession(createDesc.text.trim())
                        }
                    }

                    Rectangle { height: 1; Layout.fillWidth: true; color: root.colBorder }

                    Label { text: "Close session"; color: root.colText; font.pixelSize: 13 }
                    JwButton {
                        text: "Close Session"
                        enabled: backend.isActive && !backend.busy && backend.adminId !== ""
                        onClicked: backend.closeSession()
                    }

                    Item { Layout.fillHeight: true }
                }

                // ── Accounts tab ──────────────────────────────────────────────
                Flickable {
                    contentHeight: accountsCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: accountsCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 14

                        Label {
                            text: "Accounts are stored in your wallet file and persist across sessions."
                            color: root.colMuted; font.pixelSize: 11
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }

                        AccountRow {
                            label: "Admin"
                            description: "Signs create/close session transactions"
                            accountId: backend.adminId
                            onGenerate: backend.generateAdmin()
                            onAssign: (id) => backend.setAdminId(id)
                        }

                        AccountRow {
                            label: "Submitter"
                            description: "Signs joke submissions"
                            accountId: backend.submitterId
                            onGenerate: backend.generateSubmitter()
                            onAssign: (id) => backend.setSubmitterId(id)
                        }

                        AccountRow {
                            label: "Voter"
                            description: "Signs votes"
                            accountId: backend.voterId
                            onGenerate: backend.generateVoter()
                            onAssign: (id) => backend.setVoterId(id)
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // ── Shared components ─────────────────────────────────────────────────────

    component JwTextField: TextField {
        Layout.fillWidth: true
        color: root.colText
        placeholderTextColor: root.colMuted
        font.pixelSize: 13
        leftPadding: 10; rightPadding: 10
        background: Rectangle {
            radius: 7; color: root.colBg
            border.color: parent.activeFocus ? root.colPrimary : root.colBorder
            border.width: parent.activeFocus ? 2 : 1
        }
    }

    component JwButton: Rectangle {
        id: btn
        Layout.fillWidth: true
        height: 38; radius: 7
        property string text: ""
        property bool accent: false
        property bool enabled: true
        signal clicked

        color: !enabled ? root.colBorder : accent ? root.colPrimary : root.colSurface
        border.color: accent || !enabled ? "transparent" : root.colBorder
        Behavior on color { ColorAnimation { duration: 100 } }

        Label {
            anchors.centerIn: parent; text: btn.text
            color: btn.enabled ? "#fff" : root.colMuted
            font { pixelSize: 13; bold: btn.accent }
        }
        MouseArea {
            anchors.fill: parent; enabled: btn.enabled
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabled) btn.clicked()
        }
    }

    component AccountRow: ColumnLayout {
        id: acctRow
        Layout.fillWidth: true
        spacing: 6
        property string label: ""
        property string description: ""
        property string accountId: ""
        signal generate()
        signal assign(string id)

        Rectangle {
            Layout.fillWidth: true
            height: acctContent.implicitHeight + 16
            radius: 8; color: root.colSurface; border.color: root.colBorder

            ColumnLayout {
                id: acctContent
                anchors { fill: parent; margins: 8 }
                spacing: 6

                RowLayout {
                    Label {
                        text: acctRow.label
                        color: root.colText; font { pixelSize: 13; bold: true }
                    }
                    Label {
                        text: acctRow.description
                        color: root.colMuted; font.pixelSize: 11
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 6

                    TextField {
                        id: acctInput
                        Layout.fillWidth: true
                        text: acctRow.accountId
                        placeholderText: "Paste account ID or generate →"
                        placeholderTextColor: root.colMuted
                        color: root.colText; font.pixelSize: 11
                        leftPadding: 8; rightPadding: 8
                        background: Rectangle {
                            radius: 6; color: root.colBg
                            border.color: parent.activeFocus ? root.colPrimary : root.colBorder
                        }
                        onEditingFinished: if (text !== acctRow.accountId) acctRow.assign(text)
                    }

                    Rectangle {
                        width: 72; height: 32; radius: 6
                        color: backend.busy ? root.colBorder : root.colPrimary
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Label { anchors.centerIn: parent; text: "Generate"; color: "#fff"; font.pixelSize: 10 }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !backend.busy
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: acctRow.generate()
                        }
                    }
                }

                Label {
                    visible: acctRow.accountId !== ""
                    text: acctRow.accountId
                    color: root.colSuccess; font.pixelSize: 9
                    wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                }
            }
        }
    }
}
