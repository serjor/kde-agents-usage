// SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property var report: null
    property string errorText: ""
    property bool loading: false
    property string runningCommand: ""
    property double nowMs: Date.now()
    readonly property string helperPath: Qt.resolvedUrl("../code/agent-usage-json").toString().replace(/^file:\/\//, "")

    toolTipMainText: i18n("Agents Usage")
    toolTipSubText: summaryText()

    function providers() {
        return report && report.providers ? report.providers : []
    }

    function enabledProviders() {
        var result = []
        if (Plasmoid.configuration.showClaude) result.push("claude")
        if (Plasmoid.configuration.showCodex) result.push("codex")
        if (Plasmoid.configuration.showOpenCode) result.push("opencode")
        if (Plasmoid.configuration.showOllama) result.push("ollama")
        return result.join(",")
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function remaining(windowData) {
        if (!windowData || windowData.used_percent === null || windowData.used_percent === undefined)
            return null
        return Math.max(0, Math.min(100, 100 - Number(windowData.used_percent)))
    }

    function colorFor(value) {
        if (value === null) return Kirigami.Theme.disabledTextColor
        if (value <= Plasmoid.configuration.criticalRemaining) return Kirigami.Theme.negativeTextColor
        if (value <= Plasmoid.configuration.warningRemaining) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }

    function formatRemaining(windowData) {
        var value = remaining(windowData)
        return value === null ? "—" : Math.round(value) + "%"
    }

    function countdown(timestamp) {
        if (!timestamp) return i18n("unknown")
        var seconds = Math.max(0, Math.floor(Number(timestamp) - nowMs / 1000))
        if (seconds === 0) return i18n("now")
        var days = Math.floor(seconds / 86400)
        var hours = Math.floor((seconds % 86400) / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        if (days > 0) return i18n("%1d %2h", days, hours)
        if (hours > 0) return i18n("%1h %2m", hours, minutes)
        return i18n("%1m", minutes)
    }

    function headline(providerData) {
        return providerData.windows && providerData.windows.length ? providerData.windows[0] : null
    }

    function importantWindow(providerData) {
        var windows = providerData.windows || []
        var selected = windows.length ? windows[0] : null
        var selectedRemaining = remaining(selected)
        for (var i = 1; i < windows.length; ++i) {
            var candidateRemaining = remaining(windows[i])
            if (candidateRemaining !== null
                    && (selectedRemaining === null || candidateRemaining < selectedRemaining)) {
                selected = windows[i]
                selectedRemaining = candidateRemaining
            }
        }
        return selected
    }

    function stateText(value) {
        if (value === null) return i18n("Unknown")
        if (value <= Plasmoid.configuration.criticalRemaining) return i18n("Critical")
        if (value <= Plasmoid.configuration.warningRemaining) return i18n("Low")
        return i18n("Available")
    }

    function freshnessText() {
        if (loading && !report) return i18n("Loading…")
        if (!report || !report.generated_at) return i18n("Not updated")
        var seconds = Math.max(0, Math.floor(nowMs / 1000 - Number(report.generated_at)))
        if (seconds < 60) return i18n("Updated now")
        var minutes = Math.floor(seconds / 60)
        if (minutes < 60) return i18n("Updated %1m ago", minutes)
        return i18n("Updated %1h ago", Math.floor(minutes / 60))
    }

    function providerSummary(providerData) {
        if (!providerData.available || !providerData.windows || !providerData.windows.length)
            return providerData.error || i18n("unavailable")
        var values = []
        for (var i = 0; i < providerData.windows.length; ++i) {
            var windowData = providerData.windows[i]
            values.push(windowData.label + ": " + formatRemaining(windowData)
                        + " · " + countdown(windowData.resets_at))
        }
        return values.join("\n")
    }

    function summaryText() {
        if (errorText) return errorText
        if (loading && !report) return i18n("Loading…")
        var lines = []
        var items = providers()
        for (var i = 0; i < items.length; ++i) {
            var providerData = items[i]
            lines.push(providerData.label + ": " + providerSummary(providerData))
        }
        return lines.join("\n")
    }

    function refresh() {
        if (loading) return
        loading = true
        errorText = ""
        runningCommand = "AGENT_USAGE_CLAUDE_NETWORK="
                       + (Plasmoid.configuration.allowClaudeNetwork ? "1" : "0")
                       + " AGENT_USAGE_CODEX_NETWORK="
                       + (Plasmoid.configuration.allowCodexNetwork ? "1" : "0")
                       + " AGENT_USAGE_PROVIDERS=" + enabledProviders()
                       + " python3 " + shellQuote(helperPath)
        executable.connectSource(runningCommand)
        watchdog.restart()
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (sourceName !== root.runningCommand) return
            watchdog.stop()
            root.runningCommand = ""
            root.loading = false
            try {
                root.report = JSON.parse(data["stdout"] || "")
            } catch (exception) {
                root.errorText = (data["stderr"] || exception.toString()).trim()
            }
        }
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMinutes) * 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: {
            executable.disconnectSource(root.runningCommand)
            root.runningCommand = ""
            root.loading = false
            root.errorText = i18n("Refresh timed out")
        }
    }
    Component.onCompleted: refresh()

    compactRepresentation: MouseArea {
        id: compactMouse

        implicitWidth: compactRow.implicitWidth + Kirigami.Units.largeSpacing * 2
        implicitHeight: Kirigami.Units.iconSizes.smallMedium
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: compactMouse.containsMouse ? 0.12 : 0

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }
        }

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: root.providers()
                delegate: RowLayout {
                    id: compactProvider
                    required property var modelData
                    readonly property var windowData: root.importantWindow(modelData)
                    readonly property var availableValue: root.remaining(windowData)
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        implicitWidth: Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: root.colorFor(compactProvider.availableValue)
                    }
                    PlasmaComponents.Label {
                        text: modelData.label.slice(0, 1)
                        font.bold: true
                    }
                    PlasmaComponents.Label {
                        visible: compactProvider.windowData !== null
                        text: compactProvider.windowData ? compactProvider.windowData.key : ""
                        opacity: 0.65
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    PlasmaComponents.Label {
                        text: compactProvider.windowData
                              ? root.formatRemaining(compactProvider.windowData) : "—"
                        font.bold: true
                        color: root.colorFor(compactProvider.availableValue)
                    }
                }
            }
            PlasmaComponents.BusyIndicator {
                visible: root.loading
                running: visible
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: width
            }
        }
    }

    fullRepresentation: Item {
        implicitWidth: Kirigami.Units.gridUnit * 28
        implicitHeight: Math.min(Math.max(details.implicitHeight + Kirigami.Units.largeSpacing * 2,
                                          Kirigami.Units.gridUnit * 15),
                                 Kirigami.Units.gridUnit * 36)
        Layout.minimumHeight: Math.min(implicitHeight, Kirigami.Units.gridUnit * 15)
        Layout.preferredHeight: implicitHeight

        PlasmaComponents.ScrollView {
            id: fullScroll

            anchors.fill: parent
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: details

                width: fullScroll.availableWidth
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Item {
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: implicitWidth

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Kirigami.Theme.highlightColor
                            opacity: 0.16
                        }
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "view-statistics"
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: implicitWidth
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Kirigami.Heading { text: i18n("Available quota"); level: 2 }
                        PlasmaComponents.Label {
                            text: root.freshnessText()
                            opacity: 0.65
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                    PlasmaComponents.BusyIndicator {
                        visible: root.loading
                        running: visible
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                    }
                    PlasmaComponents.ToolButton {
                        icon.name: "view-refresh"
                        enabled: !root.loading
                        onClicked: root.refresh()
                        PlasmaComponents.ToolTip { text: i18n("Refresh") }
                    }
                }

                PlasmaComponents.Frame {
                    visible: root.errorText.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    padding: Kirigami.Units.largeSpacing

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            source: "dialog-error-symbolic"
                            color: Kirigami.Theme.negativeTextColor
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: implicitWidth
                        }
                        PlasmaComponents.Label {
                            text: root.errorText
                            color: Kirigami.Theme.negativeTextColor
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }

                Repeater {
                    model: root.providers()
                    delegate: PlasmaComponents.Frame {
                        id: providerCard

                        required property var modelData
                        readonly property var headlineWindow: root.importantWindow(modelData)
                        readonly property var headlineRemaining: root.remaining(headlineWindow)

                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        padding: Kirigami.Units.largeSpacing

                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.largeSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Rectangle {
                                    implicitWidth: Kirigami.Units.smallSpacing * 1.5
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: root.colorFor(providerCard.headlineRemaining)
                                }
                                Kirigami.Heading {
                                    text: providerCard.modelData.label
                                    level: 3
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents.Label {
                                    visible: providerCard.modelData.plan
                                    text: providerCard.modelData.plan || ""
                                    opacity: 0.65
                                    font.bold: true
                                    font.capitalization: Font.AllUppercase
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                            }

                            PlasmaComponents.Label {
                                visible: !providerCard.modelData.available
                                text: providerCard.modelData.error || i18n("Usage unavailable")
                                wrapMode: Text.Wrap
                                opacity: 0.7
                                Layout.fillWidth: true
                            }

                            Repeater {
                                model: providerCard.modelData.windows || []
                                delegate: ColumnLayout {
                                    id: quotaWindow

                                    required property var modelData
                                    readonly property var availableValue: root.remaining(modelData)
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            PlasmaComponents.Label {
                                                text: quotaWindow.modelData.label
                                                font.bold: true
                                            }
                                            PlasmaComponents.Label {
                                                text: root.stateText(quotaWindow.availableValue)
                                                color: root.colorFor(quotaWindow.availableValue)
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            }
                                        }
                                        PlasmaComponents.Label {
                                            text: root.formatRemaining(quotaWindow.modelData)
                                            color: root.colorFor(quotaWindow.availableValue)
                                            font.bold: true
                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.55
                                        }
                                    }

                                    Item {
                                        implicitHeight: Kirigami.Units.smallSpacing
                                        Layout.fillWidth: true

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: Kirigami.Theme.disabledTextColor
                                            opacity: 0.22
                                        }
                                        Rectangle {
                                            width: parent.width * (quotaWindow.availableValue === null
                                                   ? 0 : quotaWindow.availableValue / 100)
                                            height: parent.height
                                            radius: height / 2
                                            color: root.colorFor(quotaWindow.availableValue)

                                            Behavior on width {
                                                NumberAnimation { duration: Kirigami.Units.longDuration }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing
                                        Kirigami.Icon {
                                            source: "chronometer"
                                            implicitWidth: Kirigami.Units.iconSizes.small
                                            implicitHeight: implicitWidth
                                            opacity: 0.65
                                        }
                                        PlasmaComponents.Label {
                                            text: quotaWindow.modelData.resets_at
                                                  ? i18n("Resets in %1", root.countdown(quotaWindow.modelData.resets_at))
                                                  : i18n("Reset unknown")
                                            opacity: 0.65
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            PlasmaComponents.Label {
                                visible: providerCard.modelData.source && providerCard.modelData.available
                                text: i18n("Source: %1", providerCard.modelData.source)
                                opacity: 0.5
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                }

                Item { implicitHeight: Kirigami.Units.smallSpacing }
            }
        }
    }
}
