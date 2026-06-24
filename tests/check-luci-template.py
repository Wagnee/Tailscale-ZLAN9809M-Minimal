#!/usr/bin/env python3

import re
import subprocess
import sys
import tempfile
from pathlib import Path


def compile_template(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    chunks = []
    position = 0

    for match in re.finditer(r"<%(.*?)%>", source, re.DOTALL):
        tag = match.group(1)
        position = match.end()
        if tag.startswith("+"):
            continue
        if tag.startswith("="):
            chunks.append("local __template_value = (" + tag[1:] + ")\n")
        else:
            chunks.append(tag + "\n")

    if position == 0:
        raise SystemExit(f"no LuCI template tags found in {path}")

    with tempfile.NamedTemporaryFile("w", suffix=".lua", encoding="utf-8", delete=False) as output:
        output.write("".join(chunks))
        generated = Path(output.name)

    try:
        subprocess.run(["luac5.1", "-p", str(generated)], check=True)
    finally:
        generated.unlink(missing_ok=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: check-luci-template.py TEMPLATE")
    compile_template(Path(sys.argv[1]))
