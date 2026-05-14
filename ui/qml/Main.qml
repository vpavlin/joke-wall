import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// JokeWall — community joke voting UI.
// Expects a `backend` context property of type JokeWallBackend.

Rectangle {
    id: root
    width: 520
    height: 700
    color: "#0f1117"

    // ── Palette ───────────────────────────────────────────────────────────────
    readonly property color colBg:       "#0f1117"
    readonly property color colSurface:  "#1a1d27"
    readonly property color colBorder:   "#2d3148"
    readonly property color colPrimary:  "#7c6ef5"
    readonly property color colSuccess:  "#3ecf8e"
    readonly property color colWarning:  "#f5a623"
    readonly property color colError:    "#e05252"
    readonly property color colText:     "#e8e9f0"
    readonly property color colMuted:    "#6b7280"
    readonly property int   radius:      12

    // ── Toast notification ────────────────────────────────────────────────────
    Rectangle {
        id: toast
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 24 }
        width: toastLabel.implicitWidth + 32
        height: 40
        radius: 20
        color: toastSuccess ? root.colSuccess : root.colError
        opacity: 0
        z: 10

        property bool toastSuccess: true

        Label {
            id: toastLabel
            anchors.centerIn: parent
            color: "#fff"
            font.pixelSize: 13
        }

        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 200 }
            PauseAnimation { duration: 3000 }
            NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 400 }
        }

        function show(msg, success) {
            toast.toastSuccess = success
            toastLabel.text = msg
            toastAnim.restart()
        }
    }

    Connections {
        target: backend
        function onTxSuccess(operation, txHash) {
            toast.show("✓ " + operation + " — " + txHash.substring(0, 12) + "…", true)
            if (operation === "submit_joke") {
                submitContent.text = ""
            }
        }
        function onTxError(operation, error) {
            toast.show("✗ " + error, false)
        }
    }

    // ── Main layout ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 20 }
        spacing: 14

        // Header
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "🎭 JokeWall"
                color: root.colPrimary
                font { pixelSize: 22; bold: true }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: countLabel.implicitWidth + 16
                height: 26
                radius: 13
                color: root.colSurface
                border.color: root.colBorder
                Label {
                    id: countLabel
                    anchors.centerIn: parent
                    text: backend.jokeCount + " jokes"
                    color: root.colMuted
                    font.pixelSize: 12
                }
            }
            Rectangle {
                width: statusLabel.implicitWidth + 16
                height: 26
                radius: 13
                color: backend.isActive ? root.colSuccess + "22" : root.colError + "22"
                border.color: backend.isActive ? root.colSuccess + "88" : root.colError + "88"
                visible: backend.sessionExists
                Label {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: backend.isActive ? "OPEN" : "CLOSED"
                    color: backend.isActive ? root.colSuccess : root.colError
                    font { pixelSize: 11; bold: true }
                }
            }
        }

        // Session info card
        Rectangle {
            Layout.fillWidth: true
            height: 52
            radius: root.radius
            color: root.colSurface
            border.color: backend.sessionExists ? root.colPrimary : root.colBorder
            border.width: backend.sessionExists ? 2 : 1
            visible: backend.sessionExists || !backend.sessionExists

            ColumnLayout {
                anchors { fill: parent; margins: 12 }
                spacing: 2
                Label {
                    text: "SESSION"
                    color: root.colMuted
                    font { pixelSize: 10; capitalization: Font.AllUppercase; letterSpacing: 1 }
                }
                Label {
                    Layout.fillWidth: true
                    text: backend.sessionExists ? backend.description : "No session — create one in the Admin tab"
                    color: backend.sessionExists ? root.colText : root.colMuted
                    font { pixelSize: 14; italic: !backend.sessionExists }
                    elide: Text.ElideRight
                }
            }
        }

        // ── Tabs ──────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.radius
            color: root.colSurface
            border.color: root.colBorder
            clip: true

            ColumnLayout {
                anchors { fill: parent; margins: 14 }
                spacing: 12

                // Tab selector
                RowLayout {
                    spacing: 8
                    Repeater {
                        model: ["Jokes", "Submit", "Admin"]
                        delegate: Rectangle {
                            width: tabLabel.implicitWidth + 20
                            height: 30
                            radius: 6
                            color: mainTabs.currentIndex === index ? root.colPrimary : "transparent"
                            border.color: mainTabs.currentIndex === index ? "transparent" : root.colBorder

                            Label {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: modelData
                                color: mainTabs.currentIndex === index ? "#fff" : root.colMuted
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: mainTabs.currentIndex = index
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                    }
                }

                StackLayout {
                    id: mainTabs
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: 0

                    // ── Jokes tab ─────────────────────────────────────────────
                    Item {
                        Flickable {
                            anchors.fill: parent
                            contentHeight: jokeColumn.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: jokeColumn
                                width: parent.width
                                spacing: 8

                                Label {
                                    visible: backend.jokes.length === 0
                                    text: backend.sessionExists
                                        ? "No jokes yet — be the first to submit one!"
                                        : "Create a session first."
                                    color: root.colMuted
                                    font { pixelSize: 13; italic: true }
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }

                                Repeater {
                                    model: backend.jokes

                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: jokeRow.implicitHeight + 20
                                        radius: 8
                                        color: modelData.rank === 1 && modelData.vote_count > 0
                                               ? root.colPrimary + "18" : root.colBg
                                        border.color: modelData.rank === 1 && modelData.vote_count > 0
                                               ? root.colPrimary + "88" : root.colBorder

                                        RowLayout {
                                            id: jokeRow
                                            anchors { fill: parent; margins: 10 }
                                            spacing: 10

                                            // Rank + vote count badge
                                            Rectangle {
                                                width: 46
                                                height: 46
                                                radius: 8
                                                color: modelData.rank === 1 && modelData.vote_count > 0 ? root.colPrimary
                                                     : modelData.rank === 2 && modelData.vote_count > 0 ? root.colPrimary + "88"
                                                     : modelData.rank === 3 && modelData.vote_count > 0 ? root.colPrimary + "55"
                                                     : root.colPrimary + "22"
                                                border.color: "transparent"
                                                ColumnLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 0
                                                    Label {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: modelData.rank === 1 && modelData.vote_count > 0 ? "🥇"
                                                            : modelData.rank === 2 && modelData.vote_count > 0 ? "🥈"
                                                            : modelData.rank === 3 && modelData.vote_count > 0 ? "🥉"
                                                            : "#" + modelData.rank
                                                        color: "#fff"
                                                        font { pixelSize: modelData.rank <= 3 && modelData.vote_count > 0 ? 18 : 12; bold: true }
                                                    }
                                                    Label {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: modelData.vote_count + " votes"
                                                        color: modelData.rank === 1 && modelData.vote_count > 0 ? "#fff" : root.colMuted
                                                        font.pixelSize: 8
                                                    }
                                                }
                                            }

                                            // Content
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Label {
                                                    Layout.fillWidth: true
                                                    text: modelData.content
                                                    color: root.colText
                                                    font.pixelSize: 13
                                                    wrapMode: Text.WordWrap
                                                }
                                                Label {
                                                    text: "#" + modelData.index + " · " + modelData.submitter
                                                    color: root.colMuted
                                                    font.pixelSize: 10
                                                }
                                            }

                                            // Vote button
                                            Rectangle {
                                                width: 60
                                                height: 36
                                                radius: 6
                                                color: (backend.isActive && !backend.busy && voteAdmin.text !== "" && voteVoter.text !== "")
                                                    ? root.colPrimary : root.colBorder
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "Vote"
                                                    color: "#fff"
                                                    font { pixelSize: 12; bold: true }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: backend.isActive && !backend.busy
                                                          && voteAdmin.text !== "" && voteVoter.text !== ""
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: backend.vote(
                                                        voteAdmin.text.trim(),
                                                        voteVoter.text.trim(),
                                                        modelData.index
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }

                                // Watch session + voter credentials
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: voterForm.implicitHeight + 16
                                    radius: 8
                                    color: root.colSurface
                                    border.color: root.colBorder

                                    ColumnLayout {
                                        id: voterForm
                                        anchors { fill: parent; margins: 8 }
                                        spacing: 6
                                        Label {
                                            text: "Session & voter"
                                            color: root.colMuted
                                            font { pixelSize: 11; capitalization: Font.AllUppercase; letterSpacing: 1 }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            JwTextField {
                                                id: watchAdmin
                                                Layout.fillWidth: true
                                                placeholderText: "Session PDA (base58)"
                                            }
                                            Rectangle {
                                                width: 56; height: 36
                                                radius: 6
                                                color: watchAdmin.text !== "" ? root.colPrimary : root.colBorder
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "Watch"
                                                    color: "#fff"
                                                    font.pixelSize: 11
                                                    visible: !backend.polling
                                                }
                                                BusyIndicator {
                                                    anchors.centerIn: parent
                                                    width: 20; height: 20
                                                    running: backend.polling
                                                    visible: backend.polling
                                                    palette.dark: "#fff"
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: watchAdmin.text !== "" && !backend.polling
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: backend.setSessionPda(watchAdmin.text.trim())
                                                }
                                            }
                                        }
                                        Label {
                                            visible: backend.adminId !== ""
                                            text: "Watching: " + backend.adminId.substring(0, 16) + "…"
                                            color: root.colSuccess
                                            font.pixelSize: 11
                                        }
                                        JwTextField { id: voteAdmin;  placeholderText: "Admin account ID (to compute session PDA for voting)" }
                                        JwTextField { id: voteVoter; placeholderText: "Your account ID (voter)" }
                                    }
                                }
                            }
                        }
                    }

                    // ── Submit tab ────────────────────────────────────────────
                    ColumnLayout {
                        spacing: 10

                        Label {
                            text: backend.isActive
                                ? "Submit your joke to the session."
                                : backend.sessionExists
                                    ? "Session is closed — no more submissions."
                                    : "Create a session first (Admin tab)."
                            color: root.colMuted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        JwTextField { id: submitAdmin;     placeholderText: "Admin account ID" }
                        JwTextField { id: submitSubmitter; placeholderText: "Your account ID (submitter)" }
                        JwTextField {
                            id: submitContent
                            placeholderText: "Your joke…"
                        }

                        JwButton {
                            text: "Submit Joke"
                            accent: true
                            enabled: backend.isActive && !backend.busy
                                  && submitAdmin.text !== ""
                                  && submitSubmitter.text !== ""
                                  && submitContent.text !== ""
                            onClicked: backend.submitJoke(
                                submitAdmin.text.trim(),
                                submitSubmitter.text.trim(),
                                submitContent.text.trim()
                            )
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ── Admin tab ─────────────────────────────────────────────
                    ColumnLayout {
                        spacing: 10

                        Label {
                            text: "Admin operations (require admin account)."
                            color: root.colMuted
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }

                        // Create session
                        Label { text: "Create session"; color: root.colText; font.pixelSize: 13 }
                        JwTextField { id: createAdmin;       placeholderText: "Admin account ID" }
                        JwTextField { id: createDescription; placeholderText: "Session description" }
                        JwButton {
                            text: "Create Session"
                            accent: true
                            enabled: !backend.busy
                                  && createAdmin.text !== ""
                                  && createDescription.text !== ""
                            onClicked: backend.createSession(
                                createAdmin.text.trim(),
                                createDescription.text.trim()
                            )
                        }

                        Rectangle { height: 1; Layout.fillWidth: true; color: root.colBorder }

                        // Close session
                        Label { text: "Close session"; color: root.colText; font.pixelSize: 13 }
                        JwTextField { id: closeAdmin; placeholderText: "Admin account ID" }
                        JwButton {
                            text: "Close Session"
                            enabled: backend.isActive && !backend.busy && closeAdmin.text !== ""
                            onClicked: backend.closeSession(closeAdmin.text.trim())
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        // ── Status bar ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            BusyIndicator {
                width: 20; height: 20
                running: backend.busy || backend.polling
                visible: backend.busy || backend.polling
                palette.dark: root.colPrimary
            }

            Label {
                text: backend.busy             ? "Submitting…"
                    : backend.polling          ? "Fetching…"
                    : backend.lastError !== "" ? "Error: " + backend.lastError
                    : backend.lastTxHash !== "" ? "OK — " + backend.lastTxHash.substring(0, 16) + "…"
                    : backend.adminId !== ""   ? "Watching: " + backend.adminId.substring(0, 24) + "…"
                    : "Ready"
                color: backend.lastError !== "" ? root.colError : root.colMuted
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                width: 28; height: 28
                radius: 6
                color: "transparent"
                border.color: root.colBorder
                Label {
                    anchors.centerIn: parent
                    text: "↻"
                    color: root.colMuted
                    font.pixelSize: 16
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: backend.refreshState()
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }

    // ── Shared components ─────────────────────────────────────────────────────

    component JwTextField: TextField {
        Layout.fillWidth: true
        color: root.colText
        placeholderTextColor: root.colMuted
        font.pixelSize: 14
        leftPadding: 12
        rightPadding: 12
        background: Rectangle {
            radius: 8
            color: root.colBg
            border.color: parent.activeFocus ? root.colPrimary : root.colBorder
            border.width: parent.activeFocus ? 2 : 1
        }
    }

    component JwButton: Rectangle {
        id: btn
        Layout.fillWidth: true
        height: 40
        radius: 8
        property string text: ""
        property bool accent: false
        property bool enabled: true
        signal clicked

        color: !enabled ? root.colBorder
             : accent   ? root.colPrimary
                        : root.colSurface
        border.color: accent || !enabled ? "transparent" : root.colBorder

        Behavior on color { ColorAnimation { duration: 100 } }

        Label {
            anchors.centerIn: parent
            text: btn.text
            color: btn.enabled ? "#fff" : root.colMuted
            font { pixelSize: 14; bold: btn.accent }
        }

        MouseArea {
            anchors.fill: parent
            enabled: btn.enabled
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabled) btn.clicked()
        }
    }
}
