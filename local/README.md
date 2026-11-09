# local/ — build helpers, versioned copies

These are the Windows build scripts and the one local edit to the `helium-windows` clone.
Neither lives in a git repo where it is used, so this directory is their only backup.

- `dev-build.ps1` / `continue-build.ps1` — the two halves of a **first** `build.py --dev` run
  (LOCAL.md §5.3, §5.6). Never run these on a working tree: `clone.py` resets the source and
  wipes the applied patches.
- `resume-build.ps1` — the everyday incremental build (`-Targets`, `-KeepGoing`). Close the
  fork browser first; Windows locks `chrome.dll` while it runs.
- `rebase-args.ps1` / `rebase-overnight.ps1 -Chunk <id>` — after a rebase's `quilt push -a` and
  `continue-build.ps1`: repair both `args.gn`s from `args/*.gn` and `gn gen` them, then the chained
  Default build, unit tests and Dcheck build (LOCAL.md §36). `check-r4.ps1` is R4's owner test.
- `helium-windows-build.py.diff` — the ATL/`vswhere` fix (LOCAL.md §3). `git pull` in the
  `helium-windows` clone silently drops it; re-apply with
  `git -C <local-path>/Helium-workspace/helium-windows apply --ignore-whitespace <local-path>/Helium-workspace/helium/local/helium-windows-build.py.diff`
  (absolute paths: `-C` makes a relative patch path resolve under helium-windows; and
  `--ignore-whitespace` because the checked-out copy has CRLF endings, which plain `apply`
  refuses). To move to a new tag without losing it: `git stash push -- build.py`,
  `git merge --ff-only <tag>`, `git stash pop` (R4).
- `check-smoke.ps1` — the post-rebase smoke test (LOCAL.md §27): guards the forwarded-launch and
  stale-binary traps, prints the seven owner steps, launches `out\Default` against `testprofile`
  with logging, and grades the log (spawn triple, reconcile counts, no hidden-tab activation).
  `-Log` names the run log (`r<N>-run1.log` by the LOCAL.md convention).
- `check-anchors.ps1` — the anchors smoke test (LOCAL.md §29): nine owner steps across two launches,
  the second with `--restore-last-session`, graded from the `[workspaces] anchor` / `hibernated anchored
  tab` lines. `-Log1`/`-Log2` name the run logs.
- `check-e11-rail.ps1`, `check-e11-search.ps1`, `check-e11-rename.ps1` — the E11 smoke tests
  (LOCAL.md 31), one per patch: the rail's Change icon / Unload / Close all items (graded from the
  `unload` / `closing` / `tab contents replaced` lines and the icon written to `Preferences`), tab
  search scoped to the workspace (the `not listing` lines inside and outside the toggle's window),
  and Rename tab across Ctrl+Shift+T and a `--restore-last-session` restart. `-Log` names the run log.
- `read-chrome-url.py` — reads a `chrome://` page out of the built fork via chromedriver, for
  verifying things that only exist in a running browser (LOCAL.md §8). Runs from anywhere;
  paths inside it are absolute. stdlib only.

**They run from `<local-path>\Helium-workspace\`, not from here.** After editing one there, copy it back
into this directory in the same commit, or the two drift apart.
