from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import UTC, datetime
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


mayor_sdk = _load_module("mayor_sdk", PROJECT_ROOT / "sdk" / "mayor_sdk.py")
chat_inventory = _load_module("chat_inventory", PROJECT_ROOT / "sdk" / "chat_inventory.py")


class MayorSdkTests(unittest.TestCase):
    def test_manifest_and_project_contracts(self):
        manifest = mayor_sdk.load_manifest()
        self.assertEqual(1, manifest["schema_version"])
        failures = [
            item
            for item in mayor_sdk._check_required_paths(manifest)
            + mayor_sdk._check_project_contracts(manifest)
            if item.status == "fail"
        ]
        self.assertEqual([], failures)

    def test_assertion_count_is_derived_from_live_tests(self):
        matrix = json.loads(
            (PROJECT_ROOT / "tests" / "assertion_matrix.json").read_text(encoding="utf-8-sig")
        )
        tests = matrix["tests"]
        self.assertNotIn("expected_test_count", matrix)
        self.assertGreater(len(tests), 0)
        self.assertEqual(len(tests), len({item["id"] for item in tests}))
        self.assertEqual(len(tests), len({item["script"] for item in tests}))
        self.assertTrue(
            {
                "transport_network_system",
                "transport_network_layer",
                "transport_planning_panel",
                "transport_coordinator_integration",
                "transport_network_integration",
            }.issubset({item["id"] for item in tests})
        )

        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(0, mayor_sdk._cmd_tests(True))
        inventory = json.loads(output.getvalue())
        self.assertEqual(inventory["test_count"], len(inventory["tests"]))

        runner = (PROJECT_ROOT / "tools" / "run_assertion_matrix.ps1").read_text(
            encoding="utf-8-sig"
        )
        self.assertIn("$allTests.Count", runner)
        self.assertNotIn("$manifest.expected_test_count", runner)
        self.assertIn("Read-Utf8FileWithRetry", runner)
        self.assertIn("$process.Dispose()", runner)

        workflow = (
            PROJECT_ROOT / ".github" / "workflows" / "godot-ci.yml"
        ).read_text(encoding="utf-8")
        import_step = workflow.index("- name: Import project assets")
        assertion_step = workflow.index("- name: Run isolated assertion manifest")
        self.assertLess(import_step, assertion_step)
        self.assertIn(
            "--headless --path . --import",
            workflow[import_step:assertion_step],
        )

        release_runner = (
            PROJECT_ROOT / "tools" / "write_release_evidence.ps1"
        ).read_text(encoding="utf-8-sig")
        self.assertIn("$manifestTests.Count", release_runner)
        self.assertIn("unique ids and scripts", release_runner)
        self.assertNotIn("$manifest.expected_test_count", release_runner)

    def test_version_inventory_keeps_layers_explicit_and_consistent(self):
        manifest = mayor_sdk.load_manifest()
        inventory = mayor_sdk._version_inventory(manifest)
        self.assertEqual(
            inventory["release"]["file_version"],
            inventory["release"]["product_version"],
        )
        self.assertTrue(inventory["sdk"]["compatible"])
        self.assertEqual(1, len(set(inventory["content"].values())))
        self.assertNotIn(None, inventory["schemas"].values())
        failures = [
            item for item in mayor_sdk._check_version_contracts(manifest) if item.status == "fail"
        ]
        self.assertEqual([], failures)

    def test_git_inventory_distinguishes_unborn_repository_from_commit(self):
        with tempfile.TemporaryDirectory() as temp:
            marker = Path(temp) / ".git"
            (marker / "refs" / "heads").mkdir(parents=True)
            (marker / "HEAD").write_text("ref: refs/heads/main\n", encoding="ascii")
            self.assertEqual("initialized_unborn", mayor_sdk._git_status(marker))
            (marker / "refs" / "heads" / "main").write_text("a" * 40 + "\n", encoding="ascii")
            self.assertEqual("repository", mayor_sdk._git_status(marker))

    def test_sdk_version_must_satisfy_project_contract(self):
        self.assertTrue(mayor_sdk._version_in_range("1.0.0", ">=1.0.0 <2.0.0"))
        self.assertFalse(mayor_sdk._version_in_range("2.0.0", ">=1.0.0 <2.0.0"))

    def test_parser_exposes_version_and_chat_maintenance_commands(self):
        parser = mayor_sdk.build_parser()
        self.assertEqual("version", parser.parse_args(["version", "--json"]).command)
        chats = parser.parse_args(["chats", "--since-days", "7", "--json"])
        self.assertEqual("chats", chats.command)
        self.assertEqual(7, chats.since_days)

    def test_chat_classifier_is_case_insensitive_and_multilabel(self):
        topics = chat_inventory.classify_text("請用 GUI 測試 NPC 地圖並截圖")
        self.assertIn("qa_and_evidence", topics)
        self.assertIn("npc_and_population", topics)
        self.assertIn("buildings_and_map", topics)

    def test_chat_analyzer_does_not_emit_raw_text(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project = root / "project"
            sessions = root / "sessions"
            project.mkdir()
            sessions.mkdir()
            records = [
                {
                    "type": "session_meta",
                    "payload": {"id": "example", "cwd": str(project), "thread_source": "user"},
                },
                {
                    "type": "response_item",
                    "payload": {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": "秘密 NPC 地圖測試"}],
                    },
                },
            ]
            (sessions / "example.jsonl").write_text(
                "\n".join(json.dumps(item, ensure_ascii=False) for item in records) + "\n",
                encoding="utf-8",
            )
            report = chat_inventory.analyze(sessions, project)
            serialized = json.dumps(report, ensure_ascii=False)
            self.assertNotIn("秘密", serialized)
            self.assertEqual(1, report["session_counts"]["user"])

    def test_chat_analyzer_can_limit_sessions_by_start_time(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project = root / "project"
            sessions = root / "sessions"
            project.mkdir()
            sessions.mkdir()
            for name, timestamp in (
                ("old", "2026-07-01T00:00:00Z"),
                ("recent", "2026-08-01T12:00:00Z"),
            ):
                records = [
                    {
                        "type": "session_meta",
                        "timestamp": timestamp,
                        "payload": {
                            "id": name,
                            "timestamp": timestamp,
                            "cwd": str(project),
                            "thread_source": "user",
                        },
                    },
                    {
                        "type": "response_item",
                        "payload": {
                            "type": "message",
                            "role": "user",
                            "content": [{"type": "input_text", "text": "交通版本測試"}],
                        },
                    },
                ]
                (sessions / f"{name}.jsonl").write_text(
                    "\n".join(json.dumps(item, ensure_ascii=False) for item in records) + "\n",
                    encoding="utf-8",
                )
            report = chat_inventory.analyze(
                sessions,
                project,
                since=datetime(2026, 8, 1, tzinfo=UTC),
            )
            self.assertEqual(["recent"], report["root_session_ids"])
            self.assertEqual(1, report["topic_chat_counts"]["transport_and_topology"])
            self.assertEqual(1, report["topic_chat_counts"]["versioning_and_migrations"])

    def test_chat_markdown_retains_counts_but_not_raw_messages(self):
        report = {
            "session_counts": {"user": 1, "subagent": 0},
            "root_user_messages": 1,
            "root_user_characters": 8,
            "topic_chat_counts": {"transport_and_topology": 1},
            "error_signature_counts": {"python_discovery_or_access": 1},
            "unreadable_files": 0,
            "window_start": None,
        }
        rendered = chat_inventory.render_markdown(report)
        self.assertIn("player-authored connected networks", rendered)
        self.assertIn("distinguish not found from access denied", rendered)
        self.assertNotIn("秘密", rendered)

    def test_wrapper_has_project_and_codex_python_fallbacks(self):
        wrapper = (PROJECT_ROOT / "sdk" / "mayor-sdk.ps1").read_text(encoding="utf-8")
        self.assertIn("MAYOR_SDK_PYTHON", wrapper)
        self.assertIn("MAYOR_PROJECT_ROOT", wrapper)
        self.assertIn(".venv\\Scripts\\python.exe", wrapper)
        self.assertIn(".cache\\codex-runtimes", wrapper)


if __name__ == "__main__":
    unittest.main()
