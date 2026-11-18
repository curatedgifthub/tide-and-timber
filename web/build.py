"""Build into web/dist with Python 3 and Lua. Install the pinned runtime with npm ci."""
import json
import shutil
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

WEB = Path(__file__).resolve().parent
ROOT = WEB.parent
sys.path.insert(0, str(ROOT / "scripts"))
from publish_rules import bundle


def copy_rules(site, modules):
    # Only the dependencies of the public mirror, score and placement helpers.
    required = ("util", "rules", "data.cards", "data.factions", "abilities",
                "chains", "decks", "battle", "online.json", "online.mirror", "tabletop.placement")
    modules["online.mirror"] = (ROOT / "online/mirror.lua").read_text(encoding="utf-8")
    modules["tabletop.placement"] = (ROOT / "tabletop/placement.lua").read_text(encoding="utf-8")
    with (site / "public-rules.lua").open("w", encoding="utf-8") as script:
        for name in required:
            script.write(f'package.preload["{name}"] = function(...)\n{modules[name]}\nend\n')
        script.write((WEB / "metrics.lua").read_text(encoding="utf-8"))

    packages = WEB / "node_modules"
    shutil.copyfile(packages / "fengari-web/dist/fengari-web.js", site / "fengari-web.js")
    licenses = site / "licenses"
    licenses.mkdir()
    for name in ("fengari-web", "fengari", "fengari-interop", "sprintf-js"):
        shutil.copyfile(packages / name / "LICENSE", licenses / f"{name}.txt")


def build():
    exported = subprocess.check_output(["lua", str(WEB / "export.lua")], cwd=ROOT)
    catalog = json.loads(exported)
    catalog["rules"], modules = bundle()
    if not catalog["config"]["key"].startswith("sb_publishable_"):
        sys.exit("Expected a public Supabase publishable key in online/config.lua.")

    with TemporaryDirectory(dir=WEB) as temporary:
        site = Path(temporary) / "site"
        shutil.copytree(WEB / "src", site, ignore=shutil.ignore_patterns(".*"))
        copy_rules(site, modules)
        for card in catalog["cards"].values():
            relative = Path(card["art"]).relative_to("tabletop/assets")
            destination = site / "assets" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / card["art"], destination)
            card["art"] = "./assets/" + relative.as_posix()
        shutil.copytree(ROOT / "tabletop/assets/fonts", site / "assets/fonts",
                        ignore=shutil.ignore_patterns(".*"))
        (site / "catalog.json").write_text(
            json.dumps(catalog, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
            encoding="utf-8")
        # Stage everything first so a missing thumbnail cannot replace a working build.
        output = WEB / "dist"
        if output.exists():
            shutil.rmtree(output)
        site.rename(output)

    print(f"Built {len(catalog['cards'])} cards with rules {catalog['rules']} in {output}")


if __name__ == "__main__":
    build()
