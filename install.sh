#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

widget_id="io.github.kde-agents-usage"
package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/package"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "Error: kpackagetool6 is not installed." >&2
    exit 1
fi

if kpackagetool6 --type Plasma/Applet --show "$widget_id" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$package_dir"
else
    kpackagetool6 --type Plasma/Applet --install "$package_dir"
fi

echo "Agents Usage is installed. Add it from the Plasma widget selector."
