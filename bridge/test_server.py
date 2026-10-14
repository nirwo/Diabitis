import json
import os
import subprocess
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest import mock

import server

TOKEN = "test-token-0123456789"
VALID_ANALYSIS = {"items": [{"name": "ביצה", "grams": 50, "protein_g": 6.3, "confidence": "high"}], "notes": ""}
VALID_RECIPE = {"name": "מוס טונה", "ingredients": ["טונה"], "steps": ["לערבב"],
                "protein_per_portion": 20, "portion_text": "מנה"}


class FakeRunner:
    def __init__(self, output="", error=None, available=True):
        self.output, self.error, self.available = output, error, available
        self.work_dirs = []
        self.prompts = []

    def run(self, prompt, work_dir):
        self.prompts.append(prompt)
        self.work_dirs.append(work_dir)
        if self.error:
            raise self.error
        return self.output

    def is_available(self):
        return self.available


class BridgeServerTest(unittest.TestCase):
    def start(self, runner):
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.make_handler(TOKEN, runner))
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        self.addCleanup(httpd.server_close)
        self.addCleanup(httpd.shutdown)
        return f"http://127.0.0.1:{httpd.server_address[1]}"

    def call(self, base, path, data=None, token=TOKEN, content_type="image/jpeg"):
        req = urllib.request.Request(base + path, data=data, method="POST" if data is not None else "GET")
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        if data is not None:
            req.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as err:
            return err.code, json.loads(err.read())

    def test_rejects_missing_token(self):
        status, body = self.call(self.start(FakeRunner()), "/health", token=None)
        self.assertEqual((status, body["error"]["code"]), (401, "UNAUTHORIZED"))

    def test_rejects_wrong_token(self):
        status, _ = self.call(self.start(FakeRunner()), "/health", token="wrong")
        self.assertEqual(status, 401)

    def test_health_reports_claude_availability(self):
        status, body = self.call(self.start(FakeRunner(available=False)), "/health")
        self.assertEqual((status, body), (200, {"status": "ok", "claude": False}))

    def test_analyze_returns_validated_items_from_fenced_output(self):
        runner = FakeRunner(output="Here you go:\n```json\n" + json.dumps(VALID_ANALYSIS, ensure_ascii=False) + "\n```")
        status, body = self.call(self.start(runner), "/analyze", data=b"\xff\xd8jpeg")
        self.assertEqual(status, 200)
        self.assertEqual(body["items"][0]["protein_g"], 6.3)
        self.assertIn("meal.jpg", runner.prompts[0])

    def test_analyze_deletes_temp_image(self):
        runner = FakeRunner(output=json.dumps(VALID_ANALYSIS))
        self.call(self.start(runner), "/analyze", data=b"\xff\xd8jpeg")
        self.assertFalse(os.path.exists(runner.work_dirs[0]))

    def test_analyze_rejects_garbage(self):
        status, body = self.call(self.start(FakeRunner(output="I think it's an egg")), "/analyze", data=b"x")
        self.assertEqual((status, body["error"]["code"]), (502, "BAD_MODEL_OUTPUT"))

    def test_analyze_rejects_implausible_protein(self):
        bad = {"items": [{"name": "עוף", "grams": 100, "protein_g": 500, "confidence": "high"}], "notes": ""}
        status, _ = self.call(self.start(FakeRunner(output=json.dumps(bad))), "/analyze", data=b"x")
        self.assertEqual(status, 502)

    def test_analyze_rejects_protein_heavier_than_food(self):
        bad = {"items": [{"name": "עוף", "grams": 20, "protein_g": 30, "confidence": "high"}], "notes": ""}
        status, _ = self.call(self.start(FakeRunner(output=json.dumps(bad))), "/analyze", data=b"x")
        self.assertEqual(status, 502)

    def test_analyze_rejects_oversized_body(self):
        with mock.patch.object(server, "MAX_IMAGE_BYTES", 10):
            status, body = self.call(self.start(FakeRunner()), "/analyze", data=b"x" * 11)
        self.assertEqual((status, body["error"]["code"]), (413, "TOO_LARGE"))

    def test_analyze_maps_claude_failure(self):
        runner = FakeRunner(error=server.ClaudeUnavailableError("not logged in"))
        status, body = self.call(self.start(runner), "/analyze", data=b"x")
        self.assertEqual((status, body["error"]["code"]), (503, "CLAUDE_UNAVAILABLE"))

    def test_analyze_maps_timeout(self):
        runner = FakeRunner(error=subprocess.TimeoutExpired("claude", 1))
        status, body = self.call(self.start(runner), "/analyze", data=b"x")
        self.assertEqual((status, body["error"]["code"]), (504, "TIMEOUT"))

    def test_recipe_rejects_unknown_stage(self):
        payload = json.dumps({"remaining_g": 30, "stage": "banana", "have": []}).encode()
        status, body = self.call(self.start(FakeRunner()), "/recipe", data=payload, content_type="application/json")
        self.assertEqual((status, body["error"]["code"]), (400, "BAD_REQUEST"))

    def test_recipe_returns_suggestion_and_passes_context(self):
        runner = FakeRunner(output=json.dumps(VALID_RECIPE, ensure_ascii=False))
        payload = json.dumps({"remaining_g": 35, "stage": "soft", "have": ["ביצים"]}).encode()
        status, body = self.call(self.start(runner), "/recipe", data=payload, content_type="application/json")
        self.assertEqual((status, body["name"]), (200, "מוס טונה"))
        self.assertIn("מזון רך", runner.prompts[0])
        self.assertIn("ביצים", runner.prompts[0])

    def test_unknown_path_is_404(self):
        status, _ = self.call(self.start(FakeRunner()), "/nope")
        self.assertEqual(status, 404)


class ClaudeRunnerTest(unittest.TestCase):
    def test_command_restricts_tools_and_settings(self):
        runner = server.ClaudeRunner("/usr/local/bin/claude")
        completed = subprocess.CompletedProcess([], 0, stdout=json.dumps({"result": "{}", "is_error": False}), stderr="")
        with mock.patch.object(subprocess, "run", return_value=completed) as run:
            self.assertEqual(runner.run("prompt", "/tmp/x"), "{}")
        command = run.call_args.args[0]
        for flag in ["--tools", "--allowedTools", "--strict-mcp-config", "--setting-sources", "--add-dir"]:
            self.assertIn(flag, command)
        self.assertEqual(command[command.index("--tools") + 1], "Read")
        self.assertNotIn("--bare", command)
        self.assertEqual(run.call_args.kwargs["cwd"], "/tmp/x")

    def test_event_array_envelope_is_unwrapped(self):
        runner = server.ClaudeRunner("/usr/local/bin/claude")
        events = [{"type": "system"}, {"type": "assistant"}, {"type": "result", "result": "{}", "is_error": False}]
        completed = subprocess.CompletedProcess([], 0, stdout=json.dumps(events), stderr="")
        with mock.patch.object(subprocess, "run", return_value=completed):
            self.assertEqual(runner.run("prompt", "/tmp/x"), "{}")

    def test_envelope_without_result_is_bad_output(self):
        runner = server.ClaudeRunner("/usr/local/bin/claude")
        completed = subprocess.CompletedProcess([], 0, stdout=json.dumps([{"type": "system"}]), stderr="")
        with mock.patch.object(subprocess, "run", return_value=completed):
            with self.assertRaises(server.ModelOutputError):
                runner.run("prompt", "/tmp/x")

    def test_missing_binary_is_unavailable(self):
        runner = server.ClaudeRunner("")
        self.assertFalse(runner.is_available())
        with self.assertRaises(server.ClaudeUnavailableError):
            runner.run("prompt", "/tmp")


if __name__ == "__main__":
    unittest.main()
