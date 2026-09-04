# SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
# SPDX-License-Identifier: MIT

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "package/contents/code/agent-usage-json"
COLLECTOR = ROOT / "package/contents/code/claude-statusline-collector"


def run_helper(home: Path, providers: str):
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["XDG_CACHE_HOME"] = str(home / ".cache")
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    env["XDG_DATA_HOME"] = str(home / ".local/share")
    env["AGENT_USAGE_PROVIDERS"] = providers
    result = subprocess.run(
        ["python3", str(HELPER)], env=env, text=True, capture_output=True,
        timeout=5, check=True,
    )
    return json.loads(result.stdout)


class HelperTests(unittest.TestCase):
    def test_claude_network_access_is_off_by_default(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            credentials = home / ".claude/.credentials.json"
            credentials.parent.mkdir(parents=True)
            credentials.write_text(json.dumps({
                "claudeAiOauth": {"accessToken": "synthetic-not-a-real-token"}
            }), encoding="utf-8")
            claude = run_helper(home, "claude")["providers"][0]
            self.assertFalse(claude["available"])
            self.assertIn("optional Anthropic request", claude["error"])
            self.assertFalse((home / ".cache/kde-agents-usage/claude-api.json").exists())

    def test_status_line_cache_excludes_unrelated_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            env = os.environ.copy()
            env["HOME"] = str(home)
            env["XDG_CACHE_HOME"] = str(home / ".cache")
            payload = {
                "account": "synthetic-account-id",
                "usage": {
                    "plan": "pro",
                    "five_hour": {
                        "used_percent": 12,
                        "resets_at": "2099-01-01T00:00:00Z",
                        "private_field": "synthetic-private-value",
                    },
                    "private_field": "synthetic-private-value",
                },
            }
            subprocess.run(
                ["python3", str(COLLECTOR)], env=env, input=json.dumps(payload),
                text=True, capture_output=True, timeout=5, check=True,
            )
            cache_path = home / ".cache/kde-agents-usage/claude-statusline.json"
            cache_text = cache_path.read_text(encoding="utf-8")
            cache = json.loads(cache_text)
            self.assertNotIn("synthetic-private-value", cache_text)
            self.assertNotIn("synthetic-account-id", cache_text)
            self.assertEqual({"plan", "five_hour"}, set(cache["usage"]))
            self.assertEqual(0o600, cache_path.stat().st_mode & 0o777)

    def test_codex_reads_real_rate_limit_event(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            session = home / ".codex/sessions/2026/09/04/session.jsonl"
            session.parent.mkdir(parents=True)
            event = {
                "timestamp": "2026-09-04T12:00:00Z",
                "payload": {
                    "type": "token_count",
                    "rate_limits": {
                        "primary": {"used_percent": 12, "resets_at": 4102444800},
                        "secondary": {"used_percent": 34, "resets_at": 4102444800},
                        "plan_type": "plus",
                    },
                },
            }
            session.write_text(json.dumps(event) + "\n", encoding="utf-8")
            report = run_helper(home, "codex")
            codex = report["providers"][0]
            self.assertTrue(codex["available"])
            self.assertEqual(codex["plan"], "plus")
            self.assertEqual([12.0, 34.0], [item["used_percent"] for item in codex["windows"]])

    def test_opencode_does_not_invent_a_percentage(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            (home / ".config/opencode").mkdir(parents=True)
            opencode = run_helper(home, "opencode")["providers"][0]
            self.assertFalse(opencode["available"])
            self.assertEqual([], opencode["windows"])

    def test_opencode_reads_provider_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            path = home / ".config/kde-agents-usage/opencode.json"
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({
                "rate_limits": {
                    "primary": {"used_percent": 25, "resets_at": 4102444800}
                }
            }), encoding="utf-8")
            opencode = run_helper(home, "opencode")["providers"][0]
            self.assertTrue(opencode["available"])
            self.assertEqual(25.0, opencode["windows"][0]["used_percent"])


if __name__ == "__main__":
    unittest.main()
