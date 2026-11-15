"""사건 상세의 실제 Swift 정렬식을 실행하는 회귀 검사(리눅스용)."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EventArticleTests(unittest.TestCase):
    def test_event_articles_are_newest_first_across_countries(self):
        source = (ROOT / "ios/Meridian/Views/DigestScreen.swift").read_text()
        event = source.split("struct EventScreen: View {", 1)[1]
        self.assertNotIn("Dictionary(grouping:", event,
                         "사건 상세는 국가별로 기사를 묶지 않아야 합니다")
        match = re.search(r"ForEach\(items\.sorted\s*\{(.*?)\}\)\s*\{ a in", event, re.S)
        if match is None:
            self.fail("사건 상세에 최신순 정렬이 필요합니다")
        swift = shutil.which("swift") or str(Path.home() / ".local/swift/swift-6.0.3-RELEASE-ubuntu22.04-aarch64/usr/bin/swift")
        program = '''import Foundation
struct Article { let id: Int; let country: String; let sortAt: Date }
let items = [
    Article(id: 1, country: "KR", sortAt: Date(timeIntervalSince1970: 10)),
    Article(id: 2, country: "US", sortAt: Date(timeIntervalSince1970: 30)),
    Article(id: 3, country: "KR", sortAt: Date(timeIntervalSince1970: 20)),
    Article(id: 4, country: "JP", sortAt: Date(timeIntervalSince1970: 30))
]
let ordered = items.sorted { SORT }
precondition(ordered.map(\\.id) == [4, 2, 3, 1], "국가와 무관하게 최신순, 같은 시각이면 기사 번호 역순")
let empty: [Article] = []
precondition(empty.sorted { SORT }.isEmpty)
precondition(Array(items.prefix(1)).sorted { SORT }.map(\\.id) == [1])
print("PASS: mixed countries, equal dates, empty, single article")
'''.replace("SORT", match.group(1))
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)
        scratch = Path.home() / ".hermes/cache/scratch"
        with tempfile.TemporaryDirectory(prefix="meridian-order-", dir=scratch) as tmp:
            script = Path(tmp) / "main.swift"
            script.write_text(program)
            result = subprocess.run([swift, str(script)], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
