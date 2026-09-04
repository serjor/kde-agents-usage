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
        implicitWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: Kirigami.Units.iconSizes.smallMedium
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: root.providers()
                delegate: RowLayout {
                    id: compactProvider
                    required property var modelData
                    spacing: 2
                    PlasmaComponents.Label {
                        text: modelData.label.slice(0, 1)
                        font.bold: true
                        color: root.colorFor(root.remaining(root.headline(modelData)))
                    }
                    Repeater {
                        model: compactProvider.modelData.windows || []
                        delegate: RowLayout {
                            required property int index
                            required property var modelData
                            spacing: 2
                            PlasmaComponents.Label {
                                text: (index > 0 ? "· " : "") + modelData.key
                                opacity: 0.7
                            }
                            PlasmaComponents.Label {
                                text: root.formatRemaining(modelData)
                                color: root.colorFor(root.remaining(modelData))
                            }
                        }
                    }
                    PlasmaComponents.Label {
                        visible: !compactProvider.modelData.windows
                                 || compactProvider.modelData.windows.length === 0
                        text: "—"
                        color: Kirigami.Theme.disabledTextColor
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
        implicitWidth: Kirigami.Units.gridUnit * 25
        implicitHeight: Math.min(details.implicitHeight + Kirigami.Units.largeSpacing * 2,
                                 Kirigami.Units.gridUnit * 32)

        ColumnLayout {
            id: details
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading { text: i18n("Available agent quota"); level: 2; Layout.fillWidth: true }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.loading
                    onClicked: root.refresh()
                    PlasmaComponents.ToolTip { text: i18n("Refresh") }
                }
            }

            PlasmaComponents.Label {
                visible: root.errorText.length > 0
                text: root.errorText
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Repeater {
                model: root.providers()
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading { text: modelData.label; level: 3; Layout.fillWidth: true }
                        PlasmaComponents.Label {
                            text: modelData.plan ? modelData.plan : ""
                            opacity: 0.7
                        }
                    }
                    PlasmaComponents.Label {
                        visible: !modelData.available
                        text: modelData.error || i18n("Usage unavailable")
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: modelData.windows || []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            PlasmaComponents.Label { text: modelData.label; Layout.preferredWidth: Kirigami.Units.gridUnit * 7 }
                            PlasmaComponents.ProgressBar {
                                from: 0; to: 100
                                value: root.remaining(modelData) === null ? 0 : root.remaining(modelData)
                                Layout.fillWidth: true
                            }
                            PlasmaComponents.Label {
                                text: root.formatRemaining(modelData)
                                font.bold: true
                                color: root.colorFor(root.remaining(modelData))
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            }
                            PlasmaComponents.Label {
                                text: modelData.resets_at ? root.countdown(modelData.resets_at) : "—"
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            }
                        }
                    }
                    PlasmaComponents.Label {
                        visible: modelData.source && modelData.available
                        text: i18n("Source: %1", modelData.source)
                        opacity: 0.55
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }
        }
    }
}
