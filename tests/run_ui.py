"""Run the graphical tests: the real game window against a game server.

    python3 tests/run_ui.py --love /path/to/love            # local stand-in server
    python3 tests/run_ui.py --love /path/to/love --live     # the project in online/config.lua

`--love` is a LÖVE 11.5 executable that is not bundled with a game (on macOS,
love.app/Contents/MacOS/love). The solo scenario plays one whole match against the
computer; the duel scenario starts two windows that play each other through a room code.
Set TT_CAPTURE_DIR to a folder to save screenshots.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--love", required=True)
    parser.add_argument("--live", action="store_true", help="use the server in online/config.lua")
    parser.add_argument("--port", type=int, default=8791)
    parser.add_argument("--only", choices=["solo", "duel"])
    parser.add_argument("--http", help="force one HTTP backend: https, libcurl or command")
    args = parser.parse_args()
    backend, server = [], None
    if not args.live:
        server = subprocess.Popen([sys.executable, "tests/mock_backend.py", "--port", str(args.port)], cwd=ROOT)
        time.sleep(1.0)
        backend = ["--backend", f"http://127.0.0.1:{args.port}", "--key", "test-key"]
    if args.http:
        backend += ["--http", args.http]

    def game(scenario, profile, env):
        return subprocess.Popen([args.love, str(ROOT), *backend, "--profile", profile, "--ui-test", scenario],
                                env={**os.environ, **env})

    failed = []
    try:
        if args.only != "duel":
            code = game("solo", "solo", {}).wait(timeout=900)
            print("solo:", "ok" if code == 0 else f"FAILED ({code})")
            if code != 0:
                failed.append("solo")
        if args.only != "solo":
            with tempfile.TemporaryDirectory() as folder:
                env = {"TT_ROOM_FILE": str(Path(folder) / "room.txt")}
                host, guest = game("host", "host", env), game("guest", "guest", env)
                codes = [host.wait(timeout=1500), guest.wait(timeout=1500)]
            print("duel:", "ok" if codes == [0, 0] else f"FAILED {codes}")
            if codes != [0, 0]:
                failed.append("duel")
    finally:
        if server:
            server.terminate()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
