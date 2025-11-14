import os
import unittest
from pathlib import Path
from unittest import mock

from probes import _runner


class TestRunnerParser(unittest.TestCase):
    """Smoke tests that ensure the shared runner stays wired correctly."""

    @mock.patch.dict(os.environ, {}, clear=False)
    def test_parser_defaults_to_capability_slug_without_probe_id(self) -> None:
        os.environ.pop("PROBE_ID", None)
        parser = _runner.build_parser("demo_capability")
        args = parser.parse_args([])
        expected = Path("artifacts") / "demo_capability.json"
        self.assertEqual(args.output, expected)

    @mock.patch.dict(os.environ, {}, clear=False)
    def test_parser_prefers_probe_id_when_set(self) -> None:
        os.environ["PROBE_ID"] = "core__demo__specimen"
        parser = _runner.build_parser("demo_capability")
        args = parser.parse_args([])
        expected = Path("artifacts") / "core__demo__specimen.json"
        self.assertEqual(args.output, expected)


if __name__ == "__main__":
    unittest.main()
