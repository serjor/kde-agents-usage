// SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.components as PlasmaComponents

KCM.SimpleKCM {
    property alias cfg_showClaude: showClaude.checked
    property alias cfg_allowClaudeNetwork: allowClaudeNetwork.checked
    property alias cfg_showCodex: showCodex.checked
    property alias cfg_allowCodexNetwork: allowCodexNetwork.checked
    property alias cfg_showOpenCode: showOpenCode.checked
    property alias cfg_refreshMinutes: refreshMinutes.value
    property alias cfg_warningRemaining: warningRemaining.value
    property alias cfg_criticalRemaining: criticalRemaining.value

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
