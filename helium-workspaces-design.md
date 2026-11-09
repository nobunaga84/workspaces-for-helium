# Helium Workspaces — Design & Handoff (v2)

Personal fork of Helium adding Arc-style Workspaces (Spaces). Private use only, never
upstreamed, must survive future Helium/Chromium updates.

**Pinned Chromium: 152.0.7977.82.** Every mechanism below was verified against that exact
tag on 2026-09-07. Do not trust a claim here after a version bump without re-checking it —
§6 lists what was verified and where.

**v2 supersedes v1.** Three of v1's decisions were wrong at 152: the `WorkspaceCollection`
container, the `Workspaces.json` persistence, and the "react from the observer" rules. What
replaced them, and why, is in §2. Raw evidence (verbatim source quotes with file:line) is
archived at `<local-path>\Helium-workspace\research\`.

---

## 1. Goal

Arc-like Workspaces layered on **Helium's vertical tab layout**
(`prefs::kHeliumLayout == kVertical`, which wraps Chromium 152's own
`VerticalTabStripStateController`). Switching workspace changes which tabs the strip draws,
inside one window. Chromium tab groups keep working *inside* a workspace as one level of
folders.

Target = Arc Spaces. Zen Workspaces is the secondary reference: same user-facing idea,
open source, and its data model (a per-tab attribute) is the one that fits Chromium.

### Non-goals

- **Per-workspace cookie jars / profiles.** Arc binds a Space to a Profile; Zen supplies a
  soft default container. Chromium 152 has no per-tab storage-partition primitive, so both
  are out until Helium lands containers (imputnet/helium#199). Do not add a `profile_id`
  field "for later" — it would be dead data.
- **Cross-window tab handoff.** Arc shares one tab instance across windows; Zen mirrors tabs
  between windows with docshell swaps. Chromium is one `WebContents` per window, full stop.
- **Sync.** No account infrastructure. JSON export/import if ever wanted.
- **Nested folders.** Chromium groups cannot nest (§6). One level only.

### Multi-window semantics

The workspace **list** is profile-global (a pref). The **active workspace** is per window.
A tab's membership travels **on the tab**, so dragging a tab into another window carries its
workspace with it. A new window inherits the active workspace of the window that had focus;
a restored window derives it from whichever tab is selected.

### Two repos, not one

Building on Windows needs `helium-windows`, which pins `helium-chromium` as a submodule.
Your fork of `helium-windows` must (a) point that submodule at this repo's `workspaces`
branch and (b) be re-pointed after every rebase. Its own patch series is left untouched.

### This build has no auto-updater — which is the point, and the cost

v1 said "this build will not auto-update." That is correct on Windows, but not for the reason
first assumed, and the difference matters. `helium-windows` does carry WinSparkle updater
patches (`patches/helium/windows/updater/*`, 8 patches applied after the Helium series)
pointing at `https://updates.helium.computer/win/appcast.xml`. But the code sits behind a GN
argument that defaults to off:

```
declare_args() { enable_winsparkle = false }
...
if (enable_winsparkle) { sources += [ "win/winsparkle_glue.cc", ... ] }
```

`flags.windows.gn` never sets it, and `build.py` enables it only when **both**
`WINSPARKLE_ED_KEY` and `WINSPARKLE_AUTHENTICODE_ORG` are present in the environment —
signing material only imputnet holds. A fork build therefore compiles no updater at all.

**So leave the updater patches alone.** Stripping them from the platform series would be a
gratuitous deviation that conflicts on every rebase and buys nothing. Just never set those
two environment variables.

What remains true is the consequence: **nothing will update or nag this build.** Helium also
disables the Chromium outdated-build detector. Security responsibility transfers to you —
rebase and rebuild on the cadence in 3.8, or accept the CVE exposure deliberately rather than
drifting into it. Put a manual watch on imputnet/helium releases.

Two real hazards remain, unrelated to the updater:

- **Never run the fork `mini_installer`.** `change-branding.patch` is applied, so the build
  identifies as Helium and would install over an official installation.
- Run the fork with its own `--user-data-dir` so the official profile stays untouched.

---

## 2. Architecture

### 2.1 The workspace is a tag on the tab, not a container

v1 proposed a new `WorkspaceCollection` between `TabStripCollection` and
`UnpinnedTabCollection`. **Not possible at 152 without patching `components/tabs`:**

- `TabCollection::Type` is a closed enum (`MIN, TABSTRIP, PINNED, UNPINNED, GROUP, SPLIT,
  MAX = SPLIT`) in `components/tabs/public/` — *not* `chrome/browser/ui/tabs/` as v1 assumed.
- `TabStripCollection`'s constructor creates exactly one `PinnedTabCollection` at index 0 and
  one `UnpinnedTabCollection` at index 1 and holds them as `raw_ptr`s compared throughout
  `GetInsertionDetails` and the move code. There is no slot to insert a level into.
- The views layer mirrors the model tree 1:1 (`TabCollectionNode::CreateViewForNode`), so a
  new type also means a new view case and a `LINT.ThenChange` pairing.

**Instead:** a `WorkspaceTabData : content::WebContentsUserData` holds the tab's workspace
guid. The tab model is untouched. The strip decides what to draw by comparing each tab's
guid to the window's active guid.

Plain version: instead of building new boxes to sort tabs into, put a **name tag** on every
tab and show only the tabs wearing today's name tag.

Why the tab and not a table in the service: the tag then survives every path that moves a
tab somewhere the service cannot see — dragging a tab out into a new window, "move tab to
another window", session restore, and reopen-closed-tab. A per-window
`map<TabHandle, guid>` loses membership on all four.

```
TabStripCollection                    (unchanged)
├── PinnedTabCollection               = Arc Favorites / Zen Essentials — global, no guid
└── UnpinnedTabCollection             (unchanged)
    ├── TabGroupTabCollection         one-level folders, scoped to a workspace by tag
    ├── SplitTabCollection            composes for free
    └── TabModel                      each tab carries WorkspaceTabData{guid}
```

### 2.2 The rule that keeps this from crashing

> **Never call a `TabStripModel` mutator from inside a `TabStripModelObserver` method.**

`TabStripModel` is not re-entrant and enforces it with a `CHECK`. `ReentrancyCheck` wraps
`AddTab`, `MoveWebContentsAt`, `ActivateTab`, `MoveGroupTo`, `AddToExistingGroup`,
`SetTabPinned` and `CloseWebContentsAt`, and observers are notified **inside** that scope.
`OnTabWillBeRemoved` fires inside it too.

So every v1 rule — "the observer moves the tab into its range", "the observer activates the
right tab", "the observer inserts an NTP" — was a crash, not a bug.

**Observers may only stamp bookkeeping.** Anything that changes the model is either a posted
task (`PostTask` + `WeakPtr`, re-validating that the tab still exists) or a command handler
reacting to a user action.

Rendering by tag is what makes this cheap: because position no longer carries meaning,
almost nothing *needs* to move.

### 2.3 Contiguity is a nicety, not an invariant

v1's central invariant was "a workspace occupies a contiguous range of public tab indices."
It is *true* that public index == depth-first leaf order of the collection tree (verified),
but the design no longer depends on it. Rendering filters by tag, so a tab briefly sitting
"in the wrong place" is still drawn in the right workspace.

A posted `Reconcile()` (stable-partition the unpinned region into workspace order) runs only
on three occasions: enabling the feature, switching layout back to vertical, and an explicit
"reorder workspaces". That keeps horizontal mode and extension-visible indices sensible
without any hot-path bookkeeping.

Dropping the invariant deletes, at a stroke: the new-tab placement hook, the drag-and-drop
index hook, every fix-up move, and the re-entrancy problem.

**The owner asked for always-contiguous anyway, after E9e.4. It is deferred conditionally rather
than scheduled — chunk C in 4, with two tests that have to pass first.** Two corrections to the
paragraph above were found while building `Reconcile()` and are recorded in LOCAL.md 24: it moves
whole units rather than raw indices, and its occasions are the **exits** from the filtered state,
not the entries named here.

And the question to answer before building contiguity at all: **what does it fix that
`Reconcile()` does not?** The disabled strip, horizontal mode and session save order are all
handled now. What remains is drift in the model order *during* normal use, and the only surface
that currently exposes that is **tab search**, which no patch has ever touched and which lists
every workspace's tabs in creation order. If tab search is the real irritant, making it
workspace-aware is far cheaper than four hooks and carries no permanent rebase tax.

### 2.4 State

`WorkspaceService` — one per window, a `TabStripModelObserver`, stored in
`BrowserWindowInterface::GetUnownedUserDataHost()` and reached via
`WorkspaceService::From(bwi)`.

| State | Where | Why |
|---|---|---|
| workspace list `{guid, title}` | pref `kHeliumWorkspacesList` = `helium.workspaces.list` (dict, `schema_version`) | profile-global, survives restart |
| `active_guid` | memory, per window | two windows can show different workspaces |
| `last_active[guid]` → `TabHandle` | memory, per window | Arc and Zen both return you to the tab you left |
| tab membership | `WorkspaceTabData` on the tab + `extra_data` | travels with the tab (§2.6) |

**The pref is `helium.workspaces.list`, and the `.list` is load-bearing (E7c, 2026-09-11).**
`PrefService` stores user values by *dotted path* — `JsonPrefStore` calls `SetByDottedPath` — so
a pref name is a node in one JSON tree, not an opaque key. Naming the list `helium.workspaces`
would have made it the **parent** of `kHeliumWorkspacesEnabled`: reading it would return
`{"enabled": true}` and never a list, and the first write would delete the toggle. Nothing
diagnoses it — `PrefRegistry::RegisterPreference` rejects only an exact duplicate path, and the
defaults live in a flat `PrefValueMap` where the two never meet, which is also why no
`TestingPrefServiceSimple` test can reproduce it. `NeitherPrefPathIsNestedInsideTheOther` pins
the rule instead. **Any new pref under `helium.workspaces.` must be a sibling of `enabled`.**

**Only `guid` and `title` are stored.** Emoji and accent are deferred to the Stage 5 rail that
draws them; `schema_version` is what makes adding them a non-event. An older build ignores keys
it does not know, so that addition needs no version bump — renaming or repurposing a key does.

**`kHeliumWorkspacesList` must stay local-only.** Helium's private sync ships `PREFERENCES`, but
only for allow-listed prefs, and `core.patch` deliberately *removed* `kVerticalTabsEnabled`
from that allowlist. Never add a workspaces entry: `SESSIONS` sync carries no per-tab
`extra_data`, so synced tabs would arrive tagless while the workspace list appeared — the
worst of both. Nothing per-window ever goes in a pref.

An **implicit default workspace** always exists (fixed guid, cannot be deleted while it is
the only one). A tab with no tag belongs to it. That covers first run, enabling the feature
on a profile with 200 open tabs, and any orphan.

**"Any orphan" is doing more work in that sentence than it looks.** An untagged tab falls into
the default workspace, but a tab tagged for a workspace that no longer exists does *not* — it
matches no active guid, so it is drawn in no workspace at all, and there is no rail entry or
shortcut that could bring it back. The rule owed is that an unrecognised guid reads as the
default workspace, which means the visibility predicate has to know the valid list rather than
just compare two strings. Not reachable before **E9**, since nothing can delete a workspace
until then and tags do not survive a restart until E8 — but it is E9's to solve, not something
to discover then.

**Done at E9b** as `ResolveTabGuid` (LOCAL.md §18), and it needed one thing this paragraph does
not mention: **the active guid has to be resolved too.** A tab resolving correctly while
`active_guid_` still names the deleted workspace means nothing matches and the strip draws
nothing — and the orphan rule working perfectly is exactly what hides the cause. Reopening a
deleted workspace's tab put a real window in that state within an hour of the rule shipping.

### 2.5 What the observer does (stamping only)

| Event | Action |
|---|---|
| tab inserted, no tag | tag = `active_guid`. ~~opener's tag if it has one, else `active_guid`~~ — **the opener half was wrong and was removed at E7b; see LOCAL.md §14** |
| removed with `kInsertedIntoOtherTabStrip` | nothing (it is moving to another window, tag intact) |
| joins a tab group | tag = the group's tag — a group never mixes tags |
| joins a split | same |
| pinned | clear tag (pinned tabs are global Favorites) |
| unpinned | tag = `active_guid` |
| any tag change | `SessionService::AddTabExtraData(...)` |
| removed, active workspace now empty | **post** `EnsureNonEmpty(active_guid)` |
| selection-only change to a tab of another workspace | `active_guid` = that tab's tag + notify. **No model call** — the tab is already active |

**Why the opener rule had to go (E7b, 2026-09-11).** Chromium's opener is not "the tab this
one came from". `TabStripModel::AddWebContents` sets it to whichever tab was *active* at
insertion, and gives one even to a plain Ctrl+T (`PAGE_TRANSITION_TYPED` at the end of the
strip), because its purpose is to decide which tab to re-activate when this one closes. It is a
close-behaviour hint, not a task relationship. So the opener's workspace differs from
`active_guid` in exactly one situation — when the active tab is not in the active workspace —
and that is precisely the state that exists while switching into a workspace with no tabs. The
tab spawned to populate that workspace was therefore stamped for the workspace being *left*,
and the auto-switch row below faithfully followed the tag straight back out, so an empty
workspace could never be filled. Redundant when it was right, harmful when it was not.

That last row is Zen's auto-switch, and it is free: Ctrl+Tab, an extension activating a tab,
an omnibox "switch to this tab", and a link opening in another workspace all become coherent
with one branch instead of intercepting every selection path.

**It must not fire on a close.** When you close a tab, Chromium picks the next active tab
*before* observers run (`DetermineNewSelectedIndex`: the tab this one opened → its opener's
other tabs → its opener → an adjacent tab), and knows nothing about workspaces. Closing the
last tab of a workspace therefore lands on a foreign tab. If auto-switch fired there, Ctrl+W
would throw you into someone else's workspace — the exact anti-Arc behaviour. So auto-switch
is conditional on the change **not** being a removal; a removal that empties the workspace
posts `EnsureNonEmpty` instead.

### 2.6 Persistence — tab extra data, not a JSON file

**v1's plan cannot work.** `SessionTabHelper`'s constructor assigns
`session_id_(SessionID::NewUnique())`, there is no setter, and `session_restore.cc` never
restores saved tab ids (only group ids are remapped). A file keyed by tab session ID can
never match tabs back up after a restart.

Chromium 152 already has what v1 §6 wondered about:

```
SessionService::AddTabExtraData(window_id, tab_id, key, data)   // session_service.h:132
   → session command 33 → SessionTab::extra_data
   → chrome::AddRestoredTab(..., extra_data, ...)               // session restore

LiveTabContext::GetExtraDataForTab(index)                       // captured at close
   → tab_restore::Entry::extra_data → Tabs-file command 14
   → ReplaceRestoredTab(..., extra_data, ...)                   // reopen closed tab
```

Key: `helium.workspace` = guid. In-tree consumers to copy: `glic` (the `WebContentsUserData`
carrier pattern) and `send_tab_to_self` (the `AddTabExtraData` call). Brave's tree-tabs —
the same "container above tabs" shape — ships on exactly this mechanism.

Three hooks, all in `chrome/browser`, none in `components/sessions` (so v1's real constraint
is satisfied):

1. `BrowserLiveTabContext::GetExtraDataForTab` — populate (makes Ctrl+Shift+T restore into
   the right workspace).
2. **`SessionService::BuildCommandsForTab` — re-emit via `AppendRebuildCommand`.**
3. `browser_tabrestore.cc` `CreateRestoredTab` — read it back onto a `WebContentsUserData`,
   consumed when the tab is inserted.

> **The trap.** `BuildCommandsForTab` emits only UA-override, group and split — never extra
> data. `ScheduleResetCommands()` clears all pending commands and rebuilds the file from live
> browsers, and it runs **at every startup** and every 250 commands. Without hook 2, every
> workspace tag disappears on essentially every restart, and the feature looks broken rather
> than buggy. Brave's documentation calls out the same trap.

Note that (3) runs *before* the tab is in the tab strip, so the value must be stashed on the
`WebContentsUserData` and consumed on the insert notification — it cannot be applied directly.

**Built and verified at E8, 2026-09-12 (LOCAL.md §16). Three corrections to the paragraphs above:**

1. **There is no separate "consume" step**, and none is needed. Writing the tag onto the
   `WebContentsUserData` in (3) *is* the stash, and the insert path already leaves it alone —
   rule 1 of `ResolveGuidForInsertedTab` is "a tab that already carries a tag keeps it". The tag is
   simply on the tab by the time anything looks.
2. **A fourth call site was missing from this list**, and it is where most of the writing happens:
   `WorkspaceService` itself calls `SessionService::AddTabExtraData` on every tag change. Hook (2)
   only re-emits at a *rebuild*; without the incremental write there would be nothing to re-emit
   between rebuilds. The three hooks here are the three *upstream* edits, which is a different
   question from the four places that touch the data.
3. **LOCAL.md §11's startup-insert warning does not apply to session restore** — it calls
   `chrome::AddRestoredTab(browser, …)` on an already-constructed `Browser`, so restored tabs are
   observed like any other. The consequence is a free one: the restored active tab pulls the window
   into its workspace through the §2.5 auto-switch, so a window comes back showing the workspace it
   was left in without anything per-window being persisted.

**A `WebContentsUserData` does not survive its tab, and that is not a contradiction of §2.1.**
The tag travels with the tab through drags and restores, but Chromium also swaps the
`WebContents` out from *under* a tab that keeps its identity: `TabStripModel::
DiscardWebContentsAt` does it for Memory Saver and for prerendering, emitting `kReplaced` with
`old_contents` and `new_contents`. Anything holding per-tab state on the contents must copy it
across on that notification or lose it silently — E7b did lose it until 2026-09-11, and the
symptom was a tab quietly rejoining the default workspace minutes after the user last touched
it. E8 inherits this: `extra_data` makes membership survive a *restart*, and does nothing at
all about a discard mid-session.

### 2.7 Rendering

Chromium 152 already ships the mechanism, dormant, for its "focused group" feature
(`features::kTabGroupsFocusing`, off by default and `CHECK`-gated, so copy the pattern rather
than reusing the flag):

`UnpinnedTabContainerViewLayout::CalculateVerticalLayout` computes a `should_show_child` per
child and emits `ChildLayout(visible=false)`; `LayoutManagerBase::ApplyLayout` turns that into
`SetViewVisibility(false)`. `CalculateVerticalMinimumSize` carries the same predicate.
`RootTabCollectionNode::OnTabGroupFocusChanged` is the invalidate pattern.

Every tab always has a `TabView` — "not shown" means the view is invisible, never absent.
That is why hiding tabs breaks nothing: `GetTabAnchorViewAt` resolves index → tab → handle →
view, so Ctrl+N, drag math, context menus and accessibility keep working.

Service API, in model terms only:
`IsVisible(const tabs::TabInterface*)` = `guid == active_guid || !enabled`;
`IsVisible(const tabs::TabCollection*)` = its first descendant tab.

Classify children **by collection node type, not by view class** — `UnpinnedTabContainerView`
has three kinds of direct child: `TabView` (TAB), `TabGroupView` (GROUP) and **`SplitTabView`
(SPLIT)**. The existing focused-group code hides anything it cannot classify, so a forgotten
`SplitTabView` case means every ungrouped split view silently vanishes.

Switching (from a command handler, so mutation is legal): set `active_guid`;
`EnsureNonEmpty(g)`; `ActivateTabAt(last_active[g] or first visible)`; invalidate the
container layout. Newly-visible tabs animate in over one 200 ms expand — acceptable; if not,
`ResetViewsToTargetLayout` snaps instead.

The predicate must be re-read on every layout and never cached in a view: switching
`kHeliumLayout` calls `ResetTabStrip()` / `InitializeTabStrip()`, which destroys and rebuilds
the entire view tree.

### 2.8 Feature gate

`IsEnabled(browser)` = `TYPE_NORMAL` **and** not off-the-record **and** vertical layout
**and** `kHeliumWorkspacesEnabled`.

Incognito and guest windows are `TYPE_NORMAL`, so without the OTR check the rail would appear
there, workspace edits would write into the *regular* profile's prefs, and
`SessionServiceFactory::GetForProfile` returns **nullptr** for OTR profiles — so every session
write needs a null check regardless. Arc gives incognito no Spaces at all; Zen shows a single
"Incognito" pseudo-space. Follow Arc: when disabled, the predicate returns true (everything
visible), the rail is hidden, and the commands are disabled.

---

## 3. Maintenance strategy

### 3.1 Where the code lives, and the GN constraint

All logic in new files under `chrome/browser/ui/tabs/workspaces/`. The target must be
**views-free and Browser-free**, because of the dependency direction at 152:

| Hook site | Its GN target | Depends on `//chrome/browser/ui`? |
|---|---|---|
| `unpinned_tab_container_view_layout.cc` | `//chrome/browser/ui/views/tabs/common:impl` | no |
| `tab_strip_collection_controller.cc` | same | no |
| `session_service.cc` | `//chrome/browser/sessions:impl` | no |
| `browser_live_tab_context.cc`, `browser_tabrestore.cc` | `static_library("ui")` | it is ui |

`ui` already depends on both of the others. So a target all four can depend on may itself
depend on **neither** `//chrome/browser/ui` **nor** `views/tabs/common:impl`. Consequences:

- The service API takes `tabs::TabInterface*` / `tabs::TabCollection*`, never a `views::View*`
  and never a `Browser*` (use `BrowserWindowInterface*`).
- `HeliumLayoutStateController` is the right *shape* to copy but the wrong *place*:
  `core.patch` compiles it into `static_library("ui")`.
- Patch 00 is **three** `BUILD.gn` deps edits, not one.

A GN cycle fails `gn gen` outright, not just `gn check`.

### 3.2 Hook budget — an aspiration, not a gate

v1 set "at most 10 upstream files, 5 lines each" as a rule and treated a rebase getting hard
as proof the budget crept. Reality check: **Helium's own vertical tabs** — a comparable change
by people fluent in the codebase — is `core.patch` (806 lines, 21 files) plus `vertical.patch`
(1701 lines, 27 files), with only 4 new files. The honest MVP number is ~20 upstream files,
about half of them one-liners in files Helium never touches.

| Class | Files |
|---|---|
| **New (fork-owned)** | `workspaces/{BUILD.gn, workspace_service.*, workspace_tab_data.*, workspace_prefs.h, existing_workspace_sub_menu_model.*, workspace_service_unittest.cc}` |
| **Clean** (no Helium hunk) | `unpinned_tab_container_view_layout.cc` (2 lines), `unpinned_tab_container_view.cc`, `tab_strip_collection_controller.*`, `root_tab_collection_node.*`, `session_service.cc` (1), `browser_tabrestore.cc` (1), `sessions/BUILD.gn`, `views/tabs/common/BUILD.gn` |
| **Adjacent** to a Helium hunk | `browser_live_tab_context.cc` (1 patch, lands one line above core.patch @@-166), `vertical_tab_strip_bottom_container.{h,cc}` (5 hunks, `vertical.patch` only), `chrome/browser/ui/BUILD.gn` (9 patches, but each adds its own sources or deps line), `browser_window_features.{h,cc}` (2 patches) |
| **Hot** (Helium owns hunks here) | `tab_strip_model.cc` (7 patches), `browser_commands.cc`, `tab_menu_model.cc` (4), `chrome_command_ids.h` (4 plus a helium-windows patch), `accelerator_table.cc` (4), `browser_command_controller.cc` (6), `browser_shortcut_metadata.cc`, `generated_resources.grd`, `chrome_dll.rc`, mac tables |

The keyboard/command cluster is roughly two-thirds of the total rebase exposure. Stage 4
therefore ships raw accelerators plus labels only; the settings-page, mac and `.rc`
integration waits for Stage 5.

Stay out of: `browser_view.cc` (~50 Helium hunks), `pref_names.h` (~20) and
`browser_ui_prefs.cc` (~20) — declare fork prefs in the fork own header, the way Helium
`browser_shortcut_prefs.h` does. Host the rail in `vertical_tab_strip_bottom_container.*`
(5 hunks, all in `vertical.patch`), **not** `vertical_tab_strip_region_view.*` (22 hunks in
`vertical.patch` alone, plus `zen-mode.patch` and `native-frame-materials.patch`).

`LOCAL.md` tracks per-file "Helium hunks nearby". When a rebase hurts, that table says why.

### 3.3 Rules that survive rebases

1. All logic in new files; every edit to an existing file is a single-line call, never logic.
2. Anchor hunks on stable, distinctive code; small hunks, 3 lines of context.
3. Split by concern so one broken patch does not block the others.
4. Append to `patches/series` — it is a single 357-line file, so appended lines rarely
   conflict. `rerere` (enabled) replays the resolution when they do.
5. Sequence workspaces patches **after** the Helium ones, always.

### 3.4 Patch set

```
patches/local/workspaces/00-prefs.patch             # kHeliumWorkspacesEnabled          (E4b, DONE)
patches/local/workspaces/01-model.patch             # service, tag, stamping leaf       (E5b, DONE)
patches/local/workspaces/02-render.patch            # visibility predicate              (E6a, DONE)
patches/local/workspaces/03-commands.patch          # IDCs via BrowserShortcutService   (E6b, DONE)
patches/local/workspaces/04-gate.patch              # the feature gate                  (E6c, DONE)
patches/local/workspaces/05-command-predicates.patch # close + numbered predicates      (E7a, DONE)
patches/local/workspaces/06-stamping.patch          # observer rules, auto-switch       (E7b, DONE)
patches/local/workspaces/07-workspace-list.patch    # per-profile list                  (E7c, DONE)
patches/local/workspaces/08-persistence.patch       # three session hooks               (E8, DONE)
patches/local/workspaces/09-rail.patch              # the switcher, read-only           (E9a, DONE)
patches/local/workspaces/10-editing.patch           # create/rename/delete + orphan     (E9b, DONE)
patches/local/workspaces/11-dead-workspace.patch    # active_guid_ resolves too         (E9b, DONE)
patches/local/workspaces/12-rail-label-aa.patch     # the rail's DCHECK crash           (E9c, DONE)
patches/local/workspaces/13-move-tabs.patch         # move selected tabs to a workspace (E9c, DONE)
patches/local/workspaces/14-tab-menu.patch          # move tab to workspace, tab menu   (E9d, DONE)
patches/local/workspaces/15-new-workspace-command.patch  # Shift+Alt+S + button menu    (E9e, DONE)
patches/local/workspaces/16-submenu-command-ids.patch    # E9d's submenu ran the wrong  (E9e, DONE)
                                                         # commands; id range registered
patches/local/workspaces/17-reorder.patch           # Move up/down + Shift+Alt+Up/Down   (E9e, DONE)
patches/local/workspaces/21-anchors.patch           # Stage 5, optional; spec in 5     (E10a, DONE)
patches/local/workspaces/22-anchor-drift.patch      # typed url leaves the anchor      (E10b, DONE)
patches/local/workspaces/23-icon-unload-close.patch # rail: icon, unload, close all    (E11, DONE)
patches/local/workspaces/24-tab-search-scope.patch  # tab search lists on-screen tabs  (E11, DONE)
patches/local/workspaces/25-rename-tab.patch        # custom tab title, top-level item (E11)
patches/local/workspaces/26-icon-presets.patch      # Change icon submenu, six presets (E11, DONE)
patches/local/workspaces/27-rail-tab-search.patch   # a tab-search glyph on the rail   (E11)
LOCAL.md
```

**Numbers are assigned as chunks land, not reserved in advance** — the list above was
rewritten on 2026-09-10 to match what actually shipped. Two earlier assumptions did not
survive contact: `01-build-gn` was dropped at E5b (a GN dep now ships in the same patch as
the target it points at), and the E7 row split three ways once its real size was counted.
`patches/local/tests/` was never created — E5a routed around the broken test doubles
instead (LOCAL.md §8).

**Renumbered 2026-09-08.** The list used to run `00-build-gn … 05-prefs` — the pref patch
numbered last but scheduled first (E4), which would have meant an earlier patch editing files a
later patch creates. Fixed while no local patch existed; series order now equals execution
order. The settings-page toggle that §4 once bundled with the pref is **deferred to Stage 5**
with the rest of the settings integration, for the §3.2 reason: its four files
(`settings_strings.grdp` 31 patches, `settings_localized_strings_provider.cc` 35,
`prefs_util.cc` 27, `appearance_behavior_page.html` 6) are among the most Helium-contended in
the tree, and a private fork does not need an opt-in switch to develop against. E4b therefore
ships `workspace_prefs.{h,cc}` + registration only, default `true`, verified at
`chrome://prefs-internals/helium.workspaces.enabled`.

### 3.5 Commands and shortcuts must go through the Helium system

Helium ships `BrowserShortcutService` (`custom-keyboard-shortcuts.patch`, 12 new files,
enabled by default). `BuildCurrentDefaults()` walks `GetAcceleratorList()` and asks
`GetBrowserShortcutCommandLabel(command_id)` for each entry; the switch ends in
`DCHECK(false)` for ids it does not know, and unlabelled ids are **dropped from the
defaults**. So a raw `accelerator_table.cc` entry alone means: a crash in dcheck builds, and
in release builds a shortcut that never appears on the settings page, is not reserved, and
loses to any user rebinding. Register `IDC_HELIUM_WORKSPACE_*` with labels.
`helium/ui/layout/shortcuts.patch` (which adds `IDC_CTRL_S_SHORTCUT`) is the exact template
for the full file list.

**IDC ids:** Helium uses 34080 to 34091; only 34092 to 34099 are free before the upstream
tab-group block at 34100, and we need about 20. Reserve a fresh contiguous block *after* the
tab-group block, in one hunk. E6b took 34110-34125 and left 34126-34139 spare.

**This paragraph's original warning was right, and a correction to it was wrong.** It told you
to avoid lines 77-125 and 464-496 because `ungoogled-chromium/windows/windows-fix-command-ids.patch`
rewrites the file there. On 2026-09-09 that was "corrected" to say no such patch exists
(LOCAL.md commit `d55a0460`); later the same day, syncing E6b, the patch was found sitting in
`helium-windows/patches/ungoogled-chromium/windows/`. It exists, and its hunks are at exactly
those lines.

The mistake is worth more than the fact: **it was checked against `helium/patches/` alone.**
That tree does not contain the Windows-only patches — `ungoogled-chromium/windows/` and
`helium/windows/` exist only in the uncommitted `helium-windows` clone. Anything asking "which
patches touch this file?" must grep **both** trees, or `helium-windows/patches`, which is a
superset. See LOCAL.md 9.

What the patch actually does is harmless to us: it flips `#if BUILDFLAG(...)` to `#if (0)` or
`#if (1)` around ids 34046-34054, 51209 and 52413, and defines no new ids. It does not touch
the tab-group block we anchor on, and series order puts our patches after it. So 34110-34999
really is free — the conclusion survived, on a reason that did not.

**Default bindings. `Ctrl+Alt` is not usable on Windows — do not propose it again.** An
earlier version of this paragraph recommended `Ctrl+Alt+Left/Right` for Windows and mac
(matching Arc-Windows and Zen) plus `Ctrl+Shift+Alt+Left/Right` for Linux. Both are wrong for
the same reason, found while writing E6b:

```cpp
// chrome/browser/ui/accelerator_table.cc, in GetAcceleratorList()
#if DCHECK_IS_ON() && BUILDFLAG(IS_WIN)
    constexpr int kCtrlAlt = ui::EF_CONTROL_DOWN | ui::EF_ALT_DOWN;
    for (auto& mapping : *accelerators) {
      DCHECK((mapping.modifiers & kCtrlAlt) != kCtrlAlt)
          << "Accelerators with Ctrl+Alt are reserved by Windows.";
```

Chromium forbids **every** Ctrl+Alt accelerator on Windows, because Ctrl+Alt is what AltGr
sends on many European layouts — and `{VKEY_LEFT, EF_ALTGR_DOWN, IDC_BACK}` is already in that
same table, so `Ctrl+Alt+Left` would have collided with Back for those users. Note the DCHECK
runs *before* `kTabGroupAcceleratorMap` is appended, so appending a map is a way to slip past
the check rather than satisfy it. Do not do that either; the check is right.

**What E6b actually shipped:** `Shift+Alt+Left/Right`, one entry each in the main
`kAcceleratorMap`, no platform guard. Free in the table on every platform, no Ctrl+Alt, inside
the DCHECK'd set rather than around it, and it matches `kTabGroupAcceleratorMap`
(`Shift+Alt+X/Z/C/P/W`) — the nearest neighbouring feature. It also removes the platform split
entirely: one hunk instead of three.

For the numbered bindings, when they arrive: **Linux is still the constrained one** — upstream
binds `Alt+1..8` to tab selection and `Alt+9` to last-tab under `BUILDFLAG(IS_LINUX)`. Leave
`Ctrl+1..8` alone. Users can rebind anything through the Helium settings page, which is why
the labels in `browser_shortcut_metadata.cc` are mandatory rather than cosmetic.

### 3.6 Commands that must learn about workspaces

`Close other tabs` and `Close tabs below/above` enumerate the whole strip, so without a
predicate they would close every hidden workspace — a data-loss surprise, and neither Arc nor
Zen has a whole-window close. One `IsVisible` predicate each, in the same shape as the
existing `IsTabCollapsed` check, in `GetIndicesClosedByCommand` and `GetTabsClosedByCommand`.

Same for `SelectNumberedTab` and `SelectLastTab` (`browser_commands.cc`) and
`SelectRelativeTab` (`tab_strip_model.cc`) if you want the Arc semantics, where `Ctrl+3` means
"the third tab I can see" rather than the third tab in the window. Both files are Helium-hot;
sequence after.

**DONE at E7a, 2026-09-10 — with two corrections to the paragraphs above.** LOCAL.md §13 has
the detail; both are the kind that cost a build if rediscovered.

1. **"The same shape as the existing `IsTabCollapsed` check" is true of the shape and false
   of the reachability.** `IsTabCollapsed` works because group state lives *inside*
   `TabStripModel`. Workspace state does not, `TabStripModel` holds no
   `BrowserWindowInterface`, and it may not include `workspace_service.h` at all: `:workspaces`
   already depends on `//chrome/browser/ui/tabs:tab_strip`, so that edge closes a **GN
   dependency cycle**, which gn fails on outright. The answer arrives instead through a new
   `TabStripModelDelegate::IsTabVisibleInActiveWorkspace()` — a plain `bool` across an
   interface `:tab_strip` already owns.
2. **`SelectRelativeTab`'s collapsed-group loop is unbounded, and Workspaces breaks the
   invariant that lets it terminate.** Extending its `while` condition hangs the browser
   rather than crashing it. The walk belongs in a bounded, tested free function.

Both close commands exclude pinned tabs already, but the *numbered* ones do not — and pinned
tabs are drawn in every workspace, because they render from a container the §2.7 predicate
never reaches. The delegate implementation therefore short-circuits pinned tabs to visible.
Clearing the tag on pin (§2.5) does **not** substitute for that: an empty guid means the
default workspace, not every workspace.

**Ctrl+Tab is deliberately left global** (Helium ships the Brave MRU cycling): the Arc
Ctrl+Tab also crosses Spaces and switches as needed. Consequence to accept: holding Ctrl+Tab
re-lays out the strip as it crosses workspaces. *Confirmed by the owner 2026-10-13 (C2): MRU keeps
crossing workspaces.* Since `63-ctrl-tab` the cycle list holds tab HANDLES, pruned before each step:
Brave's raw indices CHECK-crashed when a tab closed during a hold (Ctrl held, Tab, W, Tab). The default
(left-to-right) order stops at open pinned pages of the workspace on screen (`IsTabCycleStop`).

### 3.7 Patch loop (quilt)

```bash
source devutils/set_quilt_vars.sh        # defines QUILT_PATCHES and the required quilt alias
cd build/src
quilt push -a
quilt new local/workspaces/01-workspace-model.patch
quilt add chrome/browser/ui/tabs/workspaces/workspace_service.cc
# ...edit...
quilt refresh
```

On a version bump: `quilt push -a` (stops at the first failure), `quilt push -f` (force,
leaves `.rej` files), fix the rejects, `quilt refresh`, `quilt push -a`. Then
`devutils/validate_patches.py` **before** spending hours compiling.

### 3.8 Rebase cadence

Helium tags roughly weekly and each rebase costs a rebuild of hours; following every tag means
about 40 rebuilds over the life of this project. **Rebase on Chromium major bumps (M152 to
M153 and so on) plus any tag carrying a critical CVE; batch the rest.** Since the updater is
off and the outdated-build nag is disabled, put a manual watch on imputnet/helium releases.

**Base the branch on the release tag that helium-windows pins, never on `main`.** As of
2026-09-07 that is 0.16.5 (`f769d143`), also Chromium 152.0.7977.82; upstream `main` runs
ahead of it, and building those commits means building what imputnet never shipped through
their Windows pipeline. Read the pin from the helium-windows submodule entry before each
rebase, and use the `--onto` form (`git rebase --onto <tag> <old base> workspaces`) — plain
`git rebase <tag> workspaces` also replays every upstream commit between the tag and the old
base, rewriting their SHAs and diverging from upstream history permanently.

Procedure: `git fetch upstream --tags`, rebase `workspaces` onto the pinned tag,
`quilt push -a`, fix rejects, `quilt refresh`, `validate_patches.py`, re-point the
helium-windows submodule, rebuild, run the tests in 3.10. Re-check the imputnet/helium PR list for spaces or anchor work before any
Stage 5 rebase.

### 3.9 Build economics

Full build = hours, 100+ GB. **`build.py --dev` sets `is_component_build=true`, which cannot
link on Windows** — abseil is exported through a pre-generated `.def` that assumes a stock
Chromium feature set, and Helium compiles those features out. It fails at ~target 479 with
hundreds of `lld-link: error: <root>: undefined symbol: ... absl::...`, and the `.def` cannot
be regenerated on Windows (`generate_def_files.py` asserts `sys.platform != 'win32'`). Override
it back to `false` in `out/Default/args.gn` after `gn gen` — see LOCAL.md 5.4. Also set
`chrome_pgo_phase=0` and `symbol_level=0` there for iteration speed. Use sccache. Build with
`dcheck_always_on=true` at least once — it is what catches the missing-shortcut-label and
re-entrancy classes of bug.

The cost: no component build means a full `chrome.dll` relink per change, minutes rather than
seconds. Budget for that in Stage 4 onward, or move the dev loop to Linux/WSL2 (where component
builds work) and keep Windows for real builds.

### 3.10 Tests

`build.py` builds no test targets; build them by hand
(`resume-build.ps1 -Targets unit_tests`) and always run with `--gtest_filter`,
never a whole suite. **Record which upstream tests already fail under the Helium patches
before Stage 3** — Helium patches no test files and its CI builds none, so a baseline is the
only way to tell your regressions from pre-existing ones.

> **`unit_tests` does not link in this fork (verified 2026-09-08).** The paragraph above was
> written as an assumption and is false one step further along: it is not that some tests fail,
> it is that the binary does not compile. Five C++ test doubles still call pre-patch signatures
> (`TemplateURLService` ctor, `PageBroadcast`, blink `Page` ctor, `OmniboxClient::AsWeakPtr`,
> `SetSafeBrowsingConfig`) plus 6 WebUI TypeScript bundles, and `//chrome/test:test_support`
> hard-depends on `//chrome/browser/search_engines:test_support`, so no narrower binary escapes.
> Full evidence is in **LOCAL.md §8**.
>
> **E5a settled it on 2026-09-09: route around it.** Helium's doubles are never fixed. A
> fork-owned `test("workspaces_unittests")` depending only on `//base`, `//components/prefs` and
> gtest links and runs (1223 transitive deps against `unit_tests`' 20232; 5 ninja steps; 4 tests
> in 0 s), and `gn desc … deps --all` confirms it reaches none of the broken targets.
>
> **This is now a design constraint, and a welcome one.** Logic that needs testing must be
> expressible over plain inputs, so the workspace decisions — guid resolution on insert /
> group-join / pin / unpin, the visibility predicate, the auto-switch condition — are **free
> functions**, and the `TabStripModelObserver` is a thin adapter that only marshals arguments
> into them. That keeps §2.5's stamping table, the part easiest to get subtly wrong, cheap to
> test. Accepted limit: anything needing a live `TabStripModel` or `Profile` is verified by the
> log line, by hand, and by the E6 DCHECK build instead.

| What | Copy this fixture |
|---|---|
| `WorkspaceServiceTest` | `TabStripModelTest` in `tab_strip_model_unittest.cc` (plain `testing::Test` plus `TestingProfile`; it already enables `kTabGroupsFocusing`) |
| range/index invariants | `tab_collection_unittest.cc` |
| the hide-a-workspace render path | `TabStripCollectionControllerTabGroupFocusingInteractiveUiTest` — but note its mixin enters vertical mode via `SetVerticalTabsEnabled(true)`, whose body `core.patch` rewrites, so check that the fork gate actually opens |
| the persistence trap | `session_service_unittest.cc:913` round-trip, extended with `ScheduleResetCommands()` before `ReadWindows` |

Do **not** use `TestWithBrowserView` — it carries a "Do not use this class" warning at 152.

### 3.11 Coexistence

Separate `--user-data-dir` so official Helium stays installed as a fallback. Keep the profiles
apart: unknown prefs survive fine, session-data assumptions do not. Turn off crash reporting
in the fork — a fork with modified tab-strip code should not upload crashes to imputnet. A
real separate product name additionally requires forking
`helium-windows/patches/helium/windows/change-branding.patch` (app GUID, install dir, registry
keys); budget that explicitly if you ever want an installer.

---

## 4. Execution plan

Each chunk ends at a **committed checkpoint**, sized so one 5-hour usage window finishes it.
If a window expires mid-chunk, nothing is lost.

| # | Chunk | Checkpoint |
|---|---|---|
| **E1** | Materialize the plan: memory, research archive, git setup, this doc, `LOCAL.md`, `CLAUDE.local.md` | commit on `workspaces` |
| **E2** | Stage -1 environment: clone helium-windows; MSYS2 quilt; VS 2026 + SDK Debugging Tools; 100+ GB free | `quilt push -a` succeeds on the unmodified series |
| **E3** | Stage 0: full dev build (hours of wall clock, little agent time) | fork `chrome.exe` runs, vertical layout on |
| **E4a** | Stage 1: profile to vertical; one number through the quilt loop, then deleted; re-point the helium-windows submodule at this repo; version the build scripts | probe seen on screen; submodule = fork; scripts committed |
| **E4b** | Stage 2: patch `00-prefs` — `kHeliumWorkspacesEnabled` + registration (toggle deferred to Stage 5, §3.4) | `chrome://prefs-internals/helium.workspaces.enabled` = `true` |
| **E5a** | Test-support spike, **time-boxed to one window** — can `unit_tests` be made to link? (§3.10, LOCAL.md §8) | a written decision; E5b–E7 checkpoints fixed either way |
| **E5b** | Stage 3: patches `01-build-gn` and `02-model` — the service that only logs, `WorkspaceTabData` | builds; log line on tab insert; tests green in whichever binary E5a chose |
| **E6** | Stage 4a: patch 03 (render) and 04a (next/prev) — two hardcoded workspaces | keyboard switches; hidden `TabView`s asserted |
| **E7a** | Stage 4b: patch 05 — close and numbered predicates. **Split out and done first: it is the only piece closing a live data-loss path** | tests green; "close other tabs" scoped |
| **E7b** | Stage 4b: patch 06 — stamping table, conditional auto-switch, active tab follows the switch | **DONE 2026-09-11.** tests green; group/split/pin rules stamp correctly; the opener rule was removed rather than shipped (§2.5, LOCAL.md §14) |
| **E7c** | Stage 4b: patch 07 — the real per-profile workspace list, replacing the two hardcoded guids | **DONE 2026-09-11.** list visible at `chrome://prefs-internals`; switching cycles it; 66/66 tests. The pref had to be `helium.workspaces.list`, not `helium.workspaces` — §2.4 and LOCAL.md §15 |
| **E8** | Stage 4c: patch 08 — persistence | **DONE 2026-09-12.** Both, log-evidenced: a restored tab arrives `-> workspace 'work' (active 'default')` — a tag the fallback cannot produce — and the window follows it back through E7b's auto-switch. Ctrl+Shift+T checked from a *different* workspace, which is the only form of the test that means anything. §3.4's third hook turned out to be the load-bearing one; LOCAL.md §16 |
| **E9a** | Stage 5: patch 09 — the rail as a read-only switcher | **DONE 2026-09-12.** Both workspaces drawn, active one highlighted, click switches, and it stacks when the strip collapses. Cost **one** upstream file and three hunks, not the five §3.2 budgeted — the rail subscribes to the collapse state itself (LOCAL.md §17) |
| **E9b** | Stage 5: the write path — create, rename, delete, the rail context menu, and §2.4's orphan-tag rule (which delete is what makes reachable) | **DONE 2026-09-12.** 87 tests. Reorder moved to E9c: it is the only one of the four needing a drag rather than a menu item. Deleting a workspace then reopening its tab lands it in the default workspace, log-evidenced — and the same log caught the auto-switch following a *dead* guid, fixed in `11-dead-workspace` (LOCAL.md §18) |
| **E9c** | Stage 5: move-tab-to-workspace, from the **rail's** menu rather than the tab's | **DONE 2026-09-13.** Zero upstream files. Also fixed a `FATAL` the rail had put in every DCHECK build since E9a, which no on-screen check could see (LOCAL.md §19, and the new rule in §5.8.1) |
| **E9d** | Stage 5: the tab-context-menu submenu | **DONE 2026-09-13, but never opened** — compiled and unit-tested, not owner-observed (LOCAL.md §20). Cost 6 upstream files, not the 9 quoted: `:tab_menu_impl` turned out to be able to depend on `:workspaces`, killing the `TabStripModelDelegate` detour |
| **E9e** | Stage 5, in three parts because they touch disjoint files: **(1) DONE 2026-09-13** — `IDC_HELIUM_WORKSPACE_NEW`, `Shift+Alt+S` and the new-tab-button entry, plus the fix for the submenu E9d shipped executing the wrong commands (LOCAL.md §21). **(2) DONE 2026-09-13** — reorder, as `Move up`/`Move down` on the rail menu plus the `Shift+Alt+Up/Down` E9e part 1 reserved for it; refuses at the ends rather than wrapping, and the default workspace moves off the front and stays there (LOCAL.md §22). The drag stays unbuilt. **(3) DONE 2026-09-14** — the settings toggle deferred from E4b, on the *appearance* page rather than 3.4's behaviour page: that block already carries `?hidden="${!this.showVerticalSettings_()}"`, so the toggle hides itself in classic layout for zero extra lines. Five upstream files; `prefs_util.cc`'s allowlist is the one whose absence is silent. Also pays 22's two debts, and adds `EnsureActiveTabVisible()` on re-enable — a hole the toggle itself creates (LOCAL.md 23). **(4) DONE 2026-09-14** — `Reconcile()`, 2.3's own unbuilt answer, with **two corrections to 2.3**: it moves whole units (`MoveGroupTo`/`MoveSplitTo`/`MoveWebContentsAt`) rather than stable-partitioning raw indices, and its occasions are the **exits** from the filtered state, not the entries 2.3 names — enabling reconciles one cycle behind the user's eyes and drifts back before the next look. Six files, zero upstream. Found and fixed three checks that were passing over code that never ran (LOCAL.md 24) | **all four done** |
| **E9f** | Stage 5 repair, not in the original plan: the tab `SwitchToWorkspace` spawns into an empty workspace was never drawn, because the strip laid it out before `StampInsertedTab` tagged it and `SetTag()` did not repaint | **DONE 2026-09-14.** The repaint moved into `SetTag()`, the one door a tag is written through, which also deleted the hand-written `Notify()` in `MoveTabsToWorkspace`. Pre-existing since E9b and invisible because the next click erases the symptom (LOCAL.md 25) |
| **E10** | Stage 5: anchors (patch `21-anchors`) | Spec 2026-09-16 from PR #1578 (5, "E10 spec"). **E10a DONE 2026-09-17**: the anchor field, Ctrl+W hibernate-and-reset with a fallback tab, the four menu items, persistence through E8's door -- nine upstream files, all at sites already ours or clean; release smoke with a restart leg and the DCHECK exercise both PASS (LOCAL.md 29). **E10b DONE 2026-09-17**: the omnibox rule, the pinned fallback and the drifted title -- two upstream files (see the correction below), release smoke 6/6 with two negative controls and the DCHECK exercise both PASS (LOCAL.md 30). **Stage 5 complete.** Same session: anchors now go **dormant** when the feature is off (the tag is kept; re-enabling restores it) -- the one review finding that mattered, closed and gate-tested (LOCAL.md 30) |
| **E11** | Stage 6. Planned as "one item per window"; the owner chose all of them for one window on 2026-09-18, plus a workspace icon "like Arc". Four patches: `23-icon-unload-close` (Change icon, Unload workspace, Unload other workspaces, Close all tabs -- the rail's menu, zero upstream files), `24-tab-search-scope` (tab search lists only on-screen tabs; one condition in the page handler, `IsTabOnScreen` made public), `25-rename-tab` (a custom title on `WorkspaceTabData`, read in `TabUIHelper::GetTitle()` so every consumer follows; persisted through E8's door as `helium.custom_title`; a plain "Rename tab" item, executed in the views-layer tab strip controller), `26-icon-presets` (Change icon as a submenu of six emoji with words, plus Custom...), `27-rail-tab-search` (a 🔍 on the rail running `IDC_TAB_SEARCH`, because Ctrl+Shift+A is Arc's global hotkey on the owner's PC) | **ALL DONE 2026-09-18**, each owner-observed and log-graded, `out/Dcheck` exercised over every path with 0 markers, 27 patches (LOCAL.md 31). Review found one real gap before landing: Close all / Unload decided membership by raw guid while rendering resolves empty and orphaned tags to the default workspace; fixed at the one site both now share |
| **E12** | Import from Arc -- a script, not a patch: `local/import-arc.py` turns each Arc space into a workspace entry plus a bookmark folder under `Other bookmarks / Arc`, and all unpinned tabs into an `Unpin` workspace and folder. Dry run by default, refuses while Helium runs, append-only, idempotent | **DONE 2026-09-18 on `testprofile`** -- 3858 bookmarks, 28 folders, 3 new workspaces; selftest PASS, guard fired, owner-observed. LOCAL.md 32 |
| **E13** | The three HIGH bugs of the 2026-09-18 review plus R3's rail overflow: `28-e13-fixes` (custom title persisted on every tag write; Close all skips pinned tabs; a move takes whole units -- a split as a pair, a grouped tab leaves its group unless the whole group moves, never a hidden tab), `29-rail-scroll` (the owner's design: `< [workspaces] > +`, sliding under the wheel and arrows, `+` = New tab / New workspace / Tab search, Helium's new tab button hidden while the rail shows), `30-rename-background-tab` (Rename tab brings its tab to the front: its dialog is tab-modal), `31-e13-hardening` (focus ring inside, `+` a real menu button, anchors only on http(s) pages; with `local/profile_write.py`, all-or-nothing profile writes) | **DONE 2026-09-19** -- every check log-graded PASS and owner-observed, Dcheck launched with 0 markers; a review workflow (8 agents) confirmed 4 findings and 0 refuted, all fixed or recorded; a second, smaller review of 31 confirmed 1 more (fixed). 32 patches (00-31). LOCAL.md 34 |
| **E13.5** | The open-risk sweep after E13 (a 6-agent workflow; two claims re-checked by hand) and its safety chunk: `32-e13-safety` -- Close all / Delete workspace ask with the count above 25 tabs (Recently Closed keeps 25), and Ctrl+W on an anchor / Unload keep a page with a "Leave site?" listener LIVE instead of discarding it (the first version closed anchored PDFs; the review caught it). Also: the helium-windows clone's push set to DISABLED, and the roadmap re-ordered (R4 before E14; a weekly update check before daily use; official Helium keeps updating; E14 gains auto-archive) | **DONE 2026-09-20** -- every part log-graded PASS and owner-observed, Dcheck launched with 0 markers incl. split and pin/unpin. 33 patches (00-32). LOCAL.md 35 |
| **E14** | In-browser "Import from Arc..." (every tab sleeping; space-pinned -> anchored, folder -> collapsed group, favorites -> pinned, splits), auto-archive into `Archive > <workspace>` bookmarks with an "Archive tabs after" setting, and X / middle-click / "Close tab" on an anchored tab resetting it. Five parts: **research** (the spec in 5), **E14a** `34-anchor-close-reset`, **E14b** `35-arc-parser`, **E14c** `36-arc-import` + the scale gate (all ~3,900 tabs asleep on `testprofile`), **E14d** `37-auto-archive`, **E14e** backups and the owner's real import | **Research DONE 2026-09-21** -- a read-only workflow over the patched .52 tree (7 researchers; the 2 skeptics died on the spend limit, so the 11 claims the spec rests on were re-read by hand). Corrected the roadmap four times (tag through `extra_data` BEFORE the insert, not `SetTag` after; groups through `AddRestoredTab`'s own argument; `RestoreSplit`; 6 real renames, not 3,181), found the restart problem already solved by Helium's lazy restore, found one unwritten precondition (`restore_on_startup`), and a quadratic loop of our own that every grouped insert would pay. **No upstream file outside the ones we already patch.** No code. LOCAL.md 37. **E14a DONE 2026-09-22** -- `34-anchor-close-reset`: two doors (the delegate's `CloseTab` for the X and a middle-click, the top of `case CommandCloseTab` for the menu) and Ctrl+W share one default-false delegate virtual; "Close other tabs" / "below" skip anchors like pinned tabs. Five upstream files, all already ours. 13/13 owner-observed and log-graded incl. a never-loaded anchor after a restart (it CAN be discarded), Dcheck launched with 0 markers. The "Close group" confirm moved to E14c. 35 patches (00-34). LOCAL.md 38. **E14b DONE 2026-09-22** -- `35-arc-parser`: leaf target `:arc_import` (`//base` only), `ParseArcSidebarJson()` -> favorites + per-space units already in strip order, `KeepCreatedAfter()` for re-import; no upstream file, nothing in `chrome` depends on it yet. 120/120; on the owner's real file the C++ counts equal an independent Python count and reconcile with the raw item count (3,865 + 9 skipped = 3,874); a deliberate mutation turned exactly one test red. Owner decided the four parser rows (6 real renames; own tabs before subfolders; skip the 9; re-import by timestamp). 36 patches (00-35). LOCAL.md 39. **E14c DONE 2026-09-23** -- `36-arc-import`: the rail's "Import from Arc..." creates every tab asleep and pre-tagged, in posted slices with a status line, favorites pinned, folders as collapsed saved groups, splits, custom titles; sets "On startup". Gated on the real file: 3,862 tabs in 234 s with the window answering, 1.26 GB, 0 markers; **cold start 360 s and exit up to 92 s FAIL and were accepted by the owner ("no limit")** -- the strip's layout is O(tabs) per added view in four places, profiled with ETW (one was ours and is fixed: 263 -> 133 s). A day of reversed decisions (new window built, rehearsed, withdrawn; plain groups withdrawn; the looser pass line withdrawn). 37 patches (00-36). LOCAL.md 40. **E14c.1 DONE 2026-09-23** -- `37-strip-bulk-layout`: while a restore or an import slice runs, the strip's layout manager marks itself dirty instead of recomputing per tab, and skips each tab's fade-in layer. Cold start with the big workspace active **360 s -> 119 s**, 0 markers on Default and Dcheck, owner rehearsal ALL PASS. A third hunk for the window close was built, proved to fire and removed: the close is not the strip's layout. One clean upstream file. 38 patches (00-37). LOCAL.md 41. **E14c.2 BUILT 2026-09-24** -- the Close-group confirm was not built: every close-group door ends in one Recently Closed *group* entry. **But the owner's run (`check-e14c2.ps1`, 4 FAILs) showed a SAVED group reopens from the saved-group model, not the entry: the tabs come back into the workspace on screen, without anchors or names, and a 1,159-tab group took ~15 minutes** -- options (confirm / re-apply the entry's data / Arc's folders) are the owner's, LOCAL.md 42. Its first run found worse: a Ctrl+Shift+T that reopened a stale 3,864-tab window, moved all 22 saved groups into it and CHECK-crashed on a split inside one. Arc keeps no tabs in its windows and an item lives in one place (read from its own files), so it cannot happen there. `38-reopen-leaves-groups`: a reopened window leaves a saved group that is open elsewhere where it is (the move lived in our own `browser_live_tab_context.cc`), and `ReconstructSplit` skips a split already in place. A first version -- a Ctrl+Shift+T rule in a 51st upstream file -- was built, reviewed and deleted: the deeper fix left it nothing to guard. No new upstream file. Tested with no one at the keyboard (an extension reopening the window by id), Workspaces on and off. LOCAL.md 42. **Next:** the owner's decisions -- the Close-group option, and whether **Arc's folder model** (the owner, 2026-09-24: a folder of sleeping tabs is never loaded until opened) becomes its own stage ahead of E14d -- it did: E15, done 2026-09-27. **E14d REDESIGNED 2026-09-27 (the owner): Arc's own archive, not bookmarks.** A per-profile archive file of our own (like the pins file) keeping EVERY close -- by hand and automatic -- per workspace, with its reason and date, and an Archive screen to browse, search and restore; Ctrl+Shift+T stays Chromium's. Read from Arc's `StorableArchiveItems.json` (counts only): one list of 1,757 archived tabs (1,300 `manual`, 457 `auto`), each with its space, address, title, `archivedAt` and `reason`, spanning ~2 months; the owner's Arc threshold is **30 days** (every `auto` item was exactly 720 h past its last use). Split: **E14d research** (the spec redone: which closes count -- not a window close or quit, not a pinned page's X, not a drag to another window; retention; restore; the default; no build) -> **E14d.1** the store + tests -> **E14d.2** recording + auto-archive + the setting -> **E14d.3** the Archive screen; bringing Arc's own archive over is optional, in E14e. **E14d research DONE 2026-09-27** -- by hand, no agents, no build: Arc's archive file read (tabs only, never a pinned item; 1,300 manual / 457 auto; **kept 60 days**; duplicates kept), and every user close found to pass ONE door, the delegate's `CreateHistoricalTab`, in a file already ours -- **zero new upstream files** for the record. The owner decided four rows: a window closed while another stays open IS archived (`window`; the last window and Exit are not, the session keeps them); **60 days**; a restore goes back to its own workspace, top of Today, and leaves the archive; **Arc-style rows by day, searchable**. Defaulted: Ctrl+Shift+T of an archived close removes its entry (08's extra data, no hook). **Re-split, each sized to one session's ~1M-token context, auto-archive LAST** (a tab closed by a timer is safe only once it can be found): **E14d.1** `47-archive` the store + the record -> **E14d.2** `48-archive-screen` the screen + restore -> **E14d.3** `49-auto-archive` the sweep + the setting. Spec in 5, "E14d spec"; LOCAL.md 51. **E14d.1 DONE 2026-09-27** -- `47-archive`, in workflow mode (the owner; ultracode on mid-chunk: 3 writers on disjoint files against a hand-written header, a 17-agent review, 3 fixers, a 3-agent fix check -- 3.94 M subagent tokens): the `:archive` store (60 days, held closes never lost), the record at the delegate's door (manual; `window` only for a committed window close beside another session window; never a pinned item's page, a quit, the last window or the app menu's Exit), `helium.archive_id` through Recently Closed only, removed at `BrowserLiveTabContext`'s reopen doors. The review found the spec wrong six times -- one HIGH: the app menu's Exit never sets `IsTryingToQuit` -- all fixed before landing (5 below). No new upstream file (54). 162 tests (161 + 1 skip); hands-free 55/55 on release and Dcheck, 0 markers. After landing, rehearsing the owner's check found Chromium's .52 menu-Close slip (no Recently Closed, no archive): Chromium main's fix backported into 47. **Owner's check ALL PASS.** 48 patches (00-47). LOCAL.md 52. **E14d.2 DONE 2026-09-28** -- `48-archive-screen`, built overnight in workflow mode (6.52 M subagent tokens): the Archive screen, a bubble on the rail's `+` (a view in a `DialogModel` custom field: `BubbleDialogDelegateView` is friend-list-only at M153), rows by day with the page's icon, a search box, an "All workspaces" switch off at every open, a click restores into the entry's workspace at the top of Today and takes its Recently Closed tab away too (saved, through `DeleteNavigationEntries`), Delete, Clear all over every workspace; a favorite (a pinned tab) is never archived. No new upstream file (54). 170 tests; hands-free 72/72 on release and Dcheck, 0 markers; a mutant build proved two rows can fail; the gate: 1,750 entries open in 510 ms, a keystroke 22 ms. Owner's check ALL PASS. 49 patches (00-48). LOCAL.md 53. **E14d.3 DONE 2026-09-29** -- `49-auto-archive`, in workflow mode (5.52 M subagent tokens): a timer per window files the tabs left alone longer than the setting (Never by default; 1 / 7 / 30 days under the Workspaces switch in Settings > Appearance) into the archive as `auto` and only then closes them, quietly (no Recently Closed), at most 25 per sweep. Never swept: the active tab, a favorite, a pinned page, an anchored tab, a split or grouped tab, an address a restore cannot open, and a live page audible within a minute, captured, on a device, in DevTools or picture-in-picture, asking "Leave site?" or typed into. The clock is the later of last shown and left, floored at the last Arc import; the importer no longer stamps Arc's time. The Archive's Clear all became "Clear..." with Last hour / 24 hours / 7 days / All time (the owner moved the ranges there from the settings page). No new upstream file (54). 183 tests; hands-free 86/86 on Dcheck, 0 markers; review 24 agents, 10 fixes; owner ALL PASS 30/30 (pwsh 7.6.6, Dcheck). After landing, the release build (a full rebuild: a hand-run `gn gen` had swapped python, LOCAL.md 54) passed too: Build Succeeded, 183/183, hands-free ALL PASS 86/86 under pwsh 7.6.6. **E14d complete.** 50 patches (00-49). LOCAL.md 54. **E14e BUILT AND REHEARSED 2026-09-30** -- no patch: `local/backup-browsers.ps1`, `import-arc-archive.py` (Arc's own archive, 1,745 entries, by a one-off script -- the owner), `count-arc-sidebar.py`, `switch-day.ps1` and `check-e14e.ps1`, in workflow mode (48 agents, 5.68 M). The owner: the real import waits for switch day (Phase 3), rehearsed on a throwaway copy of official Helium's profile. The real backup made and verified (`backups/2026-09-30_010832`); rehearsal 5 ALL PASS 16/16 (443 + 3,415 + 9 = 3,867, all of Arc's tabs; 1,745 archive entries; 609 restored). The rehearsals found the owner's zen mode (the rail invisible to MSAA: pinned for the import), a case-insensitive variable, and that `restore_on_startup` is a tracked pref no script can write. LOCAL.md 55 holds the switch-day sheet. **E14 complete but for switch day; next: Phase 2 (the installer)** |
| **E15** | **Arc folders**, inserted by the owner 2026-09-24 ahead of E14d: a per-workspace *pinned section* of folders and items that are data in the fork's own file, not tabs -- nothing loads until an item is opened, an opened item is one real tab hidden from the list and drawn as its row, closing it closes the page and keeps the item, full Arc drag (pin, unpin, reorder, nested folders), New folder / Rename, the importer writing folders instead of groups. Spec in 5, "E15 spec", decided with the owner in one brainstorm. Parts: **E15 research** (seven read-only questions) -> **E15a** the store -> **E15b** the section + importer + scale gate -> **E15c** open / close -> **E15d** drag | **Spec 2026-09-24.** Done means cold start and close <= 10 s on the re-imported `testprofile` (now 119 s and ~3 min), a 1,159-item folder shown in about a second with nothing loaded, nothing lost, 0 markers. **Research DONE 2026-09-24** -- by hand, no agents, no build: all seven answered into the spec. The store is `Profile` user data in `//base` (no factory hook); the section mounts through one hunk in `tab_strip_view.cc`, from our own controller; an item opens through the importer's `AddRestoredTab` road; the unpin needs no hook; `//chrome/browser/favicon:impl` would close a GN cycle. **One** new upstream file for E15a-c (`tab_strip_view.cc`), plus E15d's `base_tab_strip_region_view.cc`. LOCAL.md 43. **E15a DONE 2026-09-24** -- `39-pins-store`: the `:pins` target (`//base` + `:stamping`), the tree, its JSON, and `PinStore` (profile user data, written 2.5 s after a change and in its destructor; a bad file kept as `.bad`, never over an earlier one; a newer or locked file read-only). No upstream file, nothing in `chrome` uses it yet. 136/136 on Default and Dcheck; deleting the destructor's flush turns exactly its 3 tests red; review: all 6 applied (`SetRoots` refuses what the next load would refuse, duplicate ids included). 40 patches (00-39). LOCAL.md 44. **E15b DONE 2026-09-25** -- `40-pinned-section`: the importer writes Arc's pinned containers into the pins file as nested rows (3,415 rows in 28 folders on the real file; favorites and Today stay tabs), and a section above today's tabs draws the active workspace's rows, nothing loaded; one new upstream file (`tab_strip_view.cc`, hook list 51). **Scale gate: cold start 2.2 s (was 119 s), exits 1.0-1.5 s, 3,443 rows reloaded, 0 markers**; its one FAIL (a 1,313-row folder drawn in 6.1 s) fixed at the cause -- rows built off the widget, 0.5 s, owner re-check "very smooth". The owner: "overall experience very fast now". Review: 7 of 7 applied; the keyboard and inactive-colour fixes await the owner's eyes (first step next session). A close with the biggest folder open still takes ~6 s (under the line, cause partly found). 41 patches (00-40). LOCAL.md 45. The owner's keyboard check (2026-09-26) found F6 pane focus taking Left/Right from a folder row -- fixed in 40 (`5e68ff5b`). **E15c DONE 2026-09-26** -- `41-pinned-open-close`, built overnight, landed after three owner runs: a pinned item opens as ONE real tab, linked (`helium.pin_item`) and anchored before the insert, drawn only as its row (sleeping / open with an X / active, a back arrow while drifted); the X and Ctrl+W close it for real (no Recently Closed); a restart relinks it; Unpin / Delete / Delete folder; a multi-tab close takes only drawn tabs. No delegate virtual was needed (the importer already calls `AddRestoredTab` from the same target); the scroll guard is two hunks in `tab_strip_view.cc` (hook list unchanged, 51). 140/140; a hands-free MSAA test (`local/check-e15c-auto.ps1`) on Default and Dcheck, 0 markers; review 9 findings, all 8 the owner chose applied. The owner's run found a redirecting address (an Amazon affiliate link) showing the back arrow at once: where an item's address lands is now its home. "Pin to workspace" moved to E15d. 42 patches (00-41). LOCAL.md 46. **E15c.1 DONE 2026-09-26** -- `42-new-tab-top`: Arc's rule, read from the owner's own sidebar file (459 Today tabs): a new tab at the TOP of Today (60 of 63), a link from a Today tab just below it (48 of 51, Chromium's rule, unchanged), a link from a pinned page at the top after that page's earlier links (308 of 318 -- the missed case, and the owner's most common). "+ New Tab" (Helium's own button) under the line, shown with no rows too, with Helium's menu; Chromium's quick look-up (Ctrl+T then Ctrl+W goes back, also after typing) kept for a tab at the top. Two new delegate doors; one new upstream file, `tab_list_bridge.cc` (the owner's choice, review #2): 52. A new tab keeps the window busy 59-152 ms on testprofile, following the tabs DRAWN, not the session rewrite. Review 8/8 applied. 140/140; hands-free (MSAA, ordered by screen position) and Dcheck ALL PASS, 0 markers; the owner's check ALL PASS over two runs. 43 patches (00-42). LOCAL.md 47. **E15d split three ways by the owner (2026-09-26): E15d.1 + E15d.2 DONE 2026-09-27** -- `43-pinned-edit`: the store's Insert / Move / Rename (every change of shape through one `Commit`), row menu Rename / New folder, tab menu "Pin to workspace" (the END of the section, Arc's order read from the owner's file: 153 vs 77), an unpinned page at the top of Today; the tab list stays STILL on pin and unpin (the owner's check found it jumping: pages are moved while still linked, and rows laid out before one is focused or named). `44-pinned-drag`: the section's own drag -- reorder, into a folder (first, Arc: 1,694 vs 30), out of one, into the tab list at the drop place (`GetLinkDropIndex`), a page open in another window brought here. No new upstream file (52). Review: a 6-agent workflow (the owner's opt-in, 1.13 M tokens), 11 confirmed, all fixed but one handed to E14e. 143/143; owner ALL PASS on both, the drag on the Dcheck build, 0 markers. 45 patches (00-44). LOCAL.md 48. **E15d.3 DONE 2026-09-27** -- `45-pin-by-drag`: a Today tab dragged onto the rows is pinned where it is dropped (before / after a row, first INTO a folder, which opens; the end; a selection in its order); only drags whose tabs can ALL be pinned are the section's, the rest stay the list's; "+ New Tab" is the list's. The section is a `TabDragTarget` via one hunk in `base_tab_strip_region_view.cc` (53). **Found: since E15b every Today-tab drag and every drag in a group CHECK-crashed** (40's box broke `GetScrollViewForContents`): fixed in 40, `tab_group_view.cc` (54). A guarded real-mouse (SendInput) hands-free test, ALL PASS release + Dcheck, 0 markers, a two-window drag included; 143/143; review 7/7 applied (the owner); owner ALL PASS over two runs. **46 patches (00-45). E15 complete.** LOCAL.md 49. **E15e DONE 2026-09-27** -- `46-new-window-workspace`: a new window opens on the workspace of this profile's window activated last (design 1's own rule, never built until E15d.3's two-window step found it); Home when there is none; a restored window still follows its selected tab. Hands-free (Ctrl+N, `--new-window`, a reopened window) ALL PASS release + Dcheck, 0 markers; owner ALL PASS. **47 patches (00-46).** LOCAL.md 50. **Next: E14d.2** (E14 row) |
| **E16** | **The zen-mode floating sidebar resizable** -- asked by the owner 2026-09-30 (future, not scheduled; after Phase 2). With zen mode on and the sidebar not pinned, Helium's `zen-mode.patch` hides the strip's resize edge (`VerticalTabStripRegionView::UpdateResizeAreaVisibility()`: `if (zen_mode_floating_style_) { resize_area_->SetVisible(false); return; }`), so the width is fixed; the owner wants to drag it like the pinned strip. This reverses E13's "the fork follows Helium's strip" for this one case. Cost: `vertical_tab_strip_region_view.cc` would be the **55th upstream file** and one Helium itself patches three times (`layout/vertical.patch`, `layout/zen-mode.patch`, `native-frame-materials.patch`): expect conflicts at rebases. To settle first: the floating strip hides when the mouse leaves it -- a drag must keep it revealed; where the edge sits inside `kZenModeVTSPadding`; the width is one saved value (`vertical_tabs.uncollapsed_width`) shared with the pinned strip; ask whether Helium upstream would take it instead (no: AI ban, LOCAL.md 34 -- the fork carries it). Test: a guarded real-mouse drag of the edge (as `check-e15d3-auto.ps1`) asserting the saved width after the drag | **DONE 2026-09-30** (LOCAL.md 58): patch `50-floating-resize` -- the edge kept, placed by `width()` (Helium's `bounds().right()` put it outside the floating strip), a floating strip never collapses; a drag keeps it revealed with no code; `check-e16-auto.ps1` red on 49, ALL PASS 9/9 |
| **E17** | **The fork's UI redesigned: native to Helium, with Arc's feel** -- asked by the owner 2026-10-02, after R5 and before the installer. Direction B from a Claude Design review: a colour and line icon per workspace, a workspace header, pinned pages on a card with solid coloured folders, Arc's bottom bar (Archive left, workspaces, +), a restyled Archive, menus with icons and one "Edit workspace…" bubble, the collapsed sidebar keeping its pinned pages. Spec: section 5, "E17 spec" | E17a `51-ui-bar`, E17b `52-ui-pinned`, E17c `53-ui-archive` | **LANDED 2026-10-03** (the owner's "land E17"; LOCAL.md 60-61; patches 51-53; final suite 16/16, 0 DCHECK markers; weeks start on Sunday) |
| **E18** | **The owner's first wishes after switch day** (2026-10-04): counts in the section headers (wish 1), roomy tabs as a Settings choice (wish 4), a gliding tab list as a Settings toggle (wish 2), a sidebar as wide as the window allows + its width kept across a restart (wish 5). Spec: section 5, "E18 spec" (16 decisions defaulted while the owner was away, for review) | E18a `54-pinned-counts` + `55-tab-style`, E18b `56-smooth-scroll`, E18c `57-wide-sidebar` | **LANDED 2026-10-04** (the owner's "all pass, land E18"; LOCAL.md 64): built while the owner was away, Default + Dcheck suites ALL PASS, owner check 14/14, glide "right"; Tab style Default / 36 / 40 / 42. One new upstream file: `tab_view_vertical_layout.cc` (57) |
| **E18.1** | **A saved tab group reopened from Recently Closed keeps its workspace** -- the owner's report after the E18 install (2026-10-04): three Home groups had come back in Canary when their 600-tab window was closed and reopened. Chromium rebuilds a saved group from its saved-group model, which keeps no workspace: E14c.2's step-3 FAIL (LOCAL.md 42), still open for real Chromium groups after E15 | `58-reopen-keeps-workspace` | **LANDED 2026-10-04** (the owner's "land E18.1", pushed `6d7b51c3`; LOCAL.md 66; installer ws59, LOCAL.md 67): `check-e181.ps1` RED 7 FAIL -> GREEN 14/14 (Default) and 10/10 (Dcheck, 0 markers); suite 8/8 + e18 ALL PASS; no new upstream file |
| **E18.2** | **A reopened group keeps its anchors and names, and pulls the window to it** -- the owner's "fix the still open 2 issues" (LOCAL.md 66): the closed tab's saved-tab id goes into Recently Closed; each rebuilt tab takes its closed tab's anchor and name by that id; a Close group -> Ctrl+Shift+T reopen focuses the group (a 1-tab group too); a reopened tab draws its rename before it is clicked | `59-reopen-keeps-tab-data` | **LANDED 2026-10-05** (the owner's "land E18.2", pushed `18124079`; LOCAL.md 68; installer ws61, LOCAL.md 69): check-e181 -Group 22/22, suite 8/8 + e18 54/55/57 (56: Windows animations off), 0 markers; no new upstream file |
| **E18.3** | **A group reopened into the workspace on screen keeps its order** -- found by E18.2's design review, confirmed (g6,g5,g4 -> g4,g5,g6): 42 put each rebuilt tab at the top; during a rebuild each goes after the last | `60-reopen-keeps-order` | **LANDED 2026-10-05** (the owner's "land E18.2", pushed `18124079`; LOCAL.md 68; installer ws61, LOCAL.md 69): order row RED on 59 alone, GREEN on 59+60 (Default and Dcheck, 0 markers) |
| **C13 + C22 a-c** | **Shortcuts** (`ideas.md`): Shift+Alt+1..9 the Nth workspace, Shift+Alt+0 back to the last one, Shift+Alt+D pin / unpin the page in front, Shift+Alt+K Clear Today (open pinned pages stay), Shift+Alt+H the Archive centred over the page | `61-shortcuts` | **LANDED 2026-10-07** (the owner's "all pass, land C13", pushed `3a00b971`; LOCAL.md 71; installer ws62, LOCAL.md 72): check-c13 21/21 on Default, Default -Zen and Dcheck, 0 markers; rebase-checks 8/8; decisions D1-D10 defaulted, the owner's to flip |
| **C12 + C30 + C24 + C26** | **The pinned section**: the page in front under its closed folder (a peek row), Delete keeps each page in the Archive, an empty section takes a dragged page, the x painted on mouse-over | `62-pinned-polish` | **LANDED 2026-10-08** (the owner's "all pass, land C12", pushed `d6e7b651`; LOCAL.md 73; installer ws63, LOCAL.md 74): design review 16 findings folded in; owner's try ALL PASS, 0 markers; the hands-free suite queued |
| **C2 + C1** | **Ctrl+Tab and quick search** (`ideas.md`): Ctrl+Tab's most-recently-used cycle holds tab handles (Brave's raw indices CHECK-crashed on a close mid-hold) and orders by when each tab was left; the default order stops at open pinned pages; Shift+Alt+F a bare box over the page -- empty: this workspace's recent tabs; typed: open tabs, pinned pages (folder names too) and archived tabs of every workspace, grouped, the workspace on screen first, Enter opens in its own workspace | `63-ctrl-tab`, `64-quick-search` | **LANDED 2026-10-13** (the owner's "all pass, land C2", pushed `3eb6e4a5`; LOCAL.md 75): workflow mode 5.12M; unit 215/215; check-c2 29/29 + Dcheck 27/27; rebase-checks 8/8; 0 markers; the owner's try ALL PASS; no new upstream file |
| **E19** | **Pinned splits (Arc parity)** -- the owner's 2026-10-13 report: an Arc pinned split view is ONE row of the pinned section with two pages side by side (each its icon, title, x; the closed page of a half-open split drawn dimmer); a half opens both pages as one split view; Close per page or both, Unpin keeps the split view, Delete puts both pages in the Archive, Rename the page under the pointer; a Today split pinned whole by drag or Shift+Alt+D; the store's file version 2 (v1 still read); a one-time repair re-pairs the splits earlier imports left as two items, read from Arc's own file | `65-pinned-splits` | **LANDED 2026-10-13** (the owner's "land E19 with the dim half", pushed `4497c6ac`; LOCAL.md 77): unit 221/221; check-e19-auto Default 7/7 + Dcheck 7/7 (re-paired 3 of 3 on the owner's real Arc file); 0 markers; the owner's try (3 and 9 by design, the dim half added; 7's failure = the Today split's drawing, its own chunk); review workflow 1.59M, 9 confirmed, all fixed; no new upstream file |
| **E19.1** | **A Today split view's second half drawn** -- the owner's E19 try (step 7): "Add tab to new split view" in Work drew the left page at half width and the right half EMPTY; the same leak made Unpin of an open pinned split an empty Today row. A new tab joined to a split before it is stamped was hidden as a row by 02's rule, and a split / group keeps a child's visibility | `66-split-half-shown` | **LANDED 2026-10-14** (the owner's "land and rebuild the installer", pushed `149a5297`; LOCAL.md 79): the Today list's detach hook shows a row leaving for a split or group (Chromium's `TabGroupView::DetachChildView` pattern); repro-e191 Default + Dcheck 13/13, check-e19-auto 7/7, 0 markers; the owner's try ALL PASS 7/7 in Work; no new upstream file |
| **wish 6a** | **The toolbar's buttons either side of the address bar** (the owner's wish 6, 2026-10-13/14: the divider is the address bar; any icon of the three Toolbar-list blocks on either side, mixed; drag in the toolbar AND in Settings' list). 6a: one saved order + Settings' Toolbar list as one draggable list with an "Address and search bar" row + the toolbar's own buttons and the extensions placed by it; Chrome's pinned buttons one group | `67-toolbar-order` | **LANDED 2026-10-15** (pushed `a37cbe75`, installer ws71; LOCAL.md 85) -- was: **BUILT + CHECKED 2026-10-14 overnight, committed locally `8f7b4484`, NOT pushed** (LOCAL.md 81): check-w6a ALL PASS 14/14 on Default, zen and Dcheck; 235/235. Waits for the owner's try (`local/try-w6a.ps1`) and word. Next: 6b (each Chrome button on its own, `SetButtonHost`), 6c (drag in the toolbar itself) |
| **wish 6b** | **Every Chrome toolbar button on its own** (the owner's 6a try: "this will be drag as a group, not individually"): the pinned box lends its buttons to the toolbar, which places each by the saved order; the list's grouping gone | `68-toolbar-order-each` | **LANDED 2026-10-15** (pushed `a37cbe75`, installer ws71; LOCAL.md 85) -- was: **BUILT + CHECKED 2026-10-14, committed locally `41964e12`, NOT pushed** (LOCAL.md 82): check-w6a 16/16 on Default, zen and Dcheck; 235/235. Waits for the owner's try and word. Next: 6c (drag in the toolbar itself) |
| **wish 6c** | **Drag any toolbar button in the toolbar itself** (the owner's 6b try: "all pass, proceed with 6c"): press and drag sideways any button -- greyed-out Back/Forward, the extensions block by its puzzle, each pinned Chrome button, the menu -- across the address bar; the button moves with the pointer; a drop saves the same order Settings' Toolbar list edits; menus open on release | `69-toolbar-drag` | **LANDED 2026-10-15** (pushed `a37cbe75`, installer ws71; LOCAL.md 85) -- was: **BUILT + CHECKED 2026-10-15 overnight, committed locally `2e4fc22e`, NOT pushed** (LOCAL.md 83): real-mouse check-w6c 15/15 on Default and Dcheck, check-w6a 16/16 on Default, zen and Dcheck; 239/239. Waits for the owner's try (`local/try-w6a.ps1` steps 6b-6f) and the word "land wish 6" |
| **wish 6c.1** | **The toolbar New tab button in every layout** (the owner's 6c try: "the new tab button is not appearing in the toolbar" -> "Show when switched on"; the other finding, temporary buttons with Extensions, kept by the owner's choice "Keep beside Extensions") | `70-toolbar-newtab` | **LANDED 2026-10-15** (pushed `a37cbe75`, installer ws71; LOCAL.md 85) -- was: **BUILT + CHECKED 2026-10-15, committed locally `75167e4f`, NOT pushed** (LOCAL.md 84): check-w6a 17/17 on Default, zen and Dcheck; real-mouse check-w6c 15/15 on Default and Dcheck; 239/239. Waits for the owner's try and "land wish 6" |
| **C3 + C17 + C15 + C8** | **The pinned section, more** (`ideas.md`): Move to workspace on every pinned row (its open pages follow); a folder's Open all / Close all / Sort by name (+ Undo sort) / Copy links; the workspace header folds the card (the page in front stays); a closed folder opens under a drag held 500 ms and closes again unless the drop went into it | `71-pinned-actions` | **LANDED 2026-10-17** (the owner's "all pass" + "Land C3"; pushed `e08b0f4a`; LOCAL.md 86; installer ws72, LOCAL.md 87): two-lens design review folded in; workflow mode (3 writers + check, 4-lens review with skeptics: 9 findings fixed); 248/248, check-c3 13/13 Default + Dcheck, regression 11/11; Sort by name = Chromium's bookmark rule (folders first, ICU collator). chrome.dll in ws72 = the tested build |
| **C14 + C34** | **A sound badge on the bar, and a close returns to the tab used last** (`ideas.md`; C34 the owner's 2026-10-17): a workspace's chip shows Chromium's alert icon (sound, or camera / mic / screen capture) while a tab of it, in this window and off screen, has it -- a click shows that tab; closing the tab on screen lands on the tab of this workspace LEFT last (C2's clock), before Chromium's opener rules, the anchor reset too | `72-sound-badge`, `73-close-to-last-tab` | **LANDED 2026-10-18** (the owner's "all pass" + "Land C14"; pushed `7dce569e`; LOCAL.md 88; installer **0.18.154.74** -- the owner's new label 0.<Helium minor>.<Chromium major>.<patch count>, LOCAL.md 89; chrome.dll = the tested build): two-lens design review (17 findings, 1 HIGH) folded in; workflow mode (3 writers + check, 4-lens review with skeptics: 5 confirmed, fixed); deslop + /code-review high (5 LOW, all applied on the owner's word); check-c14 12/12 Default + Dcheck, 0 markers; the regression suite all pass (e14d3 86/86 after the owner's reboot finished a pending Windows update that hid web content from MSAA -- the ws72 build failed it too). No new upstream file |
| **C35 + C31 + C32** | **The pinned card told apart in dark mode, a pinned page's address replaced, duplicate tabs closed** (`ideas.md`; C35 the owner's 2026-10-18): the dark card a step stronger (alpha 0x14), a 1 px edge round it and a line under it in the strip's own line colour (light mode: the edge and the line); "Replace pinned URL with current" (Arc's words) on a pinned page that wandered -- the page in front becomes its address; the workspace menu's "Close duplicate tabs...": the Today tabs whose address is a pinned page's, an open pinned page's, a favorite's or another Today tab's close into the Archive after a confirm, the copy used last stays, a marked tab (split, group, anchored, renamed) never closes | `74-pinned-card-edge`, `75-replace-pinned-url`, `76-duplicate-tabs`, `77-pinned-active-ring` | **LANDED 2026-10-19** (the owner's "Land C35" + "one installer with both"; pushed `5468e7a7`; LOCAL.md 92; installer **0.18.154.80**, chrome.dll = the tested build) -- was: BUILT + CHECKED (LOCAL.md 90; C35.1, the owner's try comment: the pinned page in front ringed in its workspace's colour, check-c35 13/13 both builds, regression 13/13): two-lens design review (29 findings, 1 HIGH: grouped tabs) folded in; workflow mode (3 writers + check, 4-lens review with skeptics: 8 taken); deslop + /code-review high; 256/256, check-c35 11/11 Default + Dcheck, 0 markers; the regression suite 13/13; the owner's try ALL PASS (before 77). No new upstream file. Next: the owner's look at the ring, then "land C35" |
| **Pinned icons** | **A pinned page's icon** (the owner's report, 2026-10-19: an open pinned page kept the globe it was drawn with; never-visited pages of one site showed its 2010s logo): an open pinned page at its address lends its row its own icon, kept while it sleeps; the host fallback's tie goes to the page mapped last, so a site's current icon beats an imported legacy one (pinned rows, split pages, the Archive, quick search) | `78-pinned-live-icon`, `79-favicon-host-newest` | **LANDED 2026-10-19** (the owner's "Land C35" + "one installer with both"; pushed `5468e7a7`; LOCAL.md 92; installer **0.18.154.80**, chrome.dll = the tested build) -- was: BUILT + CHECKED (LOCAL.md 91): check-icons 2/6 on the unfixed build, 6/6 Default + Dcheck, 0 markers; regression 14/14; check-c35 Dcheck 13/13; 256/256; design review (4 lenses + skeptic) + deslop + /code-review high. **79 adds an upstream file (71)** and breaks a never-built upstream test (recorded). Next: the owner's look, then landing after C35 |
| **C4** | **Drag onto a workspace on the bar** (`ideas.md`; design 5 "the drag is still open"): a Today tab (or several, a group, a split) or a pinned page dropped on a workspace's chip moves there -- the chip only lights while held; a moved Today tab goes to the TOP of that workspace's Today, for the drop and both menus (the owner's rule); a chip dragged along the bar reorders the workspaces | `80-move-to-top`, `81-drag-to-workspace` | **LANDED 2026-10-20** (the owner's try ALL PASS + "Land C4"; pushed `dd58d127`; LOCAL.md 94; installer **0.18.154.82**, chrome.dll = the tested build) -- was: BUILT + CHECKED (LOCAL.md 93): workflow then "lean" (~6.06M); design review (26 findings, 1 HIGH: zen's unclaimed band above the bar) folded in; code review 0 findings; Default + Dcheck 0 errors; 256/256; **check-c4 67/67 Default + Dcheck** (the 00-79 control FAIL as designed), the regression suite all pass, the try rehearsed PASS -- the first runs' 7 failures were all the harness's. Next: the owner's `try-c4.ps1`, then "land C4" (installer 0.18.154.82). No new upstream file (71) |
| **C7** | **Switch workspace by a sideways scroll** (`ideas.md`; design 5 deferred it): a touchpad's two-finger swipe, a thumb wheel or a tilted wheel over the sidebar shows the workspace beside this one on the bar, once per swipe, stopping at the ends (the owner's answers) | `82-swipe-workspace` | **LANDED 2026-10-20** (the owner's try with an MX thumb wheel + "lands the build"; pushed `ae2e3521`; LOCAL.md 96; installer **0.18.154.83**, chrome.dll = the tested build) -- was: BUILT + CHECKED (LOCAL.md 95): solo; our handler modelled on Chromium's `VerticalTabStripFocusSwipeController` (behind a disabled flag); code review 7 findings, 4 fixed; Default + Dcheck 0 errors; 256/256; **check-c7 13/13 Default + Dcheck** by posted wheels (the 00-81 control FAIL as designed); **the regression suite all pass** (rebase-checks 8/8, c12, c2, e19, c3, c14, c35, icons, c4 67/67, c7). No new upstream file (71) |
| **C23** | **Arc's site icons for the pinned pages that drew a globe** (`ideas.md`) | no patch: `arc-icons.py` (kept off the repo: `<local-path>\Helium-workspace\migration\`) | **RUN 2026-10-20 02:52 on the daily profile** (the owner's "Claude runs it tonight"; LOCAL.md 95): 272 globes, Arc had 71 (its `Favicons` by page / its sidebar icon cache / by site) -> 201 left with no local icon; backup `backupsefore-c23`; rehearsed on copies, the written file kept by a 150 s run of 0.18.154.82. **C23.1 RUN 2026-10-20 18:47** (LOCAL.md 97, `<local-path>\Helium-workspace\migration\site-icons.py`, off the repo): Today tabs too (they ask by exact address); 485 -> 160 globe addresses (201 pinned + 289 Today -> 154 + 11), 48 from 39 sites asked once; backup `backups\before-c23-sites` |
| **R** | Rebase (repeatable) | 3.8. **R1 DONE 2026-09-15: 0.16.5 to 0.16.6** (same Chromium 152, Helium-only) — **388 patches, ZERO rejects**; 69 commits replayed with one conflict, in `patches/series`, which is structural and recurs every rebase. Cost a **37,436-target rebuild** although no Chromium line changed, because `pop -a`/`push -a` rewrites every patched file's mtime. Found three runbook gaps, all fixed in LOCAL.md 26: `validate_patches.py --remote` cannot run (`requests` missing), `^FAILED\|error:` false-positives on `webui_js_error:` targets, and the submodule needs `reset --hard` rather than `pull` after a rebase. **R2 DONE 2026-09-15: 0.16.6 to 0.17.0 = Chromium 152→153** — 388 patches, **2 rejects + 1 compile error, all ours**, each fixed toward the shape M153 gave the code (05 lost 35 lines; the compile error was in a *clean-list* file whose patch applied without a murmur); a from-scratch 57,816-step build; `validate_patches.py --remote` now dies in `_parse_deps` on M153 DEPS. Full account in LOCAL.md 27. ****R3 DONE 2026-09-19: 0.17.0 to 0.17.1 (helium-windows 0.17.1.1) = Chromium 153.0.8010.36 to .47** — 89 commits with no stop, **396/396 patches, 0 rejects, 0 compile errors, no line of ours changed**; a new pre-flight (Chromium's changed files vs our hook files and our included headers: 3 and 0) predicted it. The smoke test found two pre-existing issues, not rebase ones: a grader bug in `check-smoke.ps1` (fixed) and the rail overflowing the strip's bottom row (to E13). LOCAL.md 33. **R4 DONE 2026-09-21: 0.17.1 to 0.17.2 (helium-windows 0.17.2.1) = Chromium .47 to .52, and the build moved from ninja to siso with CIPD-installed tools** -- 106 commits with no stop, **401/401 patches, 0 rejects, 0 compile errors**; 5 fuzzed hunks (03, 08, 09) refreshed, context only. A read-only pre-flight workflow forecast all of it and found the one thing no text comparison could: Helium now enables Chromium's back-to-opener, whose close skips Recently Closed and our Ctrl+W diversion, so it could destroy an anchored tab -- `33-back-to-opener-anchor` (1 upstream file + 1 GN dep). Lazy session restore (new upstream) leaves persistence intact. LOCAL.md 36. **R5 DONE 2026-10-01/02: 0.17.2 to 0.18.2 (helium-windows 0.18.2.1) = Chromium 153.0.8010.52 to 154.0.8037.92** -- 209 commits, one `series` stop; **426/426** after 8 rejects and 6 fuzzed hunks, every one forecast by a read-only pre-flight workflow (5 agents, 1.36M tokens) -- including the one silent HIGH, 04's WorkspaceService hunk fuzzed into the wrong function (moved back by hand). M154 moved the tab menu's enum (`tab_context_menu_command.h`) and `NewTabButtonMenuModel` to new files: 56 upstream files. Early compile of our 44 files 0 errors; Default 54,849 + Dcheck 57,677 steps, 0 errors; 183/183; hands-free suite 16/16 on both builds; owner checks 4/4, incl. reconcile's move path under DCHECK. LOCAL.md 59. **R6 2026-10-28/30: 0.18.2 to 0.20.2 (helium-windows 0.20.2.1) = Chromium 154.0.8037.92 to 156.0.8078.73** -- the source is a tarball now; 387 commits (`range-diff` all `=`); 19 patches fixed by hand, then 471/471 with 0 fuzz; the hunks' function labels unchanged but for six deliberate moves; checkers found 02's compile error and 57's dead hunk, the first build 67's lint (a 156 rule). Helium 0.20's FloatingStyle enum reworked 50. Patch 94 put the sidebar's boxes over the page in zen mode (ZB: inside on R6, off-window on the 154 build). Default 11,923 + Dcheck 57,917 steps, 0 errors; 307/307; 95 patches, 75 upstream files. LOCAL.md 117; **LANDED 2026-10-30** (force push over `backup/pre-0.20.2`, installer 0.20.156.95), LOCAL.md 118 |
| **HS** | **Hook shrink** (`fork-review-2026-10-25.md` "The plan" step 5): the review's rebase findings that did not break at R6, each cut to a one-line hook into fork code, in five parts by Chromium file -- 1 sessions and restore, 2 tab strip, 3 commands, 4 sidebar view hooks, 5 toolbar -- then the LOW-bug polish batch | **HS1 (part 1) 2026-10-30: #22 #23 #45** -- 08 21 38 58 59 87 edited in place (`refresh -f`, no pop; still 95 patches), the fork-owned `workspace_restore_hooks.{h,cc}`, `session_service_base.cc` the 76th upstream file; the six patches' added lines in Chromium files 175 -> 71. Chain proof 71/71, Default + Dcheck 0 errors, 307/307; the hands-free suite on the owner's word. LOCAL.md 119. **HS2 (part 2) 2026-10-31: #4 #6 #7 #18 #33** (+ 92's #35 guard moved) -- 14 21 25 41 42 43 63 73 86 87 91 92 edited in place, still 95 patches; the fork-owned `ui/tabs/workspace_tab_strip_hooks.{h,cc}` (in `tab_strip_impl`); the twelve patches' added lines in Chromium files 189 -> 57. Chain proof 37/37, Default + Dcheck 0 errors, 307/307, the suite all pass (after a c14 script fix), the owner's two by-hand checks PASS. LOCAL.md 120. **HS3 (part 3) 2026-11-01: #16** + the owner's 8 label renames -- 03 15 17 31 55 61 64 87 93 edited in place, still 95 patches; the fork-owned `ui/workspace_command_hooks.{h,cc}` (in `browser_command_controller_impl`); the fork's lines in `browser_command_controller.cc`, `browser_shortcut_metadata.cc` and `ui/BUILD.gn` 170 -> 41. Chain proof 111/111, Default + Dcheck 0 errors, 307/307, the suite 16/16 (e18 after a suite fix), the owner's four by-hand checks PASS. LOCAL.md 121. **HS4 (part 4) 2026-11-01: #28 #29 #32 #34 #41 #44** (#24 #43 checked, now tripwires) -- 02 36 37 41 45 55 56 71 73 81 88 edited in place, still 95 patches; the fork-owned `views/tabs/common/workspace_view_hooks.{h,cc}` (in `views/tabs/common:impl`); 75 upstream files (02 left `unpinned_tab_container_view_layout.h`); the fork's lines in the six view files 263 -> 104. Chain proof 71/71, Default + Dcheck 0 errors, 307/307, the suite 22/22, the owner's four by-hand checks PASS. LOCAL.md 122. **HS5 (part 5) 2026-11-02: #9 #11 #12 #13** -- 67 68 69 70 edited in place, still 95 patches; the fork-owned `workspace_toolbar_rows.{h,cc}` and the Toolbar list's own element `workspace_toolbar_list.{ts,html.ts,css}`; 75 upstream files (`toolbar.css` out, `side_panel/customize_chrome/BUILD.gn` in); the fork's lines in Chromium's toolbar files +621/-116 -> +248/-59. Chain proof 43/43, Default + Dcheck 0 errors, 307/307, the suite 5/5 (81 PASS lines); the owner's look found Alt+Up after a click on a row dead since wish 6 -- fixed, `check-w6a` 5g/5h. LOCAL.md 123 |
| **A** | **The fork's own default profile folder** (`negative-review-2026-11-01.md` route A: installer F1 F4 F5 and the overlooked F5): a launch without `--user-data-dir` opens `%LOCALAPPDATA%\Helium Workspaces\User Data` (the installer's profile: nothing moves), no in-browser "make default", the installer asks before an older setup goes over a newer install | **PUSHED 2026-11-02, patch 95 (`620218bb` + docs `7a62fe65`, no installer)**: `user_data_dir.cc` + `chromium_install_modes.h`, 77 upstream files; the comparison copy and the taskbar id deliberately unchanged. Default 0 errors, `check-95` red 0/2 then green 2/2. LOCAL.md 124 |
| **B** | **Data-file safety** (`negative-review-2026-11-01.md` route B: data-files F1-F4, overlooked F8, transfer F7, privacy F6): a newer build's workspace list is never written over; a Pins or Archive file that cannot be read, or was set aside as .bad, is told in Chromium's "Profile error occurred" box; the Archive screen's Clear also clears the before-import backups; no log line names a site, an address or a title without `--helium-workspaces-log-addresses`. The Archive stays separate from Clear browsing data (the owner) | **PUSHED 2026-11-03, patch 96 (`5f44407a` + docs `b4ad9b13`, no installer)**: 22 fork-owned files, still 77 upstream. Default 0 errors, `workspaces_unittests` 310/310, `check-96` red 0/5 then green 5/5 + 2/2, Dcheck 0 errors + `check-96` 7/7, 0 markers. LOCAL.md 125 |
| **C** (route C) | **The Arc import says why nothing arrived** (`negative-review-2026-11-01.md` route C: arc-import F4 (b)(c)(d), F8, F5's first half; not the deferred C below): a missing, too-big, unreadable or unknown-format Arc file each has its own sentence; "On startup" changes only when tabs arrived, at the end, never under a policy; the import time is saved only when something arrived. C2 (arc-import F1 F2 F3 F5 F6 F7) goes to release prep, switch-day F1-F8 to D | **PUSHED 2026-11-03, patch 97 (`24f7e68e` + docs `af03cb3b`, no installer)**: 7 fork-owned files, still 77 upstream. Default 0 errors, `workspaces_unittests` 311/311, `check-97` red 1/5 then green 5/5, Dcheck 0 errors + `check-97` 5/5, 0 markers. LOCAL.md 126 |
| **D** | **Installer robustness, the update check, switch-day retired** (`negative-review-2026-11-01.md` route D: installer F2 F3 F6 F7 F9 + F8's note, data-files F6-F8, switch-day F1-F8): setup asks again before it deletes, checks the free space, can always be uninstalled, never hangs on the taskbar step, says what a data delete left and names its Helium and Chromium; the update check records FAILED instead of a made-up verdict; the switch-day tools deleted (the owner) | **PUSHED 2026-11-03 (`30468333` + docs `ff1943bc`, no installer)**: no patch, no browser file, still 98 patches and 77/74/151. `check-d` red 1/10 then green 11/11; the installer fixes need the next installer (LOCAL.md 127's tests). LOCAL.md 127 |
| **C2** (route C, part 2) | **The Arc import's identity** (`negative-review-2026-11-01.md` route C: arc-import F1 F2 F3 F5 F6 F7; not the Ctrl+Tab C2 above): a space is found by Arc's space id, never its title; "already imported" is a list of Arc ids, not a time; an imported tab wears its Arc id until the import finishes, so a cut-off import's restored tabs are not added twice; one import per profile, greyed in every window; a re-run's new pinned tabs go into one "New from Arc" folder (the owner's D1); the bubble counts only new skipped tabs and says when pinned tabs could not be saved | `98-arc-import-identity` | **PUSHED 2026-11-03, patch 98 (`9ce22978` + docs `c5fd8c5f`, no installer)**: 15 fork-owned files, still 77 upstream. Default and Dcheck 0 errors, `workspaces_unittests` 315/315, `check-98` red 0/8 then green 8/8 on Default and Dcheck (green found the tab tag never set: fixed), 0 markers. LOCAL.md 128 |
| **P** (the polish batch, A-C) | **Export/import safety, small bugs, rebase tripwires** (LOCAL.md 129: the 11-01 review's transfer F1-F5, F8-F10, never routed until this batch; review #30 #36 #48 #49 #50 #52; data-files F9; the tripwires for #10 #17 #26 #39 #46 #47 #51 and R6's #4): an export refuses a store that could not be read; an import keeps a copy first or changes nothing, keeps this PC's settings, refuses a script's address and a file on another computer, a list of another version and a file over 128 MB; no Snooze for a grouped tab; the + menu's Export/Import greyed during an Arc import; a ruled link with no main window | `99-polish-fixes` | **PUSHED 2026-11-04, patch 99 (`34c2a313` + docs `ad736a83`, no installer)**: 15 fork-owned files, still 77 upstream. Default and Dcheck 0 errors, `workspaces_unittests` 319/319, `check-99` red 6/6 then green 7/7 (Default and Dcheck), the owner's try 2 PASS + 1 not reachable by a click. LOCAL.md 129 |
| **P-D** (the polish batch, D) | **A reopened window's extra New Tab** (LOCAL.md 130; 119's candidate): the stand-in New Tab for a window whose saved group stays in another window comes at the END of the reopen (`ShowBrowserWindow`), only if the window is still empty -- not the moment the group's first tab, restored first, left it empty | `100-reopen-new-tab` | **PUSHED 2026-11-04, patch 100 (`6af33391` + docs `fbc14db3`, no installer)**: still 77 upstream. Default and Dcheck 0 errors; `check-e14c2-reopen` red (3 tabs for 2) then ALL PASS on Default and Dcheck, Workspaces on and off. LOCAL.md 130 |
| **P-E** (the polish batch, E) | **The menus review's picks** (LOCAL.md 131; the owner's "Use your picks": 1 3a 4a 5 6 7 8b 9b 10 12a 13a 15): the tab menu in three groups under dividers; the pinned page, folder and selection menus grouped, Delete last; Pin to this workspace, Always open ... in the X workspace, Rename tab..., Rename..., Use current page, Hibernate this / other workspaces, Bookmark all tabs; Find tabs and pages in the + menu; Workspace settings focuses its first dropdown only from the keyboard; box titles without the menu's ellipsis; no new message | `101-menu-polish` | **PUSHED 2026-11-04, patch 101 (`8099dc86` + docs `0e1a8808` + `0c9fc450`, no installer)**: 7 files, still 77 upstream. Default and Dcheck 0 errors; `check-101` red 6/6 then green 7/7 on Default and Dcheck, 0 markers; review 7/7 fixed. LOCAL.md 131 |
| **C** | Always-contiguous workspaces (Arc/Zen parity) — **DEFERRED CONDITIONALLY, 2026-09-14**, not scheduled. 2.3 rejected it and those reasons stand: it reinstates the new-tab placement hook, the drag index hook, every fix-up move and the re-entrancy problem, and the first two live in hot upstream files, so it is the **only remaining item that makes every future rebase permanently more expensive** (3.8 budgets ~40 rebuilds). Not placed after E11: Stage 6 is nice-to-haves and must not outrank it | **Both tests must pass first.** (1) The owner has used `Reconcile()` (E9e.4) for several weeks and still wants it — that condition had zero days to run when this was written. (2) The first real rebase has happened and its cost at 21 patches is known, because that number is what decides whether hot-file hunks are affordable at all. **Before building it, write down what it fixes that `Reconcile()` does not** — see 2.3 |

**E8 is the MVP.** It is genuinely useful on its own, and stopping there is a legitimate
outcome, not a failure.

**Stage -1 on Windows is settled** — it is MSYS2 plus `quilt` plus `build.py --dev` inside the
VS Developer Command Prompt. WSL2 cannot drive the MSVC toolchain; do not try.

Realistic total to E9 at beginner level, part-time: **8 to 14 months.** Stage 0 is the gate:
if getting an unmodified build is miserable rather than merely tedious, stop — it only gets
harder from there.

### Off-ramps (not defeat)

- **A:** an extension keeping all tab groups collapsed except one. About 60 lines of JS,
  usable next week, roughly 70% of the Spaces feel on the existing Helium vertical tabs.
  "Convert group to workspace" (Stage 6) is the bridge from A to the real feature.
- **B:** stop at E8. A working two-workspace switcher with persistence is worth having.

---

## 5. Arc feature to mechanism

| Arc feature | Mechanism at 152 | Effort | Stage |
|---|---|---|---|
| Spaces in one window; switching swaps the tab list | tag predicate in `UnpinnedTabContainerViewLayout`, copying the focused-group pattern | Core, **medium** (was high) | 4a |
| Space switcher rail | new view in `VerticalTabStripBottomContainer` (5 Helium hunks, one patch — far cheaper than the region view) ; hidden when only one workspace | Medium | 5 |
| Keyboard switching | `IDC_HELIUM_WORKSPACE_*` via `BrowserShortcutService`, platform-guarded defaults | Low to medium (3.5) | 4a/5 |
| Per-space name, emoji, accent | pref metadata; inline `Textfield`, `ui::ShowEmojiPanel()`, the 8 `TabGroupColorId` values (free dark-mode variants); tints strip and rail only | Low to medium | 5 |
| New tab opens in current space | stamp the tag on insert. **No placement hook** — the Helium `kNewTabNextToActive` pref keeps working untouched | Low | 4b |
| Folders in sidebar | existing tab groups, now tagged. **One level** — groups cannot nest | Low, after model | 4b |
| Per-space pinned tabs | **not** Chromium pinned state (that is Favorites). Helium-side anchors: a live tab with `helium.anchor_url`; drift indicator; Ctrl+W resets and unloads rather than closing (the Zen rule) | Medium to high | 5 |
| Split view per space | composes automatically — but the predicate must handle `SplitTabView` | Low | 4a |
| Drag tab between spaces | drop onto the rail. The tag is what moves; no index math | **Low** (was high — `TabDragController` is untouched) | 5/6. **A menu route shipped at E9c** — right-click a workspace, "Move tab here", moving the whole selection; **the drag: C4** (patches 80-81, LOCAL.md 93) -- the bar is a `TabDragTarget`, a moved tab goes to the top of the other workspace's Today |
| Auto-archive after N hours | closed tabs already carry the tag, so Recently Closed restores into the origin workspace. Add the Zen "close all unpinned in this workspace" first; a TTL timer last | Medium | 6 |
| Swipe between spaces | defer. Cheapest later is the Zen Ctrl+wheel over the strip with a cooldown, not trackpad swipe (scroll-to-switch is already broken in vertical layout, imputnet/helium#1238) | Medium | 6 |
| Space bound to its own cookie jar | **deferred** — no Chromium primitive (see 1) | High | — |
| Sync across devices | none; JSON export/import if ever | — | — |

### Zen ideas worth stealing (Arc has no equivalent)

| Idea | Why | Stage |
|---|---|---|
| Auto-switch when a foreign workspace tab is activated | makes Ctrl+Tab, extensions, links and omnibox switch-to-tab coherent with one branch | 4b |
| Unload space / unload all others | Arc only archives; this frees memory while keeping the list intact — the Helium hibernation path over one workspace worth of tabs | 6 |
| Convert tab group to workspace | one-click migration from off-ramp A | 6 |
| URL routing rules (regex; "add domain to routing" from the tab menu) | Arc Air Traffic Control is macOS-only and contains/equals only; applied post-insert, so it slots into the stamping hook | 6 |
| Hide the rail entirely when there is one workspace | stock Helium stays stock until you opt in | 5 |
| Ctrl+W on an anchor = reset and unload | stops users accidentally losing anchors | 5 |

### Rail context menu

The Zen Space menu is the right template — the Arc folder items belong to the *pinned
section* menu, not the Space menu.

```
Change Name...          Change Icon...          Edit Theme...
--------------------------------------------------------------
Reorder Spaces
--------------------------------------------------------------
New Folder              (= AddToNewGroup with a fresh NTP)
Create Space
Delete Space            (confirm; disabled when only one)
```

Stage 6 adds: Unload Space, Unload All Other Spaces, Space Routing Settings, Export Space to
Bookmark Folder (`chrome::BookmarkAllTabs` over the tabs of one workspace).

**Deliberately absent:** *Set Profile* — both Arc and Zen have it, but Chromium 152 has no
per-tab storage partition, and a greyed-out item is a promise the fork cannot keep. *Live
Folders* (the Arc GitHub auto-folders) — out of scope.

**Delete Space** = confirm, close the tabs of that workspace with
`CLOSE_CREATE_HISTORICAL_TAB` (so they land in Recently Closed), erase the metadata, and if it
was active switch to a neighbour. Refuse when it is the only workspace. ~~A restored tab whose
tag names a deleted workspace is adopted by the active one (the Zen orphan rule)~~ — never
resurrect the dead workspace.

**Built at E9b, 2026-09-12, with three corrections (LOCAL.md §18):**

1. **The orphan sentence above is wrong; §2.4's version is right.** A tab whose tag names a
   deleted workspace **resolves** to the default workspace — it is not *adopted* by the active
   one. Adoption depends on which workspace happened to be showing when the tab arrived, so the
   same tab lands differently depending on timing and differently again in another window, and it
   means writing a tag from a path that only reads one. Resolving is a pure function of the tag
   and the list, and it keeps the tab recoverable if a workspace with that guid ever exists again.
2. **"Refuse when it is the only workspace" is not the rule.** The *default* workspace can never
   be deleted, however many exist, because `ParseWorkspaces()` prepends it whenever the stored
   list lacks it — the write would report success and change nothing.
3. **No confirmation shipped.** Every tab it closes goes to Recently Closed with its tag intact,
   so `Ctrl+Shift+T` is the undo; a modal confirm is a second dialog class for a reversible
   action. Add one if a workspace is ever lost that the owner wanted.

**Also at E9b: the rail is shown whenever Workspaces is enabled**, not hidden at one workspace as
the row in §5's table says. That rule and "the `+` that creates the second workspace lives on the
rail" cannot both hold — a fresh profile could never get a second workspace.

### Owner requests, 2026-09-10 -- input for Stage 5

Raised after driving E6c by hand. The first two are already sited in this document; the third is
new.

| Request | Where it lands |
|---|---|
| A small control at the bottom of the tab strip, to switch workspaces or add one | This is the rail. 3.2 already picks `VerticalTabStripBottomContainer` for it -- 5 Helium hunks, against 22+ for the region view -- so the request and the cheapest hook agree. **The switch half shipped at E9a and cost 3 hunks in 1 file, not 5 in 2** (LOCAL.md §17); "or add one" is E9b |
| "New workspace" / "Switch workspace" in the tab-strip context menu | The `tab_menu_model.cc` family (4 Helium patches), beside the planned `ExistingWorkspaceSubMenuModel` for "Move tab to workspace". **"Move tab to workspace" shipped at E9d**; "New workspace" there is deliberately not built, since it needs a second `ContextMenuCommand` for what the rail's `+` does in two clicks (LOCAL.md §20) |
| The `+ New Tab` button doubling as add-workspace | **New, and worth a design decision rather than a patch.** Do not change its click: it is the most-used control in the strip, and an accidental workspace is expensive to undo, because deleting one closes its tabs. A right-click or long-press on it reaches the same place without putting a near-destructive action under the busiest button, and it is what both Arc and Zen do -- their `+` for spaces is a separate control on the rail. **Shipped exactly that way at E9e**: "New workspace" on the right-click menu, left-click untouched |

---

### E10 spec -- anchors, decided 2026-09-16 from PR #1578

**What #1578 is.** Read in full on 2026-09-16 (fetched read-only as `upstream/pr-1578`, head
`d6ea19a3`, base `bf15608b` = tag 0.12.0, Chromium 148; closed unmerged 2026-08-08). A flag-gated
experiment of three patches -- `anchored-tabs-rename-restore` (630 lines), `-startup-setting` (239),
`-group-hibernation` (3,329) -- with **~70 hunks across ~50 upstream files**: 19 in
`tab_strip_model.cc`, 9 each in `session_restore.cc` and `browser_tabrestore.cc`, 12 in
`vertical_tab_view.cc` and 11 in `vertical_unpinned_tab_container_view.cc`, files Helium has since
restructured into `views/tabs/common/`. Its patches will not apply to 153; they are a **map, not a
source**. It bundles four features: (1) *anchored* means "pinned or in a group", and closing such a
tab **hibernates** it instead; (2) an *anchored URL* the tab is reset to when it hibernates, with a
"Replace anchored URL with current" menu item; (3) *rename tab* (a custom title); (4) a startup
setting that restores hibernated tabs as hibernated.

**What we take, what we change, what we drop.**

| Piece | #1578 | E10 |
|---|---|---|
| Anchor identity | implicit: any grouped or pinned tab, behind a flag | **explicit**: `anchored` + `anchor_url` on `WorkspaceTabData`, set by "Anchor tab" in the tab menu. Per-workspace by construction -- the tab already carries the guid. Never pinned tabs (Favorites, above) and never "every grouped tab" (groups are folders here) |
| Unload | `TabManager::DiscardTabByExtension` (unconditional; still present at 153), then rewrite the discarded entry's URL, virtual URL and title to the anchor, so the reload lands on the anchor rather than the drift | the same call and the same rewrite. Helium's own hibernate goes through the eligibility-gated `CanDiscard` path; an anchor must bypass it, or Ctrl+W on an "ineligible" tab silently does nothing. (**Corrected 2026-09-20, LOCAL.md 35:** that path is EXTERNAL and always eligible at M153, so neither gates forms or audio; `32` keeps a page with a "Leave site?" listener live instead) |
| Ctrl+W | `browser_commands.cc` `CloseTab`: single selection, not a split, anchored -> activate a fallback tab, hibernate, return | the same, one hunk in a file we already own a hunk in (E7a; 5 Helium patches). The fallback search uses **our visibility predicate**, not #1578's group rule, so Ctrl+W on the last visible tab of a workspace lands inside that workspace or spawns into it (E9f's path) |
| Menu | "Replace anchored URL with current" | "Anchor tab" / "Unanchor" / "Reset to anchor" / "Replace anchor with current", through our own `SimpleMenuModel` delegate the way E9d's submenu did -- no `tab_strip_model.cc` command plumbing |
| Omnibox drift rule | `browser_navigator.cc`: a URL typed into an anchored tab opens a **new** tab (2 hunks; **0 Helium patches** touch the file -- **WRONG at M153, see the E10b correction below**) | take it in E10b: the cheapest hook in the set, and the Arc behaviour a pinned tab implies |
| Persistence | four session keys via `AddTabExtraData`, plus 9 hunks in `session_restore.cc` to restore *hibernated* | the keys ride in `PopulateWorkspaceExtraData()` -- E8's one door, **0 new hunks** -- and restore as a normal tab (session restore lazy-loads background tabs anyway). Drift across a restart is accepted in v1; "Reset to anchor" is one click |
| Rendering | `AnchoredGroupIndicatorView`, a group hibernate button, a "Clear ungrouped" button, dimmed favicon via `tab_ui_helper` (Helium-hot, 2+1 patches) | **none in v1**: 153's `TabData::is_tab_discarded` already reaches the renderer (`tab.cc`, hover card), so a hibernated anchor looks like any discarded tab. A drift dot is Stage 6 if it is ever missed |
| Rename tab | custom title, persisted as `helium.custom_title` | **not E10** -- workspace-agnostic; an E11 item, and 2.6's carrier makes it small |

**Hook budget.** Three upstream files -- `browser_commands.cc` (1 hunk), `tab_menu_model.cc` (1, at
E9d's existing site), `browser_navigator.cc` (1 block + 1 dep line, **E10b DONE**; the file is `ui/navigator/browser_navigator.cc` at M153 and **two Helium patches touch it**, neither near `NormalizeDisposition` where our hook went) -- against #1578's fifty. Everything else is
ours: two fields on `WorkspaceTabData`, a `workspace_anchors.{h,cc}` beside `workspace_service.cc`
holding the hibernate-and-rewrite and the fallback search, tests for the extra-data round trip and
the fallback choice.

**Split.** **E10a** = the tag, Ctrl+W hibernate-and-reset, the four menu items, persistence of the
two fields (one patch, `21-anchors`, one session). **E10b** = the omnibox rule and restart fidelity,
only if E10a gets used and drift annoys. The design's earlier open question -- "Chromium pinned
survive restart with session restore off; anchors won't" -- is settled by E8: tags survive exactly
when session restore is on, and anchors inherit that. No pref-backed write.

**Risks to carry into E10a.** `DiscardTabByExtension` **replaces the `WebContents`**; our observer
already logs `tab contents replaced at index` (E7b) and re-stamps the guid, and the two new fields
must ride the same path or an anchor forgets it is one the moment it hibernates. `CloseTab` runs as
a command, outside the observer, so 2.2 is not in play -- but the fallback activation is a mutator,
and it must happen **before** the discard, as #1578 does it. And "Anchor tab" on a tab in a split:
decline, as #1578 declines Ctrl+W on splits.

### E14 spec -- Arc import, auto-archive, close-on-anchor; decided 2026-09-21 from the research workflow

Read from the **patched 153.0.8010.52 tree** (Helium 0.17.2 + our 34 patches), not from memory of
152: seven read-only researchers, one question each; the two skeptics died on the monthly spend limit,
so the eleven claims this spec stands on were re-read by hand (LOCAL.md 37 lists them). Full reports:
`<local-path>\Helium-workspace\research\e14-research-2026-09-21\`. **Rows marked OWNER are recommendations,
confirmed at the start of the chunk that needs them.**

**Four things the roadmap had wrong, and one it no longer needs.**

| Roadmap said | The tree says |
|---|---|
| `AddRestoredTab`, *then* `SetTag` / `SetAnchored` / `SetCustomTitle` | **Wrong order, and two of the three cannot do it.** `SetTag` is private; `SetAnchored` anchors at the *committed* URL, not a given one; and a tab inserted untagged is stamped with the ACTIVE workspace first, so the later write is a real change = one relayout per tab, 3,900 times. Instead put `helium.workspace` / `helium.anchor_url` / `helium.custom_title` in `AddRestoredTab`'s **`extra_data`**: 08's hook (`browser_tabrestore.cc:99`) applies them BEFORE the insert, `ResolveGuidForInsertedTab` keeps an existing tag, and `SetTag` returns before `Notify` when the tag did not change. **Zero new hooks.** The guid must never be empty -- pass the literal `default` |
| groups via `AddToNewGroup` + `TabGroupVisualData(title, colour, collapsed)` | `AddToNewGroup` ignores visual data and moves tabs. Pass a fresh `TabGroupId` as `AddRestoredTab`'s `group` argument (first tab creates the group through `AddToGroupForRestore`, later ones are clamped into it), then `ChangeTabGroupVisuals(id, {title, colour, /*is_collapsed=*/true})`. That path sends no `OnTabGroupAdded`, so the group is **not a saved group** until `TabGroupSyncService::SaveGroup(...)` is called once after its last tab, as `browser_live_tab_context.cc` does |
| split -> `AddToNewSplit` | works, but wants a `SplitTabCreatedSource`, logs UKM and may show a promo. `RestoreSplit(SplitTabId::GenerateNew(), {i, i+1}, SplitTabVisualData())` is the quiet one and is what Helium's lazy restore uses between sleeping tabs |
| "3,181 tabs renamed in Arc" | 3,181 have a non-null `item.title`, but **3,175 equal `savedTitle` byte for byte** (3,170 created in one hour -- a bulk import into Arc). **Six** are real renames |
| "find the switch that stops session restore waking every tab" | **Nothing to find.** Helium 0.17.2's `lazy-session-restore.patch` (no flag, no pref) passes `kDeferUntilActivation` for every non-selected tab; it added that as `AddRestoredTab`'s **16th parameter**, and its own `AddDeferredPinnedStartupTab` (`startup_browser_creator_impl.cc:221`) is the template for a sleeping tab from a bare URL |

**The one precondition nobody had written down:** the tabs come back after a restart only if
`session.restore_on_startup` is "Continue where you left off". The Windows default is the New Tab page.
The import checks `SessionStartupPref` and sets `LAST` (telling the owner), or refuses. OWNER --
**decided 2026-09-22: set it, telling the owner** (the E14c paragraph below).

**Mapping (unchanged in intent, corrected in mechanism).**

| Arc | Here | How |
|---|---|---|
| space | workspace (name, emoji) | `prefs::AddWorkspace` + `SetWorkspaceIcon` + `WriteWorkspaces`, **never `CreateWorkspace()`** (it switches and spawns a loaded New Tab per space). Written before the space's first tab, or the tag resolves as an orphan. Icon = `emoji_v2`, else the `emoji` int as one code point |
| favorite (`topAppsContainerIDs`, 2) | Chrome pinned tab | `pin=true`, inserted FIRST while the strip is small |
| space-pinned tab | anchored sleeping tab | `extra_data[helium.anchor_url] = GURL(savedURL).spec()` and the SAME spec as the entry's virtual URL, or the tab reads as drifted. http(s) only (31) |
| folder | collapsed group titled `A > B` | one group per folder that has direct tabs; a folder's own tabs come before its subfolders' groups (5 of 28 folders mix the two). OWNER |
| split view (3; one sits inside a folder) | real split | the two tabs adjacent, then `RestoreSplit`, all in one task |
| Today tab | normal sleeping tab in its own space's workspace | `last_active_time` = Arc's `timeLastActiveAt`, else `createdAt` (**40% of Today tabs have no `timeLastActiveAt`**; `createdAt` is on every item). Both are doubles of seconds since 2001: `+ 978307200` |
| Arc rename | custom title | only where `item.title != savedTitle` (6 tabs); the other 3,175 show Arc's name while asleep from the entry's own title and pick up the real page title on first load. OWNER |
| 9 tabs with no URL, `chrome://` or `arc://` | skipped, counted in the report | OWNER |
| Little Arc windows | ignored | they are extra `littleBrowser` pairs in `sidebar.containers`. **`import-arc.py:77` takes "the first container with `spaces`", which is a Little Arc window in 2 of Arc's own 24 snapshots.** The main sidebar is the dict after the `{"global":{}}` key-dict |

**Decided by the owner 2026-09-22 and built as `35` (LOCAL.md 39):** the three OWNER rows above as
recommended (folder order, 6 renames, skip the 9), and re-import option **(a)**, one timestamp. On the
real file: 28 folders become **22 groups** (six have no tabs of their own), 3,865 tabs, 9 skipped.

**Decided by the owner 2026-09-22 for E14c (`36-arc-import`)** -- recorded from a docs session while
the chunk was already running in another, so each answer was then checked against the chunk's patch
and script: one reached it as a change, two were withdrawn for what was already approved and built.
(1) The import may switch "On startup" to "Continue where you left off", telling the owner;
`local/check-e14c.ps1` already grades it. (2) The tabs go into a **new window**, not the one whose
rail was clicked. **A change to the importer as built**: the patch creates no window, its first import
filled the current one, and the script's owner-observed line reads "same workspace after the import".
E14c creates the window before the first insert and re-words that check. **Withdrawn the same evening by the owner, after rehearsing the new-window build (LOCAL.md 40):** closing the import's window before the original dropped it from the session, so the next launch restored the original window alone -- with the real import that is 3,873 tabs gone to one Recently Closed entry. The import fills the window whose rail was clicked, as first built. (3) Folders become **saved
groups, as built**: the importer calls `TabGroupSyncService::SaveGroup` once per group after its last
tab, which the owner accepted in the chunk session, so the gate's `SaveGroup` timing below stands. A
"plain groups, no `SaveGroup`" answer given here the same day was withdrawn. (4) The gate's pass line
is under "The scale gate" below: **the numbers in `check-e14c.ps1` won** over a looser line recorded
here first.

**Gated 2026-09-23 (LOCAL.md 40):** the owner chose **no folder cap** -- every Arc folder a group, all 3,862
tabs -- knowing the cold start then takes minutes (360 s with the big workspace active, 133 s with it
hidden) and the close up to 92 s. The strip's own layout is the cost (profiled, four O(tabs)-per-view
places, one of them ours and fixed); **E14c.1** adds a bulk-mode hunk to the layout manager.
**Done 2026-09-23 (`37-strip-bulk-layout`, LOCAL.md 41):** the cold start with the big workspace active
went 360 s -> 119 s. The close is NOT the strip's layout -- a hunk aimed at it was built, proved to fire
and removed for buying nothing -- and ~78 s of every close is profile teardown.

**Every insert appends (`tab_index = count()`).** Upstream's `SessionServiceBrowserHelper` writes three
session commands for every tab *after* the insert point, so a mid-strip insert is O(n) and an append is
O(1). Same reason: never move a tab, build each group and each split consecutively.

**Where the code goes.**

| Piece | Home | Upstream files |
|---|---|---|
| Arc JSON -> plain-value plan (`ArcImportPlan`: favorites, workspaces, units of group > split > tab), `FromArcSeconds`, the "already imported" filter, cycle guard + depth cap | new leaf target `:arc_import`, `//base` only, tests in `workspaces_unittests` (3.10). `base::JSONReader::ReadDict(json, base::JSON_PARSE_RFC)` -- `options` has no default; the type is `base::DictValue` | **0** |
| Read + parse | `base::ThreadPool` `MayBlock` task -> reply on the UI sequence, which is a posted task and so may mutate the strip (2.2). Exact path under `base::DIR_LOCAL_APP_DATA`; never glob (23 dated backups sit beside the file). 64 MB read cap. **No file picker** | **0** |
| `ArcImporter` | in `:workspaces`, Browser-free, owned by `WorkspaceService`. `chrome::AddRestoredTab` lives in `//chrome/browser/ui` (the GN cycle again, E10a), so it is **handed in as a `RepeatingCallback`** -- not a `FunctionRef` like `DiscardFn`, because it may outlive one call | **0** |
| Entry: rail `+` menu "Import from Arc..." | the rail binds the callback, including `browser_tabrestore.h` with no GN dep -- the third include of that kind (31's recorded row). **Fallback if it will not compile:** `IDC_HELIUM_WORKSPACE_IMPORT_ARC 34128` (34128-34139 are free in E6b's block) handled in `browser_command_controller.cc`. The rail route wins because `03`'s hunk in that file has needed a fuzz refresh at both R3 and R4 | 1 (`generated_resources.grd`, strings, already ours) |
| Our own quadratic | `TabGroupedStateChanged` scans the whole strip by index (each lookup itself a linear walk) **per grouped insert**, at import and at every start. Read only `group_model()->GetTabGroup(g)->ListTabs()`'s first other member. Ships with the importer | **0** |
| Re-import | OWNER. **(a)** one number -- "last import time"; a re-run adds only Arc items with `createdAt` after it, so a tab closed or archived here stays gone. `ponytail:` a crash mid-import cannot resume. **(b)** a ledger of ~3,900 Arc item ids (~155 KB) in a sibling pref `helium.workspaces.arc_import`, which resumes but grows `Preferences`. Never space + URL: 118 URLs repeat in space 1, one of them nine times. Recommended: (a) | **0** |

**First run is one synchronous loop**, because session restore rebuilds the same tabs the same way at
every start -- the import's duration *is* the cold start's. Slice into posted tasks (WeakPtr, whole
units, `IsDeleteScheduled()` / `closing_all()` checked per slice) only if the gate says so.

**The scale gate** (roadmap; testprofile, the real file): import time, cold start to a usable strip,
browser-process memory with everything asleep, renderer count, strip scroll in space 1, workspace
switch latency, exit time, session file size, **and the local no-cache server's log showing fetches for
the selected tab only, after the import and after two restarts**. Reading could not settle any of it:
a sleeping tab has no renderer but is still a full `WebContents` + ~100 helpers + a `TabView` (views
are built for hidden tabs too, laid out at height 0), and the vertical strip recomputes its layout on
every view add. If it fails at 3,900 and passes near 1,000, the roadmap's fallback stands: space 1's
folders stay bookmarks (E12), everything else becomes tabs -- the parser and importer are needed either way.
Also measure there: `SaveGroup` on a 300-tab group; whether Ctrl+Shift+T on a closed imported group
wakes every tab and drops anchors (inferred, not read); "Close all tabs" on a big workspace (each
single close costs ~3n session commands).

**Pass line, decided by the owner 2026-09-22 and coded in `local/check-e14c.ps1`** -- the script is
the authority, this is its summary. Two runs on `testprofile` with the real file: run 1 imports, run 2
is a cold restart that must bring the tabs back by itself. Graded from the logs and the script's own
3-second measurements: every planned tab created, one insert line per tab, tags arriving BEFORE the
insert (at most a handful of relayouts), no workspace switch and no spawned tab, startup set to
continue; the restore loop finished **within 10 s**; browser process **under 1536 MB private** with
the tabs asleep; **renderers <= 20** (sleeping tabs own none); exit **within 10 s** of the window
close; 0 crash markers; a re-run imports almost nothing. Owner-observed: groups collapsed and named,
only the clicked tab loads, scrolling smooth, the cold-start count in your head, and the no-cache
server log showing fetches for the selected tab only, after the import and after two restarts (the
script does not grade that one). Import time is not gated: the first real import took **324 s for
3,873 tabs on the Dcheck build**, and `local/probe-e14c.ps1` (an ETW profile) exists to find where
the seconds go. A looser line (15 s, 2 GB, renderers +2, import <= 60 s) was recorded here an hour
after the script and withdrawn the same day.

**Close on an anchored tab = reset** (`34`, first, independent of everything above).

| Path | Today | E14a |
|---|---|---|
| Ctrl+W | diverted in `chrome::CloseTab` (21) | unchanged; may shrink to the shared virtual |
| X button, middle-click, both strips | `TabView` -> `TabStripCollectionController::CloseTab` -> `TabStripModelDelegate::CloseTab` -> closes | door 1: top of `BrowserTabStripModelDelegate::CloseTab` |
| tab menu "Close tab" | `TabStripModel::ExecuteContextMenuCommand` -> `ExecuteCloseTabs`; never sees the delegate | door 2: top of `case CommandCloseTab`, only when `GetTabsForCommand` returns exactly one tab |
| window close, Close group, Close other / below, multi-selection, Close all tabs, Delete workspace | real closes | **stay real closes** -- none passes either door |

Both doors call one new default-false `TabStripModelDelegate` virtual wrapping `HibernateAnchoredTab`,
which is already general over any tab. Five upstream files, **all already ours** (05, 21). Neither site
is an observer or holds the reentrancy guard; one level lower (`ExecuteCloseTabs`) does, and would CHECK.
**DONE as `34`, 2026-09-22 (LOCAL.md 38); the owner said yes to all four, and the "Close group"
confirm moved to E14c because its site is an upstream views file no patch touches yet. The test also
settled the last sentence below: a never-loaded anchor IS discarded and hibernated, tag and anchor kept.**
OWNER, all four: X on an anchor that is **already asleep** does nothing visible -- after the import that
is nearly every tab in space 1 (recommended: accept, it is Arc's rule; Unanchor first to remove);
"Close other tabs" / "Close tabs below" skip anchors as they skip pinned tabs (recommended: yes, both
sites are ours); "Close group" over anchors gets 32's count confirm (recommended: yes); Tab Search's
own X stays a real close (recommended: yes). Verify on a **never-loaded** imported anchor too: it is
not `WasDiscarded()`, so the discard may decline.

**Auto-archive** (`37`). *Superseded 2026-09-27 (the owner): the record is Arc's own archive -- a file of our own
keeping every close per workspace, with an Archive screen -- not bookmarks (design 4, E14 row); the spec is redone
in **E14d research** -- done, "E14d spec" below. The table below is kept for its rules, which still apply: the clock,
the never-archived list (add pinned pages, E15), the sweep's limits, the setting's values.*

| Piece | Decision |
|---|---|
| Clock | `WebContents::GetLastActiveTime()`: set from `AddRestoredTab`'s argument, **already persisted by the session service and handed back at every restore** -- no key of ours. It is stamped when a tab becomes VISIBLE and never when it is hidden, so it means "last shown": a tab sat on for 13 hours is 13 hours old the moment it is left. Hence an in-memory `left_at` stamp on `selection.old_tab` (bookkeeping, legal in the observer); the sweep uses the later of the two. `ponytail:` not persisted across a restart |
| Pref | `helium.workspaces.archive_after_minutes`, int, sibling of `enabled` (2.4). 720 / 1440 / 10080 / 43200 / **0 = Never, the default** (OWNER). Minutes, so a test can set 2 and watch a sweep. `IsDueForArchive(last_used, now, minutes)` is a free function in `:prefs`: false for Never, a null stamp or a future one |
| Never archived | pinned; anchored (read the raw tag, not the gated `IsAnchored()`, so an anchor is safe while the feature is off); the active tab; a split member (v1); and, for a LOADED tab, audible or recently audible, captured / mirrored / DevTools / PiP, or `MayHoldUnsavedWork()` = `AsksBeforeLeaving()` **or** `PageNode::HadFormInteraction()` **or** `HadUserEdits()`. One new dep, `//components/performance_manager` (no `//chrome` deps; main-thread graph at M153). A sleeping tab has no document: age alone decides |
| Why the listener test stays | a timer closing a background page with a live `beforeunload` handler raises an **app-modal "Leave site?" out of nowhere**. Such tabs are skipped, never closed. The same helper replaces `AsksBeforeLeaving()` in Unload and Ctrl+W-on-anchor (**add** the form signal; replacing would let PDFs sleep, 35) and Unload skips already-asleep tabs before counting -- 36's two hand-offs |
| Sweep | `base::RepeatingTimer` on `WorkspaceService` (one per window, dies with it, never in an observer), every 5 min, **at most 25 tabs per sweep**: each close costs ~3n session commands at n = 3,900. **Bookmark first, close only if `AddURL` returned a node**; the whole sweep returns early while the bookmark model is not loaded. `CLOSE_CREATE_HISTORICAL_TAB` for a batch of 5 or fewer, else `CLOSE_NONE` -- a big batch would push every hand-closed tab out of Recently Closed's 25. Skips while an import runs |
| Record | `Other bookmarks > Archive > <workspace>`; the workspace folder is matched by a `helium.workspace` meta-info guid, so renaming a workspace does not fork its archive. Newest first; no duplicate URL within a folder. Deps `//chrome/browser/bookmarks`, `//components/bookmarks/browser` -- **run `gn gen` before writing any C++** to prove there is no cycle. A never-loaded import has no History entry; the bookmark is its only record (OWNER) |
| Entry | rail `+` menu "Archive" -> `chrome::ShowBookmarkManagerForNode(browser, id)`, else `ShowBookmarkManager` |
| Setting | four of 18's five upstream files (`settings_strings.grdp`, `settings_localized_strings_provider.cc`, `prefs_util.cc` as `kNumber`, `appearance_page.html.ts`); the options array inline in the `.html.ts` to stay out of `appearance_page.ts` -- **not yet compiled** |
| Import day | with a setting other than Never, a Today tab already past the deadline goes straight to `Archive > <workspace>` and never becomes a tab. By (`timeLastActiveAt`, else `createdAt`), of 456 Today tabs only 9 are under 12 h, 28 under 24 h, 118 under 7 d; all are under 30 d. OWNER |

**Hook budget.** Import: **0** new upstream files (one string file already ours). Close-reset: 5, all
ours. Auto-archive: 4 + the string file, all ours (18). **Nothing in E14 touches an upstream file our
patches do not already touch.** *Corrected 2026-09-24:* E14c.1's `37` added one clean file (41); E14c.2's `38`
none (a first version's `browser_tab_restorer.cc` was removed again, LOCAL.md 42). And "Close group asks
above 25" below was **not built**: a group close is one Recently Closed entry that reopens whole (LOCAL.md 42).

**Split.** **E14a** `34-anchor-close-reset`. **E14b** `35-arc-parser` (`:arc_import` + tests, no UI; port
`import-arc.py --selftest`'s fixture, add the Little-Arc-first case). **E14c** `36-arc-import` (importer,
rail entry, the group-observer fix, the startup-pref check, **and the owner's "Close group asks above
25 tabs"** -- moved here from E14a, 38) **and the scale gate**. **E14d**
`37-auto-archive`. **E14e** backups (Arc data 2.9 GB, official profile 2.5 GB; both browsers closed),
then the real import -- the owner's call.

### E15 spec -- Arc folders: a pinned section of data, not tabs; decided with the owner 2026-09-24

**Why.** Every imported Arc folder became a tab group of real, sleeping tabs (E14c): 3,183 of them.
Every one costs a `TabView` and a `WebContents`, so the cold start is ~2 minutes (41), the close ~3
(41), and reopening one 1,159-tab group froze the window for 7-8 minutes and took ~15 to answer (42) --
and came back without workspace, anchors or names, because Chromium reopens a saved group from its
saved-group model. Arc, on the same data (read from its own files, LOCAL.md 42), keeps ~23 live tabs of
~3,800 items: a window holds no tabs, an item lives in one place, and nothing loads until opened.
The owner: *"put all these into a Folder as they are supposed to be, and never load it when we are not
opening it."*

**Decided with the owner (2026-09-24, one question at a time, all answered):**

| Question | Decision |
|---|---|
| scope of the first design | the store + the importer writing it, the section on screen, Arc-style open/close -- **plus full drag and New folder / Rename**. Later stages: moving items between workspaces, search, auto-archive into folders, re-import into folders (*done in route C2, patch 98: one "New from Arc" folder per re-run, LOCAL.md 128*) |
| where items are kept | **the fork's own file** per profile, not bookmarks |
| an opened item | **lives in its row**, like Arc -- not again in the tab list |
| placement | **between favorites and today's tabs**, scrolling with today's tabs, a divider between |
| drag | **full Arc drag at once**: pin (tab -> section), unpin (item -> tab list), reorder, into / out of nested folders; "it also works like anchor" |
| approach | **A: items are data; an open item is a real tab, hidden from the list and drawn as its row.** B (items as never-loaded pinned tabs) rejected: still a tab each, so nothing gets faster |
| from Arc's practice | **a last-used time on every item**, and the **"back to pinned address" arrow** on an open item that drifted. Recorded for later: the Archive (redesigns E14d), per-window folder state, one search for everything, a light window for outside links |

**Terms.** *Favorites* = Chromium pinned tabs, unchanged (top, all workspaces, as E14c imports Arc's).
*Pinned section* = per workspace, folders and items. *Today* = the normal tab list below it.

**Store** (E15a). A tree per workspace guid: a **folder** `{id, title, open, children}` whose children are
folders or items, nesting as deep as Arc's (the E14b "A > B" flattening existed only because tab groups
cannot nest); an **item** `{id, url, title, custom_title, last_active}`. `url` is the item's saved
address -- its anchor. Pure data with its JSON form in a leaf target (`:pins`, `//base` only), unit-tested
like `:arc_import`. The live object is **one per profile**, shared by every window: a file in the profile
directory, loaded off the UI thread, written through `base::ImportantFileWriter` (never a half-written
file). A file that fails to parse is kept aside (`.bad`) before anything writes over it. An item whose
workspace was deleted follows 2.4's orphan rule and shows under the default workspace. *Why a file,
against 2.6:* 2.6 rejected a file because it had to be keyed by tab session ids, which are new on every
restart; an item is not a tab and has its own stable id. The link from an OPEN item's tab back to its
item still travels 2.6's way, in the tab's extra data (key `helium.pin_item`, through E8's door).
**Answered (LOCAL.md 43): `Profile` user data, created on first use -- no hook.** A `KeyedService` would
need its factory in `chrome_browser_main_extra_parts_profiles.cc`, which three Helium/ungoogled patches
already edit (a late factory is `DCHECK(false)`, `dependency_manager.cc:70-80`). The whole store, file
included, is `//base` only: it takes the profile directory, attaches through `base::SupportsUserData`
(what `Profile` is), writes on its own `BLOCK_SHUTDOWN` sequence after a 2.5 s delay, and **flushes
pending changes in its destructor** -- `BookmarkStorage`'s pattern (`bookmark_storage.cc:182-206, 321`);
`ImportantFileWriter` DCHECKs a missed flush (`important_file_writer.cc:441`). Profiles are destroyed in
`StartTearDown` (`browser_process_impl.cc:663`), before the thread pool stops. Windows log-off
(`EndSession`, :853) commits prefs only, so up to 2.5 s of changes can be lost there -- bookmarks have
the same gap.

**The section on screen** (E15b). `WorkspacePinnedSectionView`, fork-owned, placed in `TabStripView`'s
unpinned scroll area above `UnpinnedTabContainerView`. **Answered (LOCAL.md 43):** one hunk in
`TabStripView::AddScrollViewContents()` (`tab_strip_view.cc:495-501`): when the unpinned container
arrives, ask our `TabStripCollectionController` for a header; if one comes back, the scroll view's
contents becomes a plain vertical box `[section, container]`. The rest of the file already walks up to
`scroll_view->contents()`, so scrolling to a tab, hit tests and link drops keep working unchanged.
Helium's hunks in this file sit ~300 lines away (the removed separator). **Corrected at E15b (LOCAL.md 45):**
the section lives beside the rail -- header in the `vertical` target, source in `vertical:impl` --
because `common:impl` already depends on the `vertical` HEADER target (that is how it builds
`VerticalTabStripScrollBar`); the research's "a target of its own" was wrong. And the box is not free:
the scroll view layers the box, so the section builds its rows off the widget (every add under a layered
ancestor walks all its rows and tabs) and caches its height. `vertical_tab_strip_region_view.cc` is
avoided: three Helium patches edit it. Folder rows (icon, name, open/closed
arrow; a left click toggles) and item rows (icon, custom name else title, an X on hover while open),
indented per level; light `views::Button`s, no layers. A closed folder creates no rows for its children.
Three item states: sleeping, open, active. Only the active workspace's tree; switching swaps it.
Hidden while the strip is collapsed. Icons: Chromium's favicon cache for the URL, else a globe. A tree
for accessibility (up/down, Enter, left/right).

**Open and close** (E15c). A click on a sleeping item opens ONE real tab in this window, tagged, anchored
at the item's `url` and linked -- all **before** the insert, as E14c tags imported tabs -- and 02's filter
hides it from the list; the row is its face. **Answered (LOCAL.md 43):** the importer's own road,
`chrome::AddRestoredTab(..., select=true, ..., extra_data, ..., kLoadIfVisible)`: 08's hook puts the tag,
anchor and `helium.pin_item` on the contents before the insert (`browser_tabrestore.cc:99`) and
`TabRestored()` persists them. The tab's one history entry is the item's address. The section sits below
`ui:ui`, so it asks through a new default-false `TabStripModelDelegate` virtual (E14a's pattern, files
already ours). **Hiding the active tab:** only the *list* asks the new question. 02's filter
(`IsTabVisibleForWorkspace`) and the command predicate `IsTabVisibleInActiveWorkspace` (Ctrl+Tab and
Ctrl+1..9) add "and not linked". `IsTabVisible` / `IsTabOnScreen` stay as they are: the tab is in its
workspace, so activating it neither switches the workspace nor triggers `EnsureActiveTabVisible`. Close
others / right / left already skip it as an anchor. On Chromium's side, `TabStripView::OnTabChanged`
scrolls the list to the active tab's view (`tab_strip_view.cc:325`), and a hidden one sits in a zero-height
slot (`unpinned_tab_container_view_layout.cc:237-246`). So a guard for an undrawn view goes in
the same upstream file, and the section scrolls its own row into view. `MoveTabsToWorkspace` must skip
linked tabs (a shift-click range, E13).
A click on an open item activates it; an item open in another window brings that window forward (one
place). **X on the row, or Ctrl+W on its page, closes the page for real** (`CLOSE_NONE`: no Recently
Closed entry, nothing was lost), through 34's doors: for a linked tab the reset becomes a close. A page
with unsaved work gets Chromium's own "Leave site?" (a real close runs it). Links inside work; a TYPED
address opens a new tab (E10b); no back-to-opener (33). The **reset arrow** shows while the page has left
the item's address (`HasDriftedFrom`); one click navigates back. `last_active` is stamped when the item's
page is shown. A window close closes only open items' pages. A restart restores their tabs as session
tabs, re-linked by extra data; a tab whose item is gone becomes an ordinary visible tab -- never a lost page.
Menus: item -- Unpin (becomes a Today tab, opened if asleep; the item goes), Delete, Rename; folder --
Rename, New folder, Delete (asks when it holds items). The tab menu's Anchor submenu becomes **Pin to
workspace**; tabs anchored in old profiles keep working as today. With Workspaces off the section hides
and open items' pages show as ordinary tabs (E10b's dormancy); the store is untouched.

**Drag** (E15d). **Pin:** the section is a `TabDragTarget`, returned by `BaseTabStripRegionView::
GetTabDragTarget` when the point is inside it (one hook, a clean upstream file); `HandleTabDrop` links the
dropped tab(s) to new items at the drop slot -- between rows or into a folder -- and they stay open.
Several selected tabs pin in order; a tab group is refused (`CanDropTab`). **Unpin, reorder, into / out of
folders:** the section's own drag. **Answered (LOCAL.md 43): our own index, no hook.** Chromium's link
drop is an OS drag. Its source only learns that the drag ended (`View::OnDragDone()`, no result), so the
item could not be deleted, and the drop always `Navigate()`s a new tab, which would load a second copy of
an open item (`browser_root_view.cc:606-690`). Instead, the section's mouse drag asks the public
`UnpinnedTabContainerView::GetLinkDropIndex(point)`. Its bottom-edge test already steps over 02's
zero-height hidden rows (`unpinned_tab_container_view.cc:153`). A sleeping item opens there. An open
item is unlinked and moved there, joining the group if the index says so. The section draws its own
insertion line (`SetLinkDropArrow` is protected).

**The importer** (E15b). E14c's "Import from Arc..." writes each space's pinned container into the store
(nested folders, loose items, custom names, `last_active` from `timeLastActiveAt`); favorites stay pinned
tabs, Today stays tabs. Nothing opens. Only `testprofile` holds the old groups: it is re-imported; the
owner's real import (E14e) arrives in the new shape.

**Not in E15** (recorded, each a later stage): moving items between workspaces; one search for tabs,
items and archive (Arc's command bar); the **Archive** -- every close and auto-archive kept per workspace
in the store, searchable and restorable with its workspace (would redesign E14d away from bookmarks);
per-window folder state (Arc keeps `expandedItems` per window); a light window for links from other apps
(Little Arc); Arc-style Ctrl+Tab over open items (*done in C2, `63-ctrl-tab`*); an icon
view in the collapsed strip; drawing only the visible rows of a huge open folder.

**Done means** (on `testprofile`, re-imported): cold start with Canary active **<= 10 s** (was 119);
browser close **<= 10 s** (was ~3 min); the 1,159-item folder shows its rows in about a second and loads
nothing; every item survives closing pages, windows and a restart; **0 markers**, Default and Dcheck.

**Hook budget (after research).** New upstream files: **`tab_strip_view.cc`** (Helium's too; two hunks,
the mount and the scroll guard) and `base_tab_strip_region_view.cc` (clean, E15d's pin target). **None**
for the store, the unpin landing or the section's constructor. Ours already: 02's filter and controller,
05/34's delegate and predicate, 08's door (a new key), 14/21's tab menu, 34's close doors, 36's importer,
`common/BUILD.gn`, `vertical/BUILD.gn`.

**Research E15 -- answered 2026-09-24, read-only, evidence in LOCAL.md 43:**

| # | Question | Answer |
|---|---|---|
| 1 | the store's owner, and the shutdown flush | `Profile` user data, `//base` only, flushed in its destructor on a `BLOCK_SHUTDOWN` sequence (Store above) |
| 2 | the section's mount | one hunk in `TabStripView::AddScrollViewContents`, a header supplied by our controller (Section above) |
| 3 | tag, anchor and link a new tab before its insert | `AddRestoredTab` with `extra_data`, `select=true`, `kLoadIfVisible`, through a delegate virtual (Open above) |
| 4 | hiding the active tab | only the list and the Ctrl+Tab / Ctrl+1..9 predicate ask "linked?"; a scroll guard in `tab_strip_view.cc`; `MoveTabsToWorkspace` skips linked tabs (Open above) |
| 5 | the unpin landing | our own drag + `GetLinkDropIndex`, no hook; Chromium's link drop cannot tell the source where it landed (Drag above) |
| 6 | icons for never-visited items | `FaviconService::GetRawFaviconForPageURL(url, ..., fallback_to_host=true)` per drawn row, a globe otherwise. The Recently Closed menu looks up pages without a tab the same way, by exact address only (`recent_tabs_sub_menu_model.cc:1035-1042`). `testprofile`'s icon database is 114 KB (globes until opened); the owner's real Helium profile's is 7.5 MB. Arc keeps its own PNG per item, named MD5(item id), for only **693 of 3,915** items: not worth importing |
| 7 | GN, no cycle | `:pins` = `//base` (+ `//base/test:test_support` in the tests). The section's target may depend on `//chrome/browser/favicon` (the header target, which `common:impl` already reaches) and `//chrome/browser/profiles:profile`, **never `//chrome/browser/favicon:impl`**: that one depends on `ui:ui`, which depends on `vertical:impl` and `common:impl` -- a cycle. Proven with `gn path` (read the arrows: it answers in either direction) |

**Split** (one session and one commit each; E15 runs **before** E14d, by the owner's order).
**E15 research** -- the seven answers above, written back into this spec.
**E15a** the store (`:pins` + tests; no UI). **E15b** the section, read-only, + the importer + the scale
gate. **E15c** open / close + menus + the reset arrow. **E15d** drag + New folder / Rename. Then E14d, E14e.

### E14d spec -- Arc's archive: every close kept per workspace, with an Archive screen; decided with the owner 2026-09-27

**Why.** E14d was auto-archive into bookmarks. On 2026-09-27 the owner chose Arc's own model instead: every
close, by hand and automatic, kept per workspace in a file of our own, with a screen to find and restore from.
The E14 spec's "Auto-archive" table keeps its rules for E14d.3 (the clock, the never-archived list, the sweep's
limits, the setting's values); its record (bookmarks) and its Recently Closed batch rule are void. Read by hand,
no agents, no build (LOCAL.md 51): Arc's archive file, counts only, and the close paths of the patched .52 tree.

**Arc's archive, read from the owner's file** (`StorableArchiveItems.json`, 1.9 MB, `version` 1).

| What | Found |
|---|---|
| shape | one list `[id, entry, id, entry, ...]`; an entry is `{archivedAt, reason, source: {space: {_0: <space id>}}, sidebarItem}`, and `sidebarItem` is the tab's own sidebar item (`savedURL`, `savedTitle`, `createdAt`, `timeLastActiveAt` on 1,571 of 1,757) |
| what is archived | **tabs only**: 1,757 of 1,757 are `tab` items, none has a `parentID` or children. A pinned item or a folder is never archived |
| reasons | 1,300 `manual`, 457 `auto`. A manual close is of the tab in front (median 0 h since last shown); every auto one is >= 720 h since last shown (30 days), 158 of them counted from `createdAt` |
| sources | 1,747 a space (1,406 / 297 / 44 / 9 / 1 per space), 9 Little Arc, 1 unknown |
| retention | **60 days**: the oldest entry is 59.76 days older than the file; 61 calendar days of closes |
| duplicates | kept: 1,720 distinct addresses, 32 repeated, at most 5 times |
| the sweep | gradual: at most 7 auto entries in any one minute |
| order | in no date order; the screen sorts |

**Which closes are archived.** Every close the user makes reaches `TabStripModel`'s one call to the delegate's
`CreateHistoricalTab` (`tab_strip_model.cc:1080-1083`, taken when the close carries
`CLOSE_CREATE_HISTORICAL_TAB`, `:4265-4269`) -- Recently Closed's own door, `browser_tab_strip_model_delegate.cc:230`,
**a file already ours** (05, 34; it reaches `WorkspaceService::From(browser_)` as 34 does). The record is made
there, before Chromium's entry: **zero new upstream files**. A page with a "Leave site?" listener reaches the
door only when it really closes (`:4259-4263` defers it, keeping its close types, `browser_tabstrip.cc:131-139`).

| Close | Archived | Read at |
|---|---|---|
| X, middle-click, Ctrl+W, the tab menu's Close / Close others / below, Close group, a selection, tab search's X, a page closing itself | yes, `manual`. *E14d.1:* the tab menu's Close only since 47 backports Chromium main's fix -- at .52 it called `ExecuteCloseTabs(..., true)`, and `true` as close types is `CLOSE_USER_GESTURE` alone: no Recently Closed, no archive | context-menu closes `tab_strip_model.cc:3520`; `chrome::CloseWebContents(..., add_to_history)` `browser_tabstrip.cc:137-139` |
| the rail's Close all tabs, Delete workspace | yes, `manual`; a deleted workspace's entries show under Home (2.4's orphan rule) | `10-editing.patch:474`, `23-icon-unload-close.patch:192, 267` |
| **a window closed while another window of the profile stays open** | **yes, `window`** (the owner): its tabs leave the session for good. *E14d.1:* only a COMMITTED close (`IsAttemptingToCloseBrowser()` and `closing_all()`), and "another window" is any normal or popup window whose own close has not committed -- the session's `HasOpenTrackableBrowsers` | `session_service.cc:436-446`: with other tabbed windows open the close is committed |
| the last window, Exit, log-off | no: the session keeps them and they come back | `session_service.cc:446` (a pending close); Exit destroys the session service first (`:439-440`). *Corrected in E14d.1 (LOCAL.md 52):* NOT `IsTryingToQuit()` -- the app menu's Exit (`AttemptUserExit`) never sets it; the rule asks whether the session service still exists, and `HasShutdownStarted()` for log-off and a silent exit |
| the X / Ctrl+W on a pinned page (E15c) | no: the item stays in the section | `41-pinned-open-close.patch:422-424` (`CLOSE_USER_GESTURE` alone). *E14d.1:* a page with an unload-type handler, a window close and the rail's Close all tabs DO reach the door, so the door itself refuses a pinned item's page |
| the X on an anchored tab (34) | no: a reset, not a close | 34 |
| a drag to another window, Move to new window | no: a detach never takes the door | `tab_strip_model.cc:649-651` (`create_historical_tab=false`) |
| Helium's back-to-opener close, Unload, a discard, a crash | no, as Recently Closed | -- |
| incognito | no: it has no `WorkspaceService`, and `BrowserSupportsHistoricalEntries()` is false | `browser_tab_strip_model_delegate.cc:676-680` |
| the auto-archive sweep (E14d.3) | yes, `auto`, recorded by the sweep before its close | -- |
| a favorite (a Chromium-pinned tab, E14c's import of Arc's favorites) | no (*E14d.2*, defaulted: Arc never archives one); Recently Closed keeps the close | `workspace_service.cc` `ArchiveClosingTab` |
| a tab with no address to go back to (an untouched New Tab page) | no | -- |

A window close reaches the door too: `UnloadController` calls `CloseAllTabs()` (`unload_controller.cc:183-186`),
which closes with `CLOSE_CREATE_HISTORICAL_TAB` (`tab_strip_model.cc:1410-1425`), after
`TabRestoreService::BrowserClosing` (`unload_controller.cc:177-180`), whose helper then drops the per-tab entries
(`tab_restore_service_helper.cc:264-270`). So the door must tell a window close from a user close. `closing_all()`
cannot: a Close group of the WHOLE strip sets it too (`tab_strip_model.cc:1453-1456`). The test is the window's
own `UnloadController::is_attempting_to_close_browser()` (`unload_controller.h:143`), then the session's rule
above: another normal window of this profile open and not quitting -> `window`, else nothing. E14d.1 proves each
row of the table with a log line.

**The record.** One list per profile; an entry is `{id, url, title, custom_title?, workspace, reason (manual |
window | auto), archived_at, last_active}`. The url is the last committed one: a sleeping restored tab has it
(`NavigationControllerImpl::FinishRestore` sets the committed index, `navigation_controller_impl.cc:5160-5172`),
so a never-loaded import is archived at its address. No back/forward history (Arc keeps none); duplicates kept
(Arc). **Kept 60 days** (the owner: Arc's number), pruned at load and before each write.

**The store** (E14d.1). `ArchiveStore`, on `PinStore`'s pattern (39): `Profile` user data, `//base` only, a file
of its own (`Workspace Archive`) in the profile directory, `ImportantFileWriter` on a `BLOCK_SHUTDOWN` sequence
after 2.5 s, the destructor's flush, a bad file kept as `.bad`, a newer or unreadable one read-only. Compact JSON:
at Arc's rate ~0.5 MB. **Its own file, not a key in the pins file**: the pins file is 1.2 MB on `testprofile`,
which a close must not rewrite, and a bad archive must not take the pins with it. `PinStore`'s read-and-move-aside
half (~40 lines) is shared, not copied; the writer and the flush are a few lines each. A new leaf target
`:archive`, tested in `workspaces_unittests`.

*Corrected in E14d.1 (LOCAL.md 52):* the id is minted by whichever asks first -- the door, or Recently Closed's capture, which a window close, Close group and a split close run BEFORE their tabs reach the door; it is added at `BrowserLiveTabContext::GetExtraDataForTab` only, never by `PopulateWorkspaceExtraData` (patch 21 rebuilds the session file from that map); and it is removed at `BrowserLiveTabContext::AddRestoredTab` / `ReplaceRestoredTab`, not in 08's `RestoreWorkspaceFromExtraData`, which a saved group's reopen never reaches. The paragraph below is the plan as written.

**Ctrl+Shift+T** stays Chromium's. *Defaulted, the owner's to overturn:* reopening an archived close removes its
entry, so an item lives in one place, as in Arc. Zero new hooks: the door writes `helium.archive_id` on the tab
before Chromium's entry is made; 08's `PopulateWorkspaceExtraData` carries it into the Recently Closed entry
(`browser_live_tab_context.cc:171-178`, ours) and 08's `RestoreWorkspaceFromExtraData` (`browser_tabrestore.cc:92-99`,
ours) sees it at the reopen and removes the entry. A reopened window does the same for each of its tabs.

**Restore** (E14d.2; the owner). The window switches to the entry's workspace (Home for a deleted one) and the page
opens at the top of Today (E15c.1's place), selected and loaded, with its custom name; the entry leaves the archive.
By the road a pinned item opens (E15c: `AddRestoredTab`, the tag in the extra data before the insert).

**Deleting browsing history leaves the archive alone** (the owner, 2026-09-27, after E14d.1's critic found Chromium clears Recently Closed and the spec had not decided): the archive is deleted from its own controls, independently -- **Clear all** on the Archive screen (E14d.2, with a confirm) and **time ranges** in its setting (E14d.3: Last hour / Last 24 hours / Last 7 days / All time, like Chrome's Clear browsing data). One store call serves both: remove the entries archived at or after a time. *Moved by the owner at E14d.3's start (2026-09-28): the ranges are on the Archive screen -- "Clear..." replaces Clear all and opens the four ranges, each with the screen's confirm -- so no WebUI handler and no new upstream file (LOCAL.md 54).*

**The Archive screen** (E14d.2). Opened from the rail's `+` menu, "Archive". **Arc-style rows grouped by day**
(Today, Yesterday, then dates), each an icon (the pinned section's favicon lookup, a globe otherwise) and a name,
newest first, **with a search box filtering the rows** (the owner: "Arc-style rows by day, but searchable in the
list"). A click restores; a row's menu has Restore and Delete. The active workspace's entries; whether a switch
shows every workspace is asked at E14d.2's start. Rows are built off the widget and attached once (E15b: an add
under a layered ancestor walks the whole subtree). **Gate:** 1,750 entries (Arc's archive, or a generated file)
open in <= 1 s and a keystroke filters in well under that; if not, draw the newest N and grow on scroll, marked
`ponytail:`. Rejected by the owner: `views::TableView` (Task Manager's list; draws only the visible rows,
`ui/views/controls/table/table_view.h:121, 481`). The host -- a bubble on the rail's `+`, or browser-modal like
25's rename box -- is whichever compiles without a GN cycle, decided at E14d.2.

*Decided and built in E14d.2 (LOCAL.md 53):* a **bubble on the rail's `+`** (the owner), a `views::View` hosted as the one custom field of a `DialogModel` in `BubbleDialogModelHost` -- `BubbleDialogDelegateView`'s constructors are friend-list-only at M153; **"All workspaces" is a switch, off at every open** (the owner), each row then led by its workspace's rail mark; the search is every word in any field, case-folded (the owner kept the default); the list only grows while open, so the search box never moves. A restore also **takes its Recently Closed tab away, saved** (`DeleteNavigationEntries`, matched by that tab's navigation, so one tab leaves a closed window or group alone; a split's tab inside one is kept), so Ctrl+Shift+T never opens the page twice -- the other half of the Ctrl+Shift+T rule above. **Clear all empties every workspace** (defaulted). The gate held: 1,750 entries open in 510 ms, a keystroke filters in 22 ms, rows built off the widget.

**Auto-archive** (E14d.3). The old table's rules with three changes: the record is this archive (`auto`), never a
bookmark; **every auto close is `CLOSE_NONE`** (the archive holds them, so Recently Closed keeps only the user's own
closes); "close only when the store took the entry" replaces "only if `AddURL` returned a node". The never-archived
list gains the pinned pages (linked tabs, E15c), which are anchored and so already skipped. The setting's default
(the old table: Never) and the import-day rule are asked at E14d.3's start. *Decided by the owner, 2026-09-28:* the choices are **1 day, 7 days, 30 days, Never** (the old table's 12 hours dropped; minutes 1440 / 10080 / 43200 / 0), the default stays **Never** (the old table's owner decision; not re-asked, the owner may overturn); and **an imported tab's clock starts on the day it was imported**, not at its Arc last use -- nothing imported is archived before the chosen time has passed since the import. *Built in E14d.3 (LOCAL.md 54):* the never-list grew in review -- a tab in a group (the last tab of a saved group deletes the group), an address a restore cannot open (only http, https, file and chrome pages are swept, never an untouched New Tab page), audible within the last minute, camera / mic / window / display capture and mirroring, a USB / Bluetooth / HID / serial device (performance_manager's `PageLiveStateDecorator`); the clock is the later of last shown and left (`left_at`, carried across a discard), floored at the last Arc import, which also covers tabs imported before 49; the sweep skips while the archive file is not loaded or read-only, during a drag, a window close or an Exit; an unload-deferred close comes back through the door marked and is neither archived twice nor kept in Recently Closed; the timer sweeps every min(5 min, setting / 2), at least every 30 s.

**With Workspaces off** nothing is recorded and the rail (the screen's door) is hidden; the file is untouched
(E10b's dormancy).

**Hook budget.** E14d.1 (landed: 0 new upstream files -- hunks in `browser_tab_strip_model_delegate.cc` and `browser_live_tab_context.cc`, both already on the list of 54). Planned: 0 new upstream files (a hunk in `browser_tab_strip_model_delegate.cc` and 08's files, all
ours). E14d.2: 0 (the rail; strings in `generated_resources.grd`, ours). E14d.3: the old table's four settings
files, all ours (18). *Landed:* those four, `generated_resources.grd` and the delegate's door, all ours: no new upstream file (54).

**Split** -- each sized to one session's context (about 1M tokens), one patch and one commit. The auto-archive
comes last on purpose: a tab closed by a timer is safe only once it can be found again.

| Chunk | Patch | Scope | Checkpoint |
|---|---|---|---|
| **E14d.1** | `47-archive` | `:archive` (entry, JSON, store, the 60-day prune, the shared read); the record at the delegate's door with the window rule; `helium.archive_id` through 08 | unit tests (flush on destroy, `.bad`, prune, newer version read-only, refusals); a hands-free script closes a tab each way in the table and reads the file, every row graded; Dcheck launched, 0 markers |
| **E14d.2** | `48-archive-screen` | the screen, search, restore, delete, **Clear all** (confirm), the rail's entry | owner-observed and MSAA hands-free; the 1,750-entry timing; Dcheck launched (new views), 0 markers |
| **E14d.3** | `49-auto-archive` | the sweep, the setting with its **delete by time range**, the import-day rule (**the clock starts at the import**, the owner) | a 2-minute setting watched in the log; the never-list (audible, "Leave site?", anchored, pinned page, active); owner-observed; Dcheck |

Then **E14e**: backups, the real import, and optionally Arc's own 1,757 entries into the archive (a second parser
beside `:arc_import`'s; all are under 60 days old).

### E17 spec -- the fork's UI redesigned: native to Helium, with Arc's feel (direction B); decided with the owner 2026-10-02

**Why.** Asked by the owner after R5, before the installer and switch day. A screenshot review of today's UI (demo data,
`local/capture-ui.ps1 -Tag before`, light and dark, in `<local-path>\Helium-workspace\ui-shots\before*`) found eight problems: the
rail floats under the last tab instead of sitting at the bottom; its controls are tiny and faint (8 px glyph arrows, a
letter "H" beside emoji); "which workspace am I in" is one grey square; pinned vs Today barely separates ("+ New Tab" is
`#686969` on `#1e2020`); folders have no open/closed arrow; the Archive is a stock bubble with long dates and a big Clear;
the workspace menu is ten items; collapsed, the pinned pages vanish.

**The visual source of truth is the canvas** -- a private claude.ai artifact (its link is kept outside the repo):
today's screenshots, the three directions (A quiet / **B Arc-flavoured, chosen** / C Arc layout), the folder-colour and
Archive-icon options, and the final boards (Archive screen, menus and the workspace editor, collapsed sidebar). Where this
text and a board disagree, this text wins and the board is fixed.

**Decided with the owner (2026-10-02), one question each.**

| Question | Answer |
|---|---|
| Yardstick | native to Helium (its greys, 8 px radii, Segoe UI 12 px, Chromium's own icons), with Arc's feel |
| Scope | all of it: the rail, pinned + New Tab, the Archive, the menus, the collapsed sidebar |
| Colour | **a colour per workspace, on our own parts only** -- Helium's strip is never tinted (the 2026-09-19 rule stands: the strip follows Helium) |
| Direction | **B**: a workspace header at the top, pinned pages on a soft card, Arc's bottom bar (Archive left, workspaces centre, + right) |
| Identity | Chromium's 9 tab-group colours; presets as Chromium's line icons drawn in that colour; emoji still via "Custom" |
| Inactive chips | in their **own** colour, dimmed (not grey) |
| Top area | as drawn; the header scrolls with the list |
| Folders | a **solid** folder, **each folder its own colour**, default the workspace's |
| Archive | as drawn, a bubble from its own button; icon: **our own "tabs put away"** (not Arc's box) |
| Menus | Chromium's native menus, **with icons**; Rename and the icon/colour picker **merged into "Edit workspace…"**, a bubble (native menus cannot show swatches) |

**Tokens.** Every colour comes from the `ColorProvider` at paint time (never a hex in code), so light, dark and Helium's
own themes all follow. The hexes are what the owner's builds draw today, measured from the screenshots, and are what a
paint must reproduce.

| Token | Source | Dark / light today |
|---|---|---|
| sidebar background | the strip's own (unchanged) | `#1e2020` / `#ffffff` |
| text | tab foreground, active frame | ~`#e3e3e3` / `#1a1c1c` |
| selected row | tab background, active | `#343636` / `#ededed`, 8 px radius, 188 x 30 at 208 px wide |
| workspace colour *c* | `GetTabGroupTabStripColorId(c, active)` (`tab_group_theme.h`) | e.g. blue `#8ab4f8` / `#1a73e8` |
| active chip fill | *c* at alpha 0x33 dark, 0x22 light | |
| inactive chip icon | *c* at alpha 0xB8 | |
| pinned card | text colour at alpha 0x0B dark, 0x09 light | |
| hairline | the strip's separator colour | `#3c4043` / `#e3e3e3` |
| menus, bubbles | native | `#1a1c1c` / `#ffffff` |

Sizes: rows 30 px, favicons 16 px, title 12 px, chips 28 x 28 with 16 px icons, radii 8 px (rows, chips, card), the bubble
12 px, folder chevrons 12 px, header 34 px.

**1. Identity -- data.** Each workspace in `helium.workspaces.list` gains two optional keys:

| Key | Value | Absent / bad |
|---|---|---|
| `color` | an int, `tab_groups::TabGroupColorId` 0-8 (grey, blue, red, yellow, green, pink, purple, cyan, orange) | grey for Home; for others the first id 1-8 no other workspace holds, then grey. A bad value is ignored, never a refused list |
| `symbol` | one of 12 preset names: `home work study play shopping music code travel flight launch star pets` -> Chromium's own icons (checked at 154.0.8037.92, 2026-10-02): `vector_icons::` (components) `kHomeIcon`, `kWorkIcon`, `kScienceIcon`, `kVideogameAssetIcon`, `kShoppingBagIcon`, `kCodeIcon`, `kFlightIcon`, `kPetsIcon`; chrome/app's `kQueueMusicIcon`, `kTravelExploreIcon`, `kRocketLaunchIcon`, `kStarIcon` | Home: `home`. Otherwise the existing `icon` (emoji) draws, else the title's first letter |

`symbol` beats `icon`; choosing a preset clears `icon`, choosing "Custom emoji…" clears `symbol`. **Existing emoji are
kept as they are** -- nothing is migrated; old builds ignore both keys. A preset is drawn in the workspace's colour; an
emoji keeps its own colours.

**2. The bottom bar** (today's rail, `workspace_rail_view.*` and its line in `vertical_tab_strip_bottom_container.cc`).
- **Anchored at the bottom**: Helium's bottom container is flex `kPreferred..kUnbounded` and fills everything below the
  tab list; the rail is set to its end (`kCrossAxisAlignmentKey` / main-axis end when collapsed), one property in our own
  hunk. A hairline above it.
- **Left to right**: the **Archive** button (our "tabs put away" icon, tooltip "Archive"), the **chips** in their
  scroller, the **+** button. Archive leaves the + menu.
- **Chips**: 28 x 28, radius 8, a 16 px preset in the workspace colour (inactive at 0xB8) or its emoji; the current one
  filled with its colour at 0x33/0x22; hover = Helium's row hover; tooltip = the name. The letter "H" for Home is gone.
- **Arrows** (chrome/app's `kChevronRightIcon`, 14 px; the left one is the same icon rotated 180 -- there is no `chevron_left` at 154) only when the chips overflow; the wheel still slides them.
- **Collapsed**: a column at the bottom -- Archive, the chips, +.
- **Unchanged**: shortcuts, the context menus' commands, reorder (relabelled "Move left" / "Move right").

**3. The top of the sidebar** (`workspace_pinned_section_view.*`).
- **Header**, 34 px, the section's first child: the symbol (or emoji/letter) in the colour + the name, 12 px semibold;
  right-click opens the workspace menu. It scrolls with the list. Hidden with the section when Workspaces is off.
- **Pinned card**: the rows inside one rounded background (radius 8, 8 px side margins, 4 px vertical padding). No pinned
  rows: no card -- it appears only as the drop target during a tab drag, as today.
- **Folders**: a 12 px chevron (`vector_icons::kKeyboardArrowDownIcon` open, chrome/app's `kKeyboardArrowRightIcon` closed) before a **solid** folder (`vector_icons::kFolderFilledIcon`) in the folder's
  colour. The pins file gains an optional folder key `color` (0-8); absent = the workspace's colour; a bad value is
  ignored (the loader reads by key and never refuses a row for it -- `NodeFromValue`, checked 2026-10-02).
- **A pinned page with its tab showing**: the selected-row look, radius 8 (today 6, `kActiveRowRadius`).
- **"+ New Tab"**: the first row of Today at full text contrast, its + at icon colour; the divider line under the section
  is removed (the card's edge separates).
- Today's tabs: Helium's, untouched.

**4. The Archive screen** (`workspace_archive_view.*`).
- Anchored to the bottom bar's Archive button, rising above it; 360 px; radius 12.
- **Header** 48 px: "Archive" 14 px semibold; a **⋯** menu holding Clear… and its time ranges (the Clear button goes);
  close **×**.
- **Search** field (search icon, 34 px, radius 8); under it a two-part switch **This workspace | All workspaces**
  (replaces the checkbox; it starts and is remembered exactly as the checkbox does today).
- **Group headings**: Today, Yesterday, Earlier this week, Last week, then month names ("September 2026").
- **Rows** 30 px: favicon, title, time on the right in secondary text -- `2:14 PM` today and yesterday, the weekday
  earlier this week, `Sep 25` otherwise. In All mode a 7 px dot in the source workspace's colour before the time.
- **Empty**: "Nothing archived yet" and "Tabs you close stay here for 60 days."
- Restore / Delete on right-click, search behaviour, keyboard: unchanged.
- **The icon**: our own vector icon `tabs_put_away.icon` (two tab lines over a tray with a down arrow), in a new
  `aggregate_vector_icons` target in our directory.

**5. Menus** -- native, each item with a 16 px Chromium icon.
- **Workspace menu**: Move tab here (`kMoveGroupIcon`; other workspaces only) · — · **Edit workspace…**
  (`vector_icons::kEditIcon`) · Move left (`vector_icons::kArrowBackIcon`) · Move right (`vector_icons::kArrowForwardIcon`) · — ·
  Unload workspace (`vector_icons::kPauseIcon`) · Unload other workspaces (the same) · Close all tabs (`kTabCloseIcon`) · — ·
  Delete workspace… (`kDeleteIcon`). Unmarked names are chrome/app's.
- **"Edit workspace…"** opens a bubble (300 px): Name (text field, replaces the inline rename) · Colour (the 9 swatches as
  24 px circles, the current one ringed; Chromium's tab-group `ColorPickerView` is reused when its API takes our colour list,
  else drawn by us -- the look is the same either way) · Icon (the 12
  presets, a 6-column grid, the current one filled with the colour) · "Custom emoji…" (today's custom-icon prompt, 26).
  Changes apply as made; Escape closes.
- **+ menu**: New tab (`kAddIcon`) · New workspace (`kAddCircleIcon`) · Tab search (`vector_icons::kSearchIcon`) · — · Import
  from Arc… (`vector_icons::kDownloadIcon`).
- **Folder menu**: gains **Colour ▸**: the 9 colours, each with its swatch, a tick on the current.

**6. Collapsed sidebar.** The header shows its symbol only; the pinned card stays as a column of top-level icons (an item's
favicon, a folder's solid coloured folder; clicking a folder opens a menu of its pages); Today's favicons as Helium draws
them; the bottom bar as a column.

**7. Zen mode** (asked by the owner on the canvas, 2026-10-02). Zen mode's floating sidebar is the same tab strip,
slid in from the window's edge over the page, so all of B shows there unchanged: header, card, folders, bottom bar,
Archive, menus. Two differences, both Helium's: it floats in Helium's own rounded, shadowed panel, and it never
collapses (E16, `50-floating-resize`), so section 6 does not apply while floating. The bottom bar anchors to the
floating panel's bottom. Verified, not assumed: every chunk's captures add a zen-mode shot (floating, revealed), and
`check-e16-auto.ps1` stays in the suite.

**Implementation facts, verified 2026-10-02 against the patched 154 tree (for the session that writes E17's plan).**

| Fact | What it means for the code |
|---|---|
| Why the rail floats: Helium's region view gives the bottom container flex `kPreferred..kUnbounded` (it fills everything under the tab list), and the container's `UpdateButtonStyles` sets cross-axis `kStart` when expanded | **No line in Helium's file is needed.** The rail sets on itself `views::kCrossAxisAlignmentKey = LayoutAlignment::kEnd` when expanded; when collapsed (the container turns vertical) it takes flex `kPreferred..kUnbounded` on the vertical axis and `SetMainAxisAlignment(kEnd)` for its own children -- all in `workspace_rail_view.cc`'s `OnCollapseStateChanged` |
| `TopContainerButton` (Helium's) is a `LabelButton`, a fixed 32 px square (`kVerticalTabStripCollapseButtonSize`), with Chromium's ink drop; it paints to a non-opaque layer (why `WorkspaceRailButton` turns subpixel AA off, E9c) | the chips stay `WorkspaceRailButton`s: override `CalculatePreferredSize` to 28; the preset via `SetImageModel(ImageModel::FromVectorIcon(icon, SkColor, 16))` for every state; the current chip's fill via `SetBackground(views::CreateRoundedRectBackground(color, 8))`; both recomputed in `OnThemeChanged` |
| a workspace colour | `GetColorProvider()->GetColor(GetTabGroupTabStripColorId(tab_groups::TabGroupColorId(c), active_frame))`, `chrome/browser/ui/tabs/tab_group_theme.h` -- target `//chrome/browser/ui/tabs:tab_group`, already in `views/tabs/vertical:impl`'s deps, as is `//components/tab_groups`. Fill alpha 0x33 on a dark strip, 0x22 on a light one (`color_utils::IsDark` of the strip's background); inactive icon alpha 0xB8 |
| icons | components' set is `vector_icons::k...Icon` from `components/vector_icons/vector_icons.h` (dep already in `:impl`); chrome/app's set is the global `k...Icon` from `chrome/app/vector_icons/vector_icons.h` (`//chrome/app/vector_icons`). **There is no `chevron_left` at 154**: the left arrow is `kChevronRightIcon` rotated 180 (`gfx::ImageSkiaOperations::CreateRotatedImage`) |
| our "tabs put away" icon | **no `aggregate_vector_icons` target**: that template needs its two `.template` files inside the icon's directory. Hand-write it in our `.cc`, the form the generator emits (`components/vector_icons/cc_macros.h`): a `static constexpr gfx::PathElement` array (`CANVAS_DIMENSIONS, 24`, then per sub-path `NEW_PATH, STROKE, 2, ...` -- `NEW_PATH` resets the paint to fill, so `STROKE` repeats), a `gfx::VectorIconRep` list `{{kPath}}`, and `constexpr gfx::VectorIcon kTabsPutAwayIcon = {reps, std::size(reps), "tabs_put_away"}`. Shapes: lines 7,4-17,4 and 5,8-19,8; `ROUND_RECT, 3, 12, 18, 9, 2`; arrow 12,14-12,18 with 10,16-12,18-14,16. **It moves to E17a**, whose bottom bar shows it |
| the Archive entry | `WorkspaceArchiveView::Show(browser, anchor)`; E17a passes the new Archive button as `anchor` and drops the + menu's `kMenuCommandArchive`; E17c changes its arrow (`workspace_archive_view.cc`, `BubbleBorder::TOP_LEFT` today) and restyles it |
| "Edit workspace..." | a new fork-owned view pair, `views/tabs/vertical/workspace_edit_bubble_view.{h,cc}` (two `sources` lines in `vertical/BUILD.gn`, already ours). **Anchored to the rail, never to a chip**: every list change runs `Rebuild()`, which deletes and remakes the chips. Colour and icon apply on click; **the name applies on Enter or when the bubble closes** (an empty name keeps the old one) -- per keystroke would rebuild the rail on every letter. "Custom emoji..." reuses `ShowNameBubble` with today's strings |
| reorder labels | "Move left / Move right" while expanded, "Move up / Move down" while collapsed (the column); same two commands, same Shift+Alt+arrow shortcuts |
| what goes | the "Change icon" submenu, `kIconPresets`/`kIconPresetNames` (the emoji presets), the separate Rename item (its bubble stays for "Custom emoji..." and the pinned section's rename, E15d) |
| data (E17a) | `workspace_prefs.{h,cc}`: `WorkspaceEntry` gains `int color = -1` and `std::string symbol`; `ParseWorkspaces` keeps `color` only in 0-8 and `symbol` only from the 12 presets (else unset -- never a refused list); `SerializeWorkspaces` writes them only when set; new free functions `SetWorkspaceColor`, `SetWorkspaceSymbol` (clears `icon`), and `SetWorkspaceIcon` clears `symbol`; the default-colour rule as a free function over the list. Tests in `workspace_prefs_unittest.cc` (`TEST(WorkspacePrefsTest, ...)` style). Service: `SetWorkspaceColor` / `SetWorkspaceSymbol` mirroring `SetWorkspaceIcon` (write the list; the list-changed callback rebuilds the rail) |
| data (E17b) | the pins file's `NodeFromValue` reads by key and ignores unknown keys, so a folder's `color` needs no version bump; `PinNode` gains it, the writer writes it when set |
| scripts that break | **in the suite**: `check-e14d2-auto.ps1` (`OpenScreen`: "+" -> "Archive") and `check-e14d3-auto.ps1` (`OpenPlus '^Archive'`) must press the bar's Archive button (role 0x2B, name "Archive"); `capture-ui.ps1` ("Change icon" -> "Edit workspace...", Archive by its button). Owner checks naming "Change icon": `check-e11-rail.ps1`, `check-e11-rename.ps1` (historical; updated or marked as such) |

**Strings** (all in `generated_resources.grd`, ours): Edit workspace…, Name, Colour, Icon, Custom emoji…, Move left,
Move right, Archive (tooltip), This workspace, All workspaces, Earlier this week, Last week, Nothing archived yet, Tabs you
close stay here for 60 days., the 12 preset names. Colour names reuse Chromium's tab-group colour strings.

**Out of scope.** Helium's strip and tab drawing (rows, selected tab, toolbar), a favorites grid (C), per-tab colours,
animations, drag-to-reorder chips.

**Hook budget.** Expected **0 new upstream files**: the rail's alignment is our own hunk in
`vertical_tab_strip_bottom_container.cc` (already ours, 09/29); everything else is in fork-created files, our BUILD.gn
entries and `generated_resources.grd`.

**Tests move with the UI.** The hands-free suite presses by accessible name: "Archive" leaves the + menu (`check-e14d2-auto`,
`check-e14d3-auto` open it there), "Rename workspace" becomes "Edit workspace…" (`check-e13*`), the rail's "+" keeps its
name. Each chunk updates the scripts it breaks in the same chunk, and `local/rebase-checks.ps1` must be 16/16 at its end.

**Split** -- one patch and one commit each; every chunk ends with `capture-ui.ps1 -Tag after-<chunk>` (both schemes)
beside the `before` set for the owner's look, a Dcheck launch (views change, 5.8.1) and the suite.

| Chunk | Patch | Scope | Checkpoint |
|---|---|---|---|
| **E17a** | `51-ui-bar` | identity data (`color`, `symbol`), "Edit workspace…" bubble, the bottom bar (anchor, Archive button **with our "tabs put away" icon**, chips, arrows on overflow, collapsed column), the workspace and + menus with icons | unit tests for the two keys' defaults and bad values; owner look at the bar; suite 16/16 |
| **E17b** | `52-ui-pinned` | header, pinned card, folder chevrons + solid coloured folders + folder Colour submenu, "+ New Tab" contrast, row radius, the collapsed card | pins file round-trip with `color`; owner look; suite 16/16 |
| **E17c** | `53-ui-archive` | the Archive screen restyle (its icon landed in E17a) | owner look; the 1,750-entry timing unchanged (E14d.2's gate); suite 16/16 |

Then the installer (Phase 2's script on the new build) and switch day.

### E18 spec -- counts in the headers, roomy tabs, a gliding tab list, a wider sidebar; decided with the owner 2026-10-04

**Why.** The owner's first wishes after switch day (`<local-path>\Helium-workspace\ideas.md`, wishes 1, 4, 2 and 5; wish 3, pinned
reorder, was confirmed working). The research was a read-only workflow on the patched 154 tree (4 researchers, a skeptic
each, a gap critic; 9 agents, 1.93M tokens); its answers are summarised here with the file and line that decided each.

**Decided by the owner (2026-10-04).**

| Question | Answer |
|---|---|
| Order | wish 1 and wish 4 first, then wish 2, then wish 5; afterwards the other ideas high to low (`ideas-analysis.md`) |
| Mode | workflow mode, "plenty" of budget (estimate given: E18 ~10-15M) |
| Wish 1 | folders show how many pages they hold; the workspace header shows pinned pages and Today tabs, **and anchored tabs when there are any** |
| Wish 4 | roomier tabs like Arc, as a **Settings choice**: roomy / the current compact |
| Wish 2 | smoother scrolling like Arc, for the tab list **and** web pages, as a **Settings toggle** |
| Wish 5 | the sidebar resizes **as wide as possible**, the minimum stays, **and a Settings control** |

**Defaulted while the owner was away (2026-10-04), each with its reason -- the owner reviews these on return; any
one can be changed before landing.**

| # | Decision | Default | Why |
|---|---|---|---|
| D1 | header format | plain numbers at the right, `3,415 · 40` and ` · 3` only when anchors > 0, quieter tone; hovering spells them out ("3,415 pinned pages / 40 Today tabs / 3 anchored tabs") | words do not fit a normal width |
| D2 | a folder's number | every page inside, sub-folders included | matches the Delete-folder confirm and the collapsed folder's page menu (both recursive, `pins::CountRows`) |
| D3 | zeros | pinned and Today always shown, `0` included; anchors hidden at 0 | the owner's "if any" |
| D4 | what "Today" counts | tabs (a split counts 2, tabs in a collapsed group count), in THIS window | the list's own predicate; pinned pages are per profile, Today is per window |
| D5 | what "anchors" counts | Today tabs that are anchored -- not pinned pages (they are anchored too), not favorites | otherwise every open pinned page would count |
| D6 | narrow sidebar | below 240 px the header shows the pinned count only | at 160 px the name would be ~25 px |
| D7 | collapsed sidebar | no numbers drawn (E17's "symbol only"); none in the collapsed tooltip either | keeps E17 spec 6 |
| D8 | roomy height | ~~42 px tabs only~~ -- **the owner, after the screenshots (2026-10-04): all three as choices** -- the dropdown is Default (Helium's 30) / Roomy, 36 px / Roomy, 40 px / Roomy, 42 px, like Arc (Today pitch 44 = Arc's) | the owner looked at 36 / 40 / 42 and kept all |
| D9 | what follows roomy | Today tabs, pinned pages, folders, the section's "+ New Tab"; icon inset +3 and icon-to-title gap 12, so Today titles line up with the pinned pages' (favicon at 16, title at 44) | one list, as in Arc |
| D10 | what stays compact | the workspace header (34), the Archive rows (30), the collapsed column, Chromium's pinned-tab (favorites) grid, tab-group headers (26 px, Helium's file), Helium's own bottom "+ New Tab" (shown only with Workspaces off) | each extra one costs an upstream file or makes a tall thin tile |
| D11 | tab style storage | a **profile** pref, `helium.workspaces.tab_row_height` (int, 30 = compact, 42 = roomy; any 30-48 honoured so a test can seed 36/40), applied to the whole browser, last writer wins | the fork runs one profile; a Local State pref would need `g_browser_process` in `:workspaces` |
| D12 | web pages (wish 2) | **no page code** -- pages already glide (Chromium's default, on because Windows "Animation effects" is on; Helium and Arc change nothing); the toggle is "Smooth scrolling in the tab list" | forcing pages costs 2 new upstream files, changes nothing on this PC and reaches only new renderers |
| D13 | glide feel | every vertical wheel step glides (Logi Options+ smooth scrolling is ON on this PC: its steps are not whole notches), ease-out, 100-200 ms by step size like Chromium's page curve, steps add up; default **on**; off when Windows animations are off | a notch-only glide would never start for this mouse |
| D14 | wider sidebar control | one switch "Allow a wider sidebar", default **on** (as wide as the window allows, the page keeps 200 DIP); off = Helium's 400 | a width number would reach only new windows (no observer exists) |
| D15 | the snap to 200 | **kept** (it acts only within 15 px of 200; removing it edits Helium's lines) | the owner sits at 400+ |
| D16 | width after a restart | **fixed in E18c**: a restored window opens at the saved width, not 200 | found by the research: today every restart loses the width |

**1. Counts (wish 1) -- `54-pinned-counts`, fork files + strings, no new upstream file.**
- Header (`WorkspaceHeaderView`, `workspace_pinned_section_view.cc:283-391`): the numbers are **painted** in `OnPaint` at the
  right, inside a right inset reserved for the current text; a change of number only `SchedulePaint`s. Reason (load-bearing):
  a `Label::SetText` fires `PreferredSizeChanged`, `InvalidateLayout` always climbs (`view.cc:1034-1038`), and the section's
  BoxLayout then measures every row of the list -- 1,313 rows with the biggest folder open -- on every tab open or close.
  The reserved inset grows (one relayout) only when the text gets wider than it.
- Folder rows (`PinRow`): a right-aligned number, set once in the constructor during `Rebuild` (rows are rebuilt on every
  store change), placed where an item's buttons go (`right = width - kRowInset`), the title clamped before it -- as
  `ArchiveRow`'s time. Not in the icon-only column.
- Numbers: `base::FormatNumber` (already used by the rail and the importer); the hover text uses three plural strings
  (`IDS_HELIUM_PINNED_PAGE_COUNT`, `IDS_HELIUM_TODAY_TAB_COUNT`, `IDS_HELIUM_ANCHORED_TAB_COUNT`).
- Accessibility: names unchanged (the hands-free scripts press by exact name, `msaa-press.ps1:92`); the numbers reach a screen
  reader as the tooltip, which becomes the accessible description (`view_accessibility.cc:1079-1086`). The header's name label
  stops handling tooltips so hovering an elided name shows the counts.
- Freshness: the pinned total is taken in `Rebuild` over `RootsForWorkspace` (a loop: an item adds 1, a folder adds
  `CountRows(children)`). Today and anchored ride `ReadLinks()`'s existing walk over every tab -- only once the pins file
  has loaded, as the links do: before that the header shows no numbers at all ("As built"). New: an `OnTabPinnedStateChanged` override (a pin without a move sends no `kMoved`), and `SetAnchored`
  notifies the workspace-changed callbacks **only when IsAnchored flips** (`workspace_service.cc:2047-2070`; a re-anchor to a
  new address must not relayout the strip).
- Evidence line: `[workspaces] pins: header counts P/T/A` when a number changes.

**2. Tab style (wish 4) -- `55-tab-style`, one new upstream file: `tab_view_vertical_layout.cc` (57th).**
- The helper lives in the fork's `:prefs` leaf (`workspace_prefs.{h,cc}`): the pref, a process-wide current height with
  `SetTabRowHeight/TabRowHeight()`, and pure rules `IconInsetExtra()` (0 / +3 when roomy) and `IconTitleGap()` (7 / 12).
- `tab_view_vertical_layout.cc`: one hunk in `CalculateProposedLayout` -- when the tab is neither `pinned_` nor `collapsed_`,
  height = `TabRowHeight()`, the contents inset widened by `IconInsetExtra()`, and the icon's padding read live from
  `IconTitleGap()` (the child configs are copied once at `OnInstalled`, so a live value must be read there: also in
  `GetChildBounds`'s padding use). The file is patched by Helium's `vertical.patch` (hunks at 19-24, 32-45, 162) and
  ungoogled's hide-close-buttons (`:7`, `:176`); the new hunk is at 52-84, overlapping neither. Dep line `:prefs` in
  `views/tabs/common/BUILD.gn` (fork-patched). `layout_constants.cc` is NOT touched (it cannot see pinned/collapsed, and
  would need a second file for the gap).
- The service (per window, built in `BrowserWindowFeatures::Init` before the views) sets the global from the pref and
  observes it; on a change it re-sets the global and notifies the list-changed callbacks (as `OnEnabledChanged` does).
- The pinned section, at the TOP of `Rebuild` (before the hidden-section return; inside the posted rebuild, never from
  `AddedToWidget` -- `GetScrollViewForContents` DCHECKs there, `scroll_view.cc:392`): if the drawn height differs, hold a
  `ScopedBulkLayout` (patch 37) and `InvalidateLayout` every `TabView` under the `TabStripView`, hidden workspaces' too;
  restyle "+ New Tab" (height, left inset 16, spacing 12); rebuild the rows with `RowHeight`. Log the walk's ms.
- Rows: `PinRow`'s min height and the drag-scroll probe (`:1667`, the probe rectangle, not a row) read the helper.
- Incognito/guest windows have no service and no section: their open tabs pick up a change at their next layout.

**3. Glide (wish 2) -- `56-smooth-scroll`, no new upstream file.**
- A class inside `workspace_pinned_section_view.cc` (`ui::EventHandler` + `views::AnimationDelegateViews`, a
  `gfx::LinearAnimation`), added as a pre-target handler on the tab list's `ScrollView` from the posted `Rebuild` (before
  the hidden return, so it also smooths Helium's plain strip with Workspaces off), removed in `RemovedFromWidget` and the
  destructor (raw_ptr to the scroll view).
- It takes a wheel event only when: the pref is on, `gfx::Animation::ShouldRenderRichAnimation()`, `x_offset == 0`, no
  Ctrl/Shift, and vertical scrolling is enabled. Target = (running target, else `CurrentOffset().y()`) − `y_offset`,
  clamped to the range; duration 100-200 ms by the step's size (Chromium's page curve: a whole notch 200 ms);
  `SetDuration` while running restarts the ease (`Start()` is a no-op while running, `animation.cc:38-40`); `SetHandled`.
  A pass-through event is seen once per bubbling level: the handler keeps no state for events it does not take.
- Each frame: if `CurrentOffset().y()` is not what the glide last wrote (a drag's auto-scroll, the active-tab reveal, the
  keyboard, the scroll bar), stop; else `ScrollToPosition` (it clamps) with `Tween::EASE_OUT`, then record the offset READ
  BACK. The rail's chips and the favorites grid are not touched.
- Evidence line: `[workspaces] glide: A -> B (N ms)` per glide.

**4. Wider sidebar (wish 5) -- `57-wide-sidebar`, no new upstream file.**
- `vertical_tab_strip_region_view.cc` (the fork's since 50): the drag clamp (`:600`, the keyboard resize goes through it)
  uses `max(160, browser_view()->width() − kContentsContainerMinimumWidth (200))` when `helium.workspaces.wide_sidebar` is
  on, else 400. When a drag ends, the saved width is the DRAWN width (the layout also subtracts the toolbar's minimum,
  `browser_view_tabbed_layout_impl.cc:512-518`, so the target could run ahead of what is drawn). Includes at the end of
  the include block, where Helium adds nothing. Dep `:prefs` in `chrome/browser/ui/BUILD.gn` (fork-patched).
- `browser_window_features.cc` (fork-patched by 01/04/08/19): a session-restored window reads the saved width too (drop
  `!browser->CreatedBySessionRestore()` at `:647`; Helium's `core.patch` removed the session's own width, so today every
  restored window opens at 200 and its first collapse writes 200 back over the pref, `controller.cc:292-297`).
- The snap to 200, the minimum 160 and the collapse below 101 stay.

**Settings** (Settings > Appearance, inside Helium's vertical-only block, ABOVE the Workspaces toggle because all three also
work with Workspaces off; each hunk written at its final position): (1) Tab strip on the right (Helium); (2) **Tab style** --
dropdown Default (Helium's, 30) / Roomy, 36 px / Roomy, 40 px / Roomy, 42 px, like Arc (the owner, D8); (3) **Smooth scrolling in the tab list** -- toggle, sub-label "The tab list
glides when you roll the mouse wheel."; (4) **Allow a wider sidebar** -- toggle, sub-label "Drag the sidebar's edge as wide
as the window allows; off keeps the 400 px limit."; (5) Workspaces (18) and its "Archive tabs after" (49). Four files, all
already the fork's: `settings_strings.grdp`, `settings_localized_strings_provider.cc`, `appearance_page.html.ts`,
`prefs_util.cc` (the allowlist -- a missing entry gives a control that never saves). Prefs are siblings of
`helium.workspaces.enabled`; `workspace_prefs_unittest.cc`'s nesting test lists each new one, plus a name and a default test.

**Hook budget.** One new upstream file (`tab_view_vertical_layout.cc`): **56 -> 57**. Everything else is fork files or files the
fork already patches.

**Tests.** Unit: the three prefs (name, default, sibling rule), the style rules (compact/roomy, pinned/collapsed stay
compact), the width rule. Hands-free (new `local/check-e18-auto.ps1`): the counts line after open / close / move / Chromium-pin
/ anchor / open a pinned page / unpin; the style flip (an MSAA rect height 30 -> 42 for a Today tab, a pinned page and
"+ New Tab", in two windows); a guarded wheel step (SendInput) graded by the glide line; the wider drag past 400 and the width
after a restart. `check-e16-auto.ps1` is rewritten for the window-relative max (and keeps a `wide_sidebar=false` run for the
old 400 assertion). `capture-ui.ps1` gains a row-height seed. The suite (16) on Default and Dcheck, 0 markers.

**Split.**

| Chunk | Patch | Scope | Checkpoint |
|---|---|---|---|
| **E18a** | `54-pinned-counts`, `55-tab-style` | wish 1, wish 4 + the Tab style row | unit tests; counts + style checks; screenshots compact / 36 / 40 / 42, light and dark; owner look + the height pick |
| **E18b** | `56-smooth-scroll` | wish 2 + its toggle | the glide check; owner feel check (Logi on) |
| **E18c** | `57-wide-sidebar` | wish 5 + its toggle + the restore-width fix | e16 rewritten; restart step; owner drag check |

**As built (2026-10-04), where the code differs from the text above -- review lens findings included.**
- Counts: when the numbers outgrow their room, only the HEADER lays itself out again (`DeprecatedLayoutImmediately`, as
  `PinRow::SetItemState` does); its size never changes, so nothing climbs. The numbers are hidden (and not logged) until the
  pins file has loaded, instead of a "0" for a moment. The header's mark passes the hover to the header, so the counts tooltip
  shows over it too. A folder's tooltip is set ONCE (review: a second `SetTooltipText` let `Button` rename the folder to
  "title + count", which every test that finds a folder by name would miss).
- Tab style: tabs are not re-measured at startup with Roomy saved (they are made at the current height); only a change walks
  them. Each window logs its own "row height A -> B". Pinned rows at 42 pitch 42; Today tabs at 42 pitch 44 (a 2 px gap) --
  judged on the captures.
- Glide: the step duration is 100 ms for a small step rising to 200 ms for a whole notch (the opposite of Chromium's page
  curve, which gives a small step the longest time); two constants in the section file, tuned after the owner's feel check.
  A step carries a running glide on only if nothing else moved the list since its last frame. Incognito, guest and popup
  windows have no section, so no glide (as no Tab style walk).
- Wider sidebar: when a drag ends, the DRAWN width is kept whenever the layout drew less than asked -- with the setting off
  too, or in a narrow window, or beside a side panel; the window is laid out synchronously only when the last frame did not
  already draw the asked width. A drag that ends during the expand animation keeps Chromium's behaviour (the asked width, no
  log line). A restored window gets the saved WIDTH only (Helium's `core.patch` also dropped its collapsed state). An upstream
  `ResizeArea` slip on a lost mouse capture (a bogus jump) was bounded by 400 and is now bounded by window - 200 -- accepted.
  Sub-label: "Drag the sidebar's edge as wide as the window allows. When off, a drag stops at 400 px" (off does not shrink a
  wider sidebar at once: no pref observer exists, D14).

**Out of scope.** Page-scroll code (D12); tab-group headers and Helium's bottom "+ New Tab" in roomy (D10); a width number in
Settings (D14); removing the snap (D15).

## 6. Verified at 152.0.7977.82 (2026-09-07)

Everything here was read from source at the pinned tag. Verbatim quotes with file and line
numbers are archived at `<local-path>\Helium-workspace\research\`. Re-verify on a major bump.

**Line numbers are a convenience, not an anchor.** Every citation below was re-verified on
2026-09-07 against the extracted tree at `helium-windows/build/src` (pre-patch, Chromium
152.0.7977.82). Search for the symbol, not the line, when a number no longer matches.

| Claim | Where |
|---|---|
| Chromium 152 ships vertical tabs natively; `kVerticalTabsLaunch` is `ENABLED_BY_DEFAULT` off ChromeOS; the Helium `core.patch` also flips `kVerticalTabs` and swaps the boolean pref for `kHeliumLayout` | `chrome/browser/ui/tabs/features.cc` |
| Collection classes live in `components/tabs/public/` (namespace `tabs`), **not** `chrome/browser/ui/tabs/` | `components/tabs/public/*.h` |
| `TabStripCollection` ctor hard-wires Pinned at 0 and Unpinned at 1 as `raw_ptr` members used in `GetInsertionDetails` | `components/tabs/impl/tab_strip_collection.cc` |
| `TabGroupTabCollection` allowed children = `{SPLIT}`; only `UnpinnedTabCollection` allows `GROUP`; enforced by `CHECK` in `AddCollection` — **groups cannot nest** | `tab_group_tab_collection.cc`, `tab_collection.h` |
| `TabCollection::Type` is a closed enum with `MAX = SPLIT` | `components/tabs/public/tab_collection.h` |
| `contents_data_` is an unconditional `unique_ptr<TabStripCollection>`; index equals depth-first leaf order; no flag gates the tree | `tab_strip_model.cc` |
| **`ReentrancyCheck` CHECKs**; observers are notified inside the guarded scope | `tab_strip_model.cc:130` |
| the `should_show_child` predicate exists in both vertical layout functions | `unpinned_tab_container_view_layout.cc` |
| three direct child kinds: `TabView`, `TabGroupView`, `SplitTabView` | `tab_collection_node.cc` `CreateViewForNode` |
| `AddTabExtraData` exists and flows through both restore paths | `session_service.h:132`, `browser_tabrestore.cc` |
| `BuildCommandsForTab` does **not** re-emit extra data; `ScheduleResetCommands` wipes and rebuilds at startup | `session_service.cc` |
| `SessionTabHelper` assigns `SessionID::NewUnique()`; no setter; restore never reassigns old ids | `session_tab_helper.cc:23` |
| post-close selection runs before observers and ignores workspaces | `DetermineNewSelectedIndex` |
| `patches/series` is one 357-line file — no per-tag companion | local repo |
| the Helium `BrowserShortcutService` drops unlabelled IDCs and DCHECKs | `custom-keyboard-shortcuts.patch` |
| Helium IDC block 34080 to 34091 used; 34100 is the upstream tab-group block | `chrome_command_ids.h` plus Helium patches |
| `kHeliumWorkspacesList` would not sync unless allow-listed; `core.patch` removed `kVerticalTabsEnabled` from that list | `chrome_syncable_prefs_database.cc` |
| helium-windows carries WinSparkle updater patches, but `enable_winsparkle` defaults to false and `build.py` sets it only when `WINSPARKLE_ED_KEY` and `WINSPARKLE_AUTHENTICODE_ORG` are both set, so a fork build has no updater | `helium-windows/patches/helium/windows/updater/build-wiring.patch`, `build.py:373` |
| LICENSE is GPLv3 — obligations trigger on **distribution** only, so private use is fine (a distinct product name is still right; GPL grants no trademark rights) | `LICENSE` |
| upstream is not building this: #1351, #215, #245 all open and untriaged; PR #1578 (anchored tabs) closed unmerged 2026-08-08, nothing in tree | GitHub |

**Still unverified:** when `AddTabExtraData` was introduced upstream (Gitiles 403, commit
search empty). It is clearly live — two 2026-copyright Google features and Brave use it — but
treat signature stability as likely rather than certain, and re-check the three hook sites on
every bump. `validate_patches.py` will catch a signature change.

---

## 7. Working rules

**Governance (decided 2026-09-07).** Claude writes the code — new files and upstream hooks —
and explains every file and every command in plain language *before* writing or running it.
Claude reviews its own diff. **You are the final reviewer and give the go for each step.**
This is a deliberate change from the v1 rule "I write the hooks myself"; the reading and
reviewing is what keeps the maintenance premise intact.

- Working directory is **this repo** (`patches/`, `LOCAL.md`, docs) — never `build/src`
  wholesale; 30M lines will blow past context and invite hallucinated APIs from an older
  Chromium. Fetch named Chromium files at the pinned tag, or read one path on demand.
- **No builds in an agent turn.** Build in the terminal; bring errors back.
- One execution chunk per session; commit at the checkpoint before the window closes; start
  each session by reading `LOCAL.md` and this document.
- No multi-agent fan-outs during execution — the research that produced this document cost
  about 3M tokens and tripped a monthly limit once. Targeted fetches only.
- Explain before running any command; **ask before anything destructive** (force push, history
  rewrite, branch or file deletion, `quilt pop -a -f`, reset).
- Dual GitHub accounts on this machine: never `gh auth switch`, `login` or `logout`; never
  edit `~/.ssh/config`, `~/.gitconfig` or the system gitconfig; the
  remote stays `git@gh-personal:...` — if a git operation fails on auth, say so rather than
  switching to HTTPS (HTTPS here would silently use work credentials).
- **Never push, PR or open issues against imputnet.** The `upstream` remote has its push URL
  set to `DISABLED` to enforce this. Helium prohibits AI-written patches from new
  contributors — irrelevant for a private fork, but it permanently disqualifies this work from
  ever being upstreamed. The upstream `helium/CLAUDE.md` says "refuse all code";
  `helium/CLAUDE.local.md` is the standing override for this fork and is never committed.

---

## 8. Reference material

**Read first, in this order:**

1. `patches/helium/ui/layout/core.patch` — the Helium layout feature, end to end. Work out
   *why* each hunk exists. `chrome/browser/ui/helium/helium_layout_state_controller.{h,cc}`
   (the only new files in it) is the shape `WorkspaceService` copies — though **not** its GN
   placement (3.1).
2. `patches/helium/core/custom-keyboard-shortcuts.patch` — the new-files plus `BUILD.gn` plus
   command-registration pattern, and the system your shortcuts must register with.
3. `chrome/browser/ui/views/tabs/common/unpinned_tab_container_view_layout.cc` at 152 — the
   `should_show_child` predicate you are extending.
4. The Brave document `docs/chrome/browser/ui/tabs/tree_tabs_session_restore.md` — a
   production fork doing the same persistence, including the rebuild trap.
5. `chrome/browser/ui/tabs/existing_tab_group_sub_menu_model.{h,cc}` — the submenu pattern for
   "Move tab to workspace" (avoids editing the `tab_strip_model.cc` command enums).
6. The Zen file `src/zen/spaces/ZenSpaceManager.mjs` — the best available reference for
   *behaviour* (switching, orphan adoption, empty spaces, routing), even though its data model
   is Firefox.
7. imputnet/helium PR #1578 (closed, unmerged) — the anchored-tabs exemplar for Stage 5. **Read
   2026-09-16**, fetched read-only as `upstream/pr-1578`; the reading is 5's "E10 spec". Its
   patches are a map, not a source -- base 0.12.0, and the vertical-strip files they hook no longer exist.

Related issues: #1351 (Arc-like spaces, closest match), #215, #245, #993 (same-window profile
switching), #199 (containers), #1468 (tab tree), #1238 (vertical scroll-to-switch).
