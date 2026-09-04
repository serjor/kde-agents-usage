<!--
SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
SPDX-License-Identifier: MIT
-->

# KDE Plasma 6 AI Agent Usage and Quota Monitor

Agents Usage is an open-source KDE Plasma 6 widget for AI coding-agent quotas and reset times.

The plasmoid monitors Claude Code, OpenAI Codex CLI, and OpenCode from your Linux desktop. It has no telemetry or analytics.

## Features

- Show the remaining percentage for each available quota window.
- Show a countdown for each quota reset.
- Select the agents that appear in the widget.
- Set warning and critical quota levels.
- Refresh automatically at a configurable interval.
- Keep local quota data in private cache files.

The panel view shows all available quota windows. Open the widget to see reset countdowns, plans, and data sources.

## Supported agents

| Agent | Data source | Quota result |
|---|---|---|
| Claude Code | Local status-line collector | Five-hour, weekly, Sonnet, and Opus windows when available |
| Claude Code | Optional Anthropic usage API | Five-hour, weekly, Sonnet, and Opus windows when available |
| OpenAI Codex CLI | Recent local session events | Five-hour and weekly windows |
| OpenCode | Optional local provider export | Windows from the selected provider |

OpenCode connects to different model providers. Thus, OpenCode does not have one universal quota.

The widget does not estimate missing percentages. It shows an unavailable state when an agent does not supply quota data.

## Requirements

- KDE Plasma 6.
- Python 3.10 or a newer version.
- `kpackagetool6`.

The widget has no external Python package dependencies.

## Install

1. Clone this repository.
2. Run `./install.sh` from the repository directory.
3. Open the Plasma widget selector.
4. Add **Agents Usage** to a panel or the desktop.

If Plasma does not list the widget, restart Plasma Shell:

```bash
systemctl --user restart plasma-plasmashell.service
```

Run `./install.sh` again to install an update.

## Configure Claude Code

The local status-line collector is the most private Claude source. It does not make network requests.

Add this object to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "python3 ~/.local/share/plasma/plasmoids/io.github.kde-agents-usage/contents/code/claude-statusline-collector"
  }
}
```

If you already have a status-line command, connect the collector through that script. Do not replace your existing command.

You can use the Anthropic usage API instead. Enable **Allow requests to the Anthropic usage API** in the widget configuration.

This option is off by default. It reads the Claude OAuth token and sends it only to `https://api.anthropic.com/api/oauth/usage`.

## Configure an OpenCode provider

Create `~/.config/kde-agents-usage/opencode.json` when an OpenCode provider supplies rate limits.

Use this format:

```json
{
  "plan": "provider plan",
  "rate_limits": {
    "primary": {
      "used_percent": 30,
      "resets_at": 1788543614
    },
    "secondary": {
      "used_percent": 45,
      "resets_at": 1788773266
    }
  }
}
```

`used_percent` is the consumed quota. The widget converts this value to the available percentage.

## Privacy and security

The default configuration makes no network requests. Codex data and OpenCode provider exports stay on your computer.

The helper reads recent Codex session files. It extracts only rate-limit values, reset times, and the plan name.

The Claude status-line collector stores only quota values, reset times, and the plan name. It does not store the full input.

The optional Anthropic request keeps the OAuth token in memory. It does not cache the token or follow HTTP redirects.

Cache files use user-only permissions. The cache directory is `~/.cache/kde-agents-usage`.

The project does not collect prompts, responses, source code, account identifiers, or usage analytics.

Read [SECURITY.md](SECURITY.md) before you report a security problem. Use GitHub private vulnerability reporting for sensitive details.

## Development

Run the automated tests:

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile package/contents/code/agent-usage-json package/contents/code/claude-statusline-collector
```

If `qmllint` is installed, examine the QML files:

```bash
qmllint package/contents/ui/main.qml package/contents/ui/configGeneral.qml
```

Inspect the normalized output:

```bash
python3 package/contents/code/agent-usage-json | python3 -m json.tool
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before you submit a change.

Project credits are available in [CONTRIBUTORS.md](CONTRIBUTORS.md).

## Related projects

The package uses the [KDE Plasma 6 widget structure](https://develop.kde.org/docs/plasma/widget/setup/).

The provider design took inspiration from [PlasmaWidgetAiUsage](https://github.com/WariKoda/PlasmaWidgetAiUsage), an MIT-licensed project.

## License

KDE Agents Usage is available under the [MIT License](LICENSE).
