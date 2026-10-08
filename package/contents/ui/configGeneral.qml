// SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    property alias cfg_showClaude: showClaude.checked
    property alias cfg_allowClaudeNetwork: allowClaudeNetwork.checked
    property alias cfg_showCodex: showCodex.checked
    property alias cfg_allowCodexNetwork: allowCodexNetwork.checked
    property alias cfg_showOpenCode: showOpenCode.checked
    property alias cfg_showOllama: showOllama.checked
    property alias cfg_refreshMinutes: refreshMinutes.value
    property alias cfg_warningRemaining: warningRemaining.value
    property alias cfg_criticalRemaining: criticalRemaining.value

    readonly property string helperPath: Qt.resolvedUrl("../code/agent-usage-json").toString().replace(/^file:\/\//, "")
    // "stored", "missing", "unsupported", or "" while the helper runs.
    property string ollamaKeyState: ""
    property string ollamaKeyError: ""

    function runKeyAction(flag) {
        ollamaKeyState = ""
        ollamaKeyError = ""
        keyAction.connectSource("python3 '" + helperPath.replace(/'/g, "'\\''") + "' " + flag)
    }

    Component.onCompleted: runKeyAction("--ollama-key-status")

    P5Support.DataSource {
        id: keyAction
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            var error = data["exit code"] ? (data["stderr"] || "").trim() : ""
            page.ollamaKeyState = (data["stdout"] || "").trim()
            if (!page.ollamaKeyState && !sourceName.endsWith("--ollama-key-status"))
                page.runKeyAction("--ollama-key-status")
            page.ollamaKeyError = error
        }
    }

    Kirigami.FormLayout {
    PlasmaComponents.CheckBox { id: showClaude; text: "Claude" }
    PlasmaComponents.CheckBox {
        id: allowClaudeNetwork
        text: i18n("Allow requests to the Anthropic usage API")
    }
    PlasmaComponents.CheckBox { id: showCodex; text: "Codex" }
    PlasmaComponents.CheckBox {
        id: allowCodexNetwork
        text: i18n("Fetch current Codex limits through the Codex CLI")
    }
    PlasmaComponents.CheckBox { id: showOpenCode; text: "OpenCode" }
    PlasmaComponents.CheckBox { id: showOllama; text: i18n("Ollama Cloud") }
    ColumnLayout {
        visible: showOllama.checked
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: {
                switch (page.ollamaKeyState) {
                case "stored": return i18n("API key saved in the system wallet.")
                case "missing": return i18n("No API key saved.")
                case "unsupported": return i18n("Install secret-tool (libsecret) to save the API key.")
                default: return i18n("Checking API key…")
                }
            }
        }
        RowLayout {
            visible: page.ollamaKeyState === "stored" || page.ollamaKeyState === "missing"
            PlasmaComponents.Button {
                icon.name: "document-edit-decrypt-verify"
                text: page.ollamaKeyState === "stored" ? i18n("Change API key…") : i18n("Add API key…")
                onClicked: page.runKeyAction("--store-ollama-key")
            }
            PlasmaComponents.Button {
                visible: page.ollamaKeyState === "stored"
                icon.name: "edit-delete-remove"
                text: i18n("Remove")
                onClicked: page.runKeyAction("--forget-ollama-key")
            }
        }
        PlasmaComponents.Label {
            visible: page.ollamaKeyState === "missing"
            text: i18n("Create a key at <a href=\"https://ollama.com/settings/keys\">ollama.com/settings/keys</a>.")
            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
        }
        PlasmaComponents.Label {
            visible: page.ollamaKeyError.length > 0
            text: page.ollamaKeyError
            color: Kirigami.Theme.negativeTextColor
        }
    }
    PlasmaComponents.SpinBox {
        id: refreshMinutes
        Kirigami.FormData.label: i18n("Refresh every (minutes):")
        from: 1
        to: 60
    }
    PlasmaComponents.SpinBox {
        id: warningRemaining
        Kirigami.FormData.label: i18n("Warning below (% available):")
        from: 1
        to: 99
    }
    PlasmaComponents.SpinBox {
        id: criticalRemaining
        Kirigami.FormData.label: i18n("Critical below (% available):")
        from: 1
        to: 99
    }
    }
}
