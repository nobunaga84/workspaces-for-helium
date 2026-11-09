// E14c.2 test fixture (LOCAL.md 42; rebuilt by the hook shrink, 119, when the E14c rehearsal's closed window had aged
// out of testprofile), loaded only by check-e14c2-reopen.ps1 into a throwaway copy of the smoke profile. It builds
// what Chromium's own TabRestoreTest.RestoreTabGroupFromClosedWindow builds, then reopens the closed window:
//   1. once "E18 g1".."E18 g4" and "E18 loose" are open in one window (W1): g1..g4 grouped ("E38 group", saved by
//      Chromium), g2 and g3 split
//   2. W2 opened, W1 closed -> a closed WINDOW in Recently Closed whose tabs carry the saved group and the split
//   3. the script opens the group again in W2 from the app menu (Tab groups > E38 group > Open group:
//      OpenSavedTabGroup, the revisit path); g2 and g3 are split again there
//   4. W1 reopened by id (what History > Recently closed does): BrowserLiveTabContext::AddRestoredTab meets a saved
//      group open in another window -- patch 38's case; with Workspaces off the group moves over, split, and the split
//      rebuild meets two halves already split -- the guard's case
// Every step logs one "E14C2-EXT ..." line; the script waits on them and grades the browser's own lines.
const log = (...a) => console.log('E14C2-EXT', ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const GROUPED = ['E18 g1', 'E18 g2', 'E18 g3', 'E18 g4'];
const TITLE = 'E38 group';

// Polls `probe` (each chrome.* call also keeps this service worker alive) until it returns something.
async function waitFor(probe, ms) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    const v = await probe();
    if (v) return v;
    await sleep(500);
  }
  return null;
}

async function tabsTitled(titles, windowId) {
  const all = await chrome.tabs.query(windowId === undefined ? {} : { windowId });
  const found = titles.map((t) => all.find((x) => x.title === t));
  return found.every(Boolean) ? found : null;
}

// g2 and g3 of window `windowId` split; what happened. Waits for their titles: a group just opened from the menu has
// its tabs before their pages load (the first Dcheck run split nothing).
async function split(windowId) {
  const halves = await waitFor(() => tabsTitled(['E18 g2', 'E18 g3'], windowId), 30000);
  if (!halves) return 'FAILED: g2 and g3 not both in the window';
  try {
    return `split ${await chrome.tabs.createSplit(halves.map((t) => t.id))}`;
  } catch (e) {
    return 'FAILED: ' + e;
  }
}

(async () => {
  // Once per browser session: MV3 runs this file again each time it wakes a stopped worker.
  if ((await chrome.storage.session.get('built')).built) return;
  await chrome.storage.session.set({ built: true });
  const pages = await waitFor(() => tabsTitled([...GROUPED, 'E18 loose']), 240000);
  if (!pages) return log('FAIL: the five pages never opened');
  const w1 = pages[0].windowId;
  if (!pages.every((t) => t.windowId === w1)) return log('FAIL: the pages are in different windows');
  const group = await chrome.tabs.group({ tabIds: pages.slice(0, 4).map((t) => t.id) });
  await chrome.tabGroups.update(group, { title: TITLE });
  log(`grouped 4 tab(s) in window ${w1}; ${await split(w1)}`);

  const w2 = await chrome.windows.create({ focused: true });
  log(`opened window ${w2.id}`);
  await sleep(4000);
  await chrome.windows.remove(w1);
  log(`closed window ${w1}`);

  // Step 3 is the script's: the app menu of W2.
  const open = await waitFor(async () => (await chrome.tabGroups.query({ title: TITLE }))[0], 180000);
  if (!open) return log('FAIL: the group was never opened again');
  const tabs = await chrome.tabs.query({ groupId: open.id });
  log(`group open again in window ${open.windowId}: ${tabs.length} tab(s)`);
  log(`split again: ${await split(open.windowId)}`);
  await sleep(3000);

  const entry = await waitFor(async () => {
    const closed = await chrome.sessions.getRecentlyClosed({ maxResults: 10 });
    return closed.find((e) => e.window && e.window.tabs.some((t) => GROUPED.includes(t.title)));
  }, 20000);
  if (!entry) return log('FAIL: the closed window is not in Recently Closed');
  log(`restoring a closed window of ${entry.window.tabs.length} tab(s)`);
  try {
    const back = await chrome.sessions.restore(entry.window.sessionId);
    log(`restore returned: window ${back.window ? back.window.id : -1}`);
  } catch (e) {
    return log('restore failed: ' + e);
  }
  // What each window holds afterwards (G: in a group, S: in a split) -- recorded, not graded.
  await sleep(5000);
  for (const w of await chrome.windows.getAll({ populate: true })) {
    const strip = w.tabs.map((t) => `${t.groupId >= 0 ? 'G:' : ''}${t.splitViewId >= 0 ? 'S:' : ''}${t.title}`);
    log(`window ${w.id}: ${strip.join(' | ')}`);
  }
})();
