"""Build the Workspaces for Helium installer from out/Default (roadmap Phase 2, LOCAL.md 56).

    python local/package-installer.py [fix]

Writes <local-path>\\Helium-workspace\\dist\\workspaces-for-helium_<version>_x64-setup.exe and prints its SHA-256. <version>
is the owner's scheme (2026-11-09): 1.<Helium minor>.<Chromium major>.<fix>, e.g. 1.21.157.00 -- the Helium and
Chromium bases the binary was built on (a newer Helium on the same Chromium keeps them), <fix> the release on that
base, two digits, 00 first (the optional argument). Before the first public one (1.21.157.00) it was
0.<Helium minor>.<Chromium major>.<patch count>. Windows shows it in Installed apps (DisplayVersion). The files are FILES.cfg's list, as Helium's own package.py zips them; the installer itself is
local/installer/helium-workspaces.nsi (NSIS 3, `winget install NSIS.NSIS`). Refuses when chrome.dll is
older than a local/workspaces patch: an installer of a stale binary.
"""
import hashlib
import subprocess
import sys
from pathlib import Path

WS = Path(r"<local-path>\Helium-workspace")
HW = WS / "helium-windows"
OUT = HW / "build" / "src" / "out" / "Default"
REPO = Path(__file__).resolve().parent.parent
HERE = REPO / "local" / "installer"
DIST = WS / "dist"
MAKENSIS = Path(r"C:\Program Files (x86)\NSIS\makensis.exe")

sys.path.insert(0, str(HW / "helium-chromium" / "utils"))
import filescfg  # noqa: E402  Helium's own, as its package.py uses it

newest_patch = max(p.stat().st_mtime for p in (REPO / "patches" / "local" / "workspaces").glob("*.patch"))
if (OUT / "chrome.dll").stat().st_mtime < newest_patch:
    sys.exit("out/Default/chrome.dll is older than a local/workspaces patch: build first (resume-build.ps1)")
# Helium's word swap (LOCAL.md 5.7) is in the build: the English pack keeps one "Chromium" (the credit link); 661
# without it.
if (OUT / "locales" / "en-US.pak").read_bytes().count(b"Chromium") > 5:
    sys.exit("out/Default says 'Chromium' in its strings: apply the word swap (LOCAL.md 5.7), rebuild, then package")

# The bases the binary was built on, read off chrome.dll itself, not whatever the tree says now (a rebase changes
# the tree first): its FileVersion is Helium's (0.18.2.1), its ProductVersion Chromium's (154.0.8037.92).
helium, chromium = subprocess.run(
    ["powershell", "-NoProfile", "-Command",
     f"$v = (Get-Item -LiteralPath '{OUT / 'chrome.dll'}').VersionInfo; $v.FileVersion; $v.ProductVersion"],
    capture_output=True, text=True, check=True).stdout.split()
parts = [helium.split(".")[1], chromium.split(".")[0]]
if not all(x.isdigit() for x in parts):
    sys.exit(f"chrome.dll says Helium {helium!r}, Chromium {chromium!r}: not the expected numbers")
fix = sys.argv[1] if len(sys.argv) > 1 else "0"
if not (fix.isdigit() and int(fix) <= 99):
    sys.exit(f"the fix number is 0..99, not {fix!r}")
version = f"1.{parts[0]}.{parts[1]}.{int(fix):02d}"

excluded = {Path("mini_installer.exe"), Path("mini_installer_exe_version.rc"), Path("setup.exe"),
            Path("helium.packed.7z")}
files = sorted(filescfg.filescfg_generator(HW / "build" / "src" / "chrome" / "tools" / "build" / "win" / "FILES.cfg",
                                           OUT, "64bit", excluded))
if not files:
    sys.exit(f"FILES.cfg matched nothing in {OUT}")

DIST.mkdir(exist_ok=True)
nsh = DIST / "files.nsh"
lines = []
for folder in sorted({f.parent for f in files}):
    lines.append(f'SetOutPath "$INSTDIR\\{folder}"' if folder != Path(".") else 'SetOutPath "$INSTDIR"')
    lines += [f'File "{OUT / f}"' for f in files if f.parent == folder]
nsh.write_text("\n".join(lines) + "\n", encoding="utf-8")

setup = DIST / f"workspaces-for-helium_{version}_x64-setup.exe"
# A release's file is never replaced: other code on the same base is the next fix number (the argument).
if setup.exists():
    sys.exit(f"{setup.name} exists: pass the next fix number, or move the old file away first")
subprocess.run([str(MAKENSIS), "-V2", f"-DVERSION={version}", f"-DFILES_NSH={nsh}", f"-DHERE={HERE}",
                f"-DICON_FILE={HW / 'build' / 'src' / 'chrome' / 'app' / 'theme' / 'chromium' / 'win' / 'chromium.ico'}",
                f"-DSIZE_KB={sum((OUT / f).stat().st_size for f in files) // 1024}",
                f"-DBUILT_FOR=Helium {helium} / Chromium {chromium}", f"-DOUTPUT_FILE={setup}",
                str(HERE / "helium-workspaces.nsi")], check=True)
with open(setup, "rb") as fh:
    print(f"{setup}\n{len(files)} files, SHA-256 {hashlib.file_digest(fh, 'sha256').hexdigest()}")
