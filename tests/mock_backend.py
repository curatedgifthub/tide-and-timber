"""A local stand-in for the Supabase project, for running the game without the internet.

    python3 tests/mock_backend.py --port 8787
    love . --backend http://127.0.0.1:8787 --key test-key

It serves the same three endpoints the game uses (anonymous sign-in, the "game" function and
the match_state RPC). Every request is handed to tests/devhost.lua, which runs the real
rules server from online/server.lua; this file is only the HTTP shell around it.
"""
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = threading.Lock()


def rules_version():
    digest = hashlib.sha256()
    text = (ROOT / "online/manifest.lua").read_text()
    for name, path in re.findall(r"^\s*\{'([^']+)','([^']+)'\},", text, re.M):
        digest.update(name.encode() + b"\0" + (ROOT / path).read_bytes() + b"\0")
    return digest.hexdigest()[:16]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        server = self.server
        if server.delay:
            time.sleep(server.delay)
        request = {"method": "POST", "path": self.path.split("?")[0], "body": body, "clock": int(time.time()),
                   "headers": {k.lower(): v for k, v in self.headers.items()},
                   "key": server.key, "rules": server.rules, "token_life": server.token_life}
        with LOCK:
            done = subprocess.run(["lua", "tests/devhost_cli.lua", server.state], cwd=ROOT,
                                  input=json.dumps(request), capture_output=True, text=True)
        if done.returncode != 0:
            status, payload = 500, json.dumps({"message": done.stderr.strip()[-400:]})
        else:
            result = json.loads(done.stdout)
            status, payload = result["status"], result["body"]
        data = payload.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        if self.server.verbose:
            super().log_message(*args)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--key", default="test-key")
    parser.add_argument("--rules", help="rules version to announce (default: the version of this checkout)")
    parser.add_argument("--token-life", type=int, default=3600, help="seconds before a sign-in expires")
    parser.add_argument("--delay", type=float, default=0, help="seconds to wait before answering")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.key, server.rules, server.token_life = args.key, args.rules or rules_version(), args.token_life
    server.delay, server.verbose = args.delay, args.verbose
    with tempfile.TemporaryDirectory() as folder:
        server.state = str(Path(folder) / "state.json")
        print(f"mock backend on http://127.0.0.1:{args.port}  key {args.key}  rules {server.rules}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
