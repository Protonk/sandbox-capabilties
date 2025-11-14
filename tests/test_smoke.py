import unittest
from pathlib import Path

from probes import _runner


class TestRunnerParser(unittest.TestCase):
    """Smoke tests that ensure the shared runner stays wired correctly."""

    def test_parser_uses_artifacts_directory(self) -> None:
        parser = _runner.build_parser("demo_capability")
        args = parser.parse_args([])
        expected = Path("artifacts") / "demo_capability.json"
        self.assertEqual(args.output, expected)


if __name__ == "__main__":
    unittest.main()
