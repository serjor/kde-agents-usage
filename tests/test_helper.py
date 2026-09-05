# SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
# SPDX-License-Identifier: MIT

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "package/contents/code/agent-usage-json"
COLLECTOR = ROOT / "package/contents/code/claude-statusline-collector"


def load_helper_module():
    loader = importlib.machinery.SourceFileLoader("helper_module", str(HELPER))
    spec = importlib.util.spec_from_loader("helper_module", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def run_helper(home: Path, providers: str, extra_env=None):
    env = os.environ.copy()
    env.pop("AGENT_USAGE_CLAUDE_NETWORK", None)
    env.pop("AGENT_USAGE_CODEX_NETWORK", None)
    env["HOME"] = str(home)
    env["XDG_CACHE_HOME"] = str(home / ".cache")
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    env["XDG_DATA_HOME"] = str(home / ".local/share")
    env["AGENT_USAGE_PROVIDERS"] = providers
    if extra_env:
        env.update(extra_env)
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

    def test_codex_live_query_replaces_stale_session_after_external_reset(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            session = home / ".codex/sessions/2026/09/04/session.jsonl"
            session.parent.mkdir(parents=True)
            session.write_text(json.dumps({
                "timestamp": "2026-09-04T12:00:00Z",
                "payload": {"rate_limits": {
                    "primary": {"used_percent": 99, "resets_at": 4102444800},
                    "secondary": {"used_percent": 72, "resets_at": 4102444800},
                    "plan_type": "plus",
                }},
            }) + "\n", encoding="utf-8")

            binary = home / "bin/codex"
            binary.parent.mkdir()
            binary.write_text("""#!/usr/bin/env python3
import json
import sys
for line in sys.stdin:
    request = json.loads(line)
    if request.get(\"id\") == 1:
        print(json.dumps({\"id\": 1, \"result\": {}}), flush=True)
    elif request.get(\"id\") == 2:
        print(json.dumps({
            \"id\": 2,
            \"result\": {
                \"rateLimits\": {\"primary\": {\"usedPercent\": 80}},
                \"rateLimitsByLimitId\": {\"codex\": {
                    \"primary\": {\"usedPercent\": 2, \"resetsAt\": 4102445800},
                    \"secondary\": {\"usedPercent\": 0, \"resetsAt\": 4102446800},
                    \"planType\": \"plus\"
                }}
            }
        }), flush=True)
""", encoding="utf-8")
            binary.chmod(0o755)

            codex = run_helper(home, "codex", {
                "AGENT_USAGE_CODEX_NETWORK": "1",
                "PATH": str(binary.parent) + os.pathsep + os.environ.get("PATH", ""),
            })["providers"][0]
            self.assertTrue(codex["available"])
            self.assertEqual("Codex account", codex["source"])
            self.assertEqual([2.0, 0.0], [item["used_percent"] for item in codex["windows"]])

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

    def test_ollama_without_key_stays_unavailable(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            ollama = run_helper(home, "ollama")["providers"][0]
            self.assertFalse(ollama["available"])
            self.assertEqual([], ollama["windows"])
            self.assertIn("API key", ollama["error"])

    def test_ollama_reads_key_file_and_network_response(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            key_path = home / ".config/kde-agents-usage/ollama-key"
            key_path.parent.mkdir(parents=True)
            key_path.write_text("synthetic-not-a-real-key\n", encoding="utf-8")

            received = {}

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    body = json.dumps({
                        "limits": {
                            "session": {"usage": 0.172},
                            "weekly": {"usage": 0.121},
                        }
                    }).encode()
                    received["auth"] = self.headers.get("Authorization", "")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

                def log_message(self, *args):
                    pass

            server = HTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                module = load_helper_module()
                module.OLLAMA_API = f"http://127.0.0.1:{server.server_port}/api/usage"
                module.HOME = home
                module.CACHE_DIR = home / ".cache/kde-agents-usage"
                env = {
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_CACHE_HOME": str(home / ".cache"),
                }
                with mock.patch.dict(os.environ, env, clear=True):
                    result = module.collect_ollama()
            finally:
                server.shutdown()
            self.assertEqual("Bearer synthetic-not-a-real-key", received.get("auth"))
            self.assertTrue(result["available"])
            self.assertEqual("ollama.com", result["source"])
            self.assertEqual([17.2, 12.1], [item["used_percent"] for item in result["windows"]])

    def test_ollama_uses_fresh_cache_and_never_stores_the_key(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            cache = home / ".cache/kde-agents-usage/ollama-usage.json"
            cache.parent.mkdir(parents=True)
            cache.write_text(json.dumps({
                "collected_at": 4102444800,
                "usage": {"session": 0.4, "weekly": 0.2},
            }), encoding="utf-8")
            key_path = home / ".config/kde-agents-usage/ollama-key"
            key_path.parent.mkdir(parents=True)
            key_path.write_text("synthetic-not-a-real-key\n", encoding="utf-8")
            original = cache.read_text(encoding="utf-8")
            module = load_helper_module()
            module.OLLAMA_API = "http://127.0.0.1:1/api/usage"
            module.HOME = home
            module.CACHE_DIR = cache.parent
            env = {
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(home / ".config"),
                "XDG_CACHE_HOME": str(home / ".cache"),
                "OLLAMA_API_KEY": "synthetic-not-a-real-key",
            }
            with mock.patch.dict(os.environ, env, clear=True):
                with mock.patch.object(time, "time", return_value=4102444900):
                    result = module.collect_ollama()
            self.assertTrue(result["available"])
            self.assertEqual("ollama.com cache", result["source"])
            self.assertEqual([40.0, 20.0], [item["used_percent"] for item in result["windows"]])
            self.assertEqual(original, cache.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
