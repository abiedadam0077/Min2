"""Turns analyzer, test and build output into GitHub annotations (::error / ::warning).

Usage: python3 tool/ci_annotate.py <analyze|test|build> <logfile>
Annotations are the only failure details visible through the Checks API, so keep messages short.
"""

import re
import sys

MAX = 60


def escape(message: str) -> str:
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def emit(level: str, message: str, file: str | None = None, line: str | None = None) -> None:
    props = []
    if file:
        props.append(f"file={file}")
    if line:
        props.append(f"line={line}")
    prefix = f"::{level} {','.join(props)}::" if props else f"::{level}::"
    print(prefix + escape(message[:600]))


def main() -> int:
    mode, path = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    emitted = 0
    if mode == "analyze":
        pattern = re.compile(r"^\s*(error|warning|info)\s+[•\-|]\s+(.*?)\s+[•\-|]\s+(\S+?):(\d+):(\d+)\s+[•\-|]\s+(\S+)")
        for line in lines:
            match = pattern.match(line)
            if not match:
                continue
            level = {"error": "error", "warning": "warning", "info": "notice"}[match.group(1)]
            emit(level, f"{match.group(2)} [{match.group(6)}]", match.group(3), match.group(4))
            emitted += 1
            if emitted >= MAX:
                break
        if emitted == 0:
            # Fallback: the tail of the analyzer output explains failures that are not lint findings.
            tail = [line.strip() for line in lines if line.strip()][-25:]
            for line in tail:
                emit("error", line)
                emitted += 1
    elif mode == "test":
        for line in lines:
            if "[E]" in line or line.strip().startswith(("Expected:", "Actual:", "Which:")):
                emit("error", line.strip())
                emitted += 1
                if emitted >= MAX:
                    break
    elif mode == "build":
        index = 0
        while index < len(lines) and emitted < MAX:
            line = lines[index]
            if re.search(r"What went wrong|Execution failed for task|^e: |Error: |Exception:|\.dart:\d+:\d+: Error|FAILURE: Build failed", line):
                tail = " | ".join(part.strip() for part in lines[index: index + 7] if part.strip())
                emit("error", tail)
                emitted += 1
                index += 7
                continue
            index += 1
    print(f"Emitted {emitted} annotation(s) for {mode}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
