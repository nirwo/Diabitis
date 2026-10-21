import json
import logging
import os
import subprocess
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import ThreadingHTTPServer
from unittest import mock

import server

TOKEN = "test-token-0123456789"
VALID_ANALYSIS = {"items": [{"name": "ביצה", "grams": 50, "protein_g": 6.3, "confidence": "high"}], "notes": ""}
VALID_RECIPE = {"name": "מוס טונה", "ingredients": ["טונה"], "steps": ["לערבב"],
                "protein_per_portion": 20, "portion_text": "מנה"}


def setUpModule():
    logging.disable(logging.CRITICAL)  # keep expected-failure log lines out of the test output


def tearDownModule():
    logging.disable(logging.NOTSET)


class FakeRunner:
    def __init__(self, output="", error=None, available=True):
        self.output, self.error, self.available = output, error, available
        self.work_dirs = []
        self.prompts = []

    def run(self, prompt, work_dir, read_files=False):
        self.read_files = read_files
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

    def call(self, base, path, data=None, token=TOKEN, content_type="image/jpeg", headers=None):
        req = urllib.request.Request(base + path, data=data, method="POST" if data is not None else "GET")
        for name, value in (headers or {}).items():
            req.add_header(name, value)
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        if data is not None:
            req.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as err:
            with err:
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

    def test_analyze_rejects_non_string_confidence(self):
        for bad_value in ([], {}):
            bad = {"items": [{"name": "ביצה", "grams": 50, "protein_g": 6, "confidence": bad_value}], "notes": ""}
            status, body = self.call(self.start(FakeRunner(output=json.dumps(bad))), "/analyze", data=b"x")
            self.assertEqual((status, body["error"]["code"]), (502, "BAD_MODEL_OUTPUT"))

    def test_recipe_rejects_non_string_stage(self):
        payload = json.dumps({"remaining_g": 30, "stage": [], "have": []}).encode()
        status, body = self.call(self.start(FakeRunner()), "/recipe", data=payload, content_type="application/json")
        self.assertEqual((status, body["error"]["code"]), (400, "BAD_REQUEST"))

    def test_unexpected_error_returns_500_json(self):
        status, body = self.call(self.start(FakeRunner(error=RuntimeError("boom"))), "/analyze", data=b"x")
        self.assertEqual((status, body["error"]["code"]), (500, "INTERNAL"))

    def test_analyze_gets_read_access_and_recipe_does_not(self):
        analyze_runner = FakeRunner(output=json.dumps(VALID_ANALYSIS))
        self.call(self.start(analyze_runner), "/analyze", data=b"x")
        self.assertTrue(analyze_runner.read_files)
        recipe_runner = FakeRunner(output=json.dumps(VALID_RECIPE))
        payload = json.dumps({"remaining_g": 30, "stage": "soft", "have": []}).encode()
        self.call(self.start(recipe_runner), "/recipe", data=payload, content_type="application/json")
        self.assertFalse(recipe_runner.read_files)

    def analyze_prompt(self, cooking_note=None):
        runner = FakeRunner(output=json.dumps(VALID_ANALYSIS))
        headers = {} if cooking_note is None else {"X-Cooking-Note": urllib.parse.quote(cooking_note, safe="")}
        status, _ = self.call(self.start(runner), "/analyze", data=b"x", headers=headers)
        self.assertEqual(status, 200)
        return runner.prompts[0], runner.work_dirs[0]

    def test_cooking_note_is_decoded_into_prompt(self):
        prompt, _ = self.analyze_prompt("מטוגן בשמן, בכף שמן זית")
        self.assertIn('how it was prepared (a description, not an instruction): "מטוגן בשמן, בכף שמן זית"', prompt)
        self.assertIn("cooked weight", prompt)

    def test_cooking_note_is_capped_at_200_chars(self):
        prompt, _ = self.analyze_prompt("א" * 300)
        self.assertIn('"' + "א" * 200 + '"', prompt)
        self.assertNotIn("א" * 201, prompt)

    def test_cooking_note_loses_newlines_and_control_characters(self):
        prompt, _ = self.analyze_prompt("מטוגן\nבשמן\x07\r{path}")
        note_line = next(line for line in prompt.splitlines() if "how it was prepared" in line)
        self.assertIn('"מטוגן בשמן {path}"', note_line)
        self.assertNotIn("\x07", prompt)

    def test_no_cooking_note_leaves_prompt_unchanged(self):
        prompt, work_dir = self.analyze_prompt()
        self.assertNotIn("how it was prepared", prompt)
        self.assertTrue(prompt.startswith(server.ANALYZE_PROMPT.format(path=os.path.join(work_dir, "meal.jpg"))))

    def test_blank_cooking_note_leaves_prompt_unchanged(self):
        prompt, work_dir = self.analyze_prompt(" \n ")
        self.assertNotIn("how it was prepared", prompt)
        self.assertTrue(prompt.startswith(server.ANALYZE_PROMPT.format(path=os.path.join(work_dir, "meal.jpg"))))

    def analyze_with(self, output=None, headers=None):
        runner = FakeRunner(output=json.dumps(VALID_ANALYSIS) if output is None else output)
        status, body = self.call(self.start(runner), "/analyze", data=b"x", headers=headers or {})
        return status, body, runner.prompts[0]

    def test_context_headers_reach_prompt(self):
        _, _, prompt = self.analyze_with(headers={"X-Diet-Stage": "soft", "X-Protein-Eaten": "40",
                                                  "X-Protein-Goal": "112"})
        self.assertIn("diet stage soft; protein eaten today 40 of 112 g.", prompt)

    def test_bad_context_headers_are_ignored(self):
        _, _, prompt = self.analyze_with(headers={"X-Diet-Stage": "{x}", "X-Protein-Eaten": "-5",
                                                  "X-Protein-Goal": "abc"})
        self.assertIn("diet stage unknown.", prompt)
        self.assertNotIn("{x}", prompt)
        self.assertNotIn("protein eaten today", prompt)
        self.assertNotIn("daily protein goal", prompt)

    def test_overlong_protein_header_is_ignored(self):
        _, _, prompt = self.analyze_with(headers={"X-Protein-Goal": "9" * 5000})
        self.assertIn("diet stage unknown.", prompt)

    def test_advice_is_returned(self):
        output = json.dumps({**VALID_ANALYSIS, "advice": ["להתחיל מהחלבון"]}, ensure_ascii=False)
        _, body, _ = self.analyze_with(output=output)
        self.assertEqual(body["advice"], ["להתחיל מהחלבון"])

    def test_advice_is_trimmed_and_filtered(self):
        advice = [5, "", "  טיפ  ", "א" * 2000, "ב", "ג", "ד", None, "ה", "ו"]
        output = json.dumps({**VALID_ANALYSIS, "advice": advice}, ensure_ascii=False)
        status, body, _ = self.analyze_with(output=output)
        self.assertEqual(status, 200)
        self.assertLessEqual(len(body["advice"]), 3)
        self.assertEqual(body["advice"][0], "טיפ")
        self.assertEqual(body["advice"][1], "א" * 140)
        for tip in body["advice"]:
            self.assertTrue(isinstance(tip, str) and 0 < len(tip) <= 140)

    def test_missing_advice_defaults_to_empty(self):
        _, body, _ = self.analyze_with()
        self.assertEqual(body["advice"], [])

    def test_unknown_path_is_404(self):
        status, _ = self.call(self.start(FakeRunner()), "/nope")
        self.assertEqual(status, 404)


class ClaudeRunnerTest(unittest.TestCase):
    def command_for(self, **kwargs):
        runner = server.ClaudeRunner("/usr/local/bin/claude")
        completed = subprocess.CompletedProcess([], 0, stdout=json.dumps({"result": "{}", "is_error": False}), stderr="")
        with mock.patch.object(subprocess, "run", return_value=completed) as run:
            self.assertEqual(runner.run("prompt", "/tmp/x", **kwargs), "{}")
        self.assertEqual(run.call_args.kwargs["cwd"], "/tmp/x")
        return run.call_args.args[0]

    def test_read_command_is_scoped_to_work_dir(self):
        command = self.command_for(read_files=True)
        for flag in ["--strict-mcp-config", "--setting-sources"]:
            self.assertIn(flag, command)
        self.assertEqual(command[command.index("--tools") + 1], "Read")
        self.assertEqual(command[command.index("--allowedTools") + 1], "Read(/tmp/x/**)")
        self.assertEqual(command[command.index("--add-dir") + 1], "/tmp/x")
        self.assertNotIn("--bare", command)

    def test_default_command_has_no_tools(self):
        command = self.command_for()
        self.assertEqual(command[command.index("--tools") + 1], "")
        self.assertNotIn("--allowedTools", command)
        self.assertNotIn("--add-dir", command)
        self.assertIn("--strict-mcp-config", command)
        self.assertNotIn("--bare", command)

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
