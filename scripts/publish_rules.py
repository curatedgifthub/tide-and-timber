"""Publish the game's rules to the Supabase project the game is configured for.

The server runs the same Lua files the game ships with (online/manifest.lua). Run this
after changing cards, abilities or any other listed file, and before packaging:

    python3 scripts/publish_rules.py            # upload
    python3 scripts/publish_rules.py --check    # only print the version and bundle size

The upload is authorised by a secret kept in supabase/.publish_secret (created on first
run). Its SHA-256 digest has to be registered once in the project; the script prints the
SQL for that if the server refuses the upload.
"""
import argparse
import hashlib
import json
import re
import secrets
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECRET = ROOT / "supabase/.publish_secret"


def manifest():
    text = (ROOT / "online/manifest.lua").read_text()
    return re.findall(r"^\s*\{'([^']+)','([^']+)'\},", text, re.M)


def bundle():
    """Returns (version, {module: source}). Must match online/rules.lua."""
    modules, digest = {}, hashlib.sha256()
    for name, path in manifest():
        data = (ROOT / path).read_bytes()
        digest.update(name.encode() + b"\0" + data + b"\0")
        modules[name] = data.decode("utf-8")
    return digest.hexdigest()[:16], modules


def config():
    text = (ROOT / "online/config.lua").read_text()
    values = dict(re.findall(r'^\s*(url|key)\s*=\s*"([^"]*)"', text, re.M))
    if not values.get("url") or not values.get("key"):
        sys.exit("online/config.lua has no project url and key yet.")
    return values["url"].rstrip("/"), values["key"]


def secret():
    if not SECRET.exists():
        SECRET.write_text(secrets.token_urlsafe(48) + "\n")
        SECRET.chmod(0o600)
    return SECRET.read_text().strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="print the version without uploading")
    parser.add_argument("--digest", action="store_true", help="print the publish secret's digest and exit")
    args = parser.parse_args()
    version, modules = bundle()
    size = sum(len(source) for source in modules.values())
    if args.digest:
        print(hashlib.sha256(secret().encode()).hexdigest())
        return
    print(f"rules {version}: {len(modules)} files, {size // 1024} KB")
    if args.check:
        return
    url, key = config()
    body = json.dumps({"p_secret": secret(), "p_version": version, "p_modules": modules}).encode()
    request = urllib.request.Request(url + "/rest/v1/rpc/publish_rules", data=body, method="POST", headers={
        "apikey": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            print("published", json.loads(response.read()))
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        if error.code in (401, 403) or "42501" in detail or "not allowed" in detail:
            digest = hashlib.sha256(secret().encode()).hexdigest()
            sys.exit("The project does not know this machine's publish secret. Run this once in the\n"
                     "Supabase SQL editor, then publish again:\n\n"
                     f"  insert into public.deploy_keys (digest) values ('{digest}');\n")
        sys.exit(f"Upload failed (HTTP {error.code}): {detail}")


if __name__ == "__main__":
    main()
