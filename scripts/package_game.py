"""Build the portable LÖVE project and optionally a local macOS application."""
import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ("abilities", "ai", "battle", "chains", "decks", "rules", "util")


def portable():
    sources = [ROOT / name for name in ("main.lua", "conf.lua", "tests/ui_smoke.lua")]
    engine = ROOT / "card_battle_sim"
    sources.extend(engine / (name + ".lua") for name in ENGINE)
    sources.extend((engine / "data").glob("*.lua"))
    sources.extend(p for p in (ROOT / "tabletop").rglob("*")
                   if p.is_file() and p.suffix in {".lua", ".png", ".ttf", ".txt"})
    # Online play: networking, and the server-side rule files the client hashes to check
    # that it runs the same rules as the server (online/manifest.lua).
    sources.extend((ROOT / "online").glob("*.lua"))
    target = ROOT / "Tide and Timber.love"
    with tempfile.NamedTemporaryFile(dir=ROOT, delete=False) as tmp:
        name = tmp.name
    try:
        with ZipFile(name, "w", ZIP_DEFLATED) as package:
            for path in sorted(sources):
                package.write(path, path.relative_to(ROOT))
        os.chmod(name, 0o644)
        os.replace(name, target)
    finally:
        Path(name).unlink(missing_ok=True)
    return target


def mac_app(runtime, game):
    target = ROOT / "Tide and Timber.app"
    if target.exists():
        with (target / "Contents/Info.plist").open("rb") as existing:
            if plistlib.load(existing).get("CFBundleIdentifier") != "local.tide-and-timber.game":
                raise ValueError(f"Unexpected application at {target}")
    with tempfile.TemporaryDirectory(dir=ROOT) as work:
        app = Path(work) / target.name
        shutil.copytree(runtime, app, symlinks=True)
        plist = app / "Contents/Info.plist"
        with plist.open("rb") as source:
            info = plistlib.load(source)
        info.update(CFBundleName="Tide and Timber", CFBundleDisplayName="Tide & Timber",
                    CFBundleIdentifier="local.tide-and-timber.game",
                    CFBundleShortVersionString="0.2", CFBundleVersion="2")
        for key in ("CFBundleDocumentTypes", "UTExportedTypeDeclarations"):
            info.pop(key, None)
        with plist.open("wb") as out:
            plistlib.dump(info, out)
        shutil.copyfile(game, app / "Contents/Resources/game.love")
        for framework in sorted((app / "Contents/Frameworks").glob("*.framework")):
            subprocess.run(["codesign", "--force", "--sign", "-", str(framework)], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        previous = Path(work) / "previous.app"
        if target.exists():
            target.rename(previous)
        try:
            app.rename(target)
        except OSError:
            if previous.exists():
                previous.rename(target)
            raise
    return target


def check_online():
    """A packaged game must know its server, and the server must already run these rules."""
    import re
    text = (ROOT / "online/config.lua").read_text()
    values = dict(re.findall(r'^\s*(url|key)\s*=\s*"([^"]*)"', text, re.M))
    if not values.get("url") or not values.get("key"):
        print("warning: online/config.lua has no server yet; the packaged game cannot play online.")
    elif values["key"].startswith("sb_secret_") or "service_role" in values["key"]:
        raise ValueError("online/config.lua holds a secret key. Use the publishable (anon) key.")


if __name__ == "__main__":
    check_online()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mac-runtime", type=Path, help="path to the official LÖVE 11.5 love.app")
    runtime = parser.parse_args().mac_runtime
    game = portable()
    print(game)
    if runtime:
        print(mac_app(runtime, game))
