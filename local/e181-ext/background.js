// E18.1 test fixture (LOCAL.md 66), loaded only by check-e181.ps1 into a throwaway profile. The script
// switches workspaces (MSAA on the rail) and opens the pages; this does what only an extension can:
//   1. once "E18 g1..g3" are open in one window (W1, on Work), group them -> a saved group in Work
//   2. once "E18 go" appears (the script's signal: W1 is back on Home), open W2 -- it starts on the
//      workspace of the window used last, Home -- and close W1 -> a closed WINDOW in Recently Closed
//   3. reopen that window by id (what History > Recently closed does) -> W3, on Home, whose group
//      Chromium rebuilds from its saved-group model (BrowserLiveTabContext::AddRestoredTab)
// Every step logs one "E181-EXT ..." line; the script waits on them and grades the browser's own lines.
const log = (...a) => console.log('E181-EXT', ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const GROUPED = ['E18 g1', 'E18 g2', 'E18 g3'];

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

async function tabsTitled(titles) {
  const all = await chrome.tabs.query({});
  const found = titles.map((t) => all.find((x) => x.title === t));
  return found.every(Boolean) ? found : null;
}

(async () => {
  const pages = await waitFor(() => tabsTitled(GROUPED), 240000);
  if (!pages) return log('FAIL: the three pages never opened');
  const w1 = pages[0].windowId;
  if (!pages.every((t) => t.windowId === w1)) return log('FAIL: the pages are in different windows');
  const group = await chrome.tabs.group({ tabIds: pages.map((t) => t.id) });
  await chrome.tabGroups.update(group, { title: 'E18.1 group' });
  log(`grouped ${pages.length} tab(s) in window ${w1}`);

  if (!(await waitFor(() => tabsTitled(['E18 go']), 240000))) return log('FAIL: no go signal');
  const w2 = await chrome.windows.create({});
  log(`opened window ${w2.id}`);
  await sleep(4000);
  await chrome.windows.remove(w1);
  log(`closed window ${w1}`);

  const entry = await waitFor(async () => {
    const closed = await chrome.sessions.getRecentlyClosed({ maxResults: 10 });
    return closed.find((e) => e.window && e.window.tabs.some((t) => GROUPED.includes(t.title)));
  }, 20000);
  if (!entry) return log('FAIL: the closed window is not in Recently Closed');
  log(`restoring a closed window of ${entry.window.tabs.length} tab(s)`);
  try {
    const back = await chrome.sessions.restore(entry.window.sessionId);
    const w3 = back.window ? back.window.id : -1;
    await sleep(5000);
    const groups = await chrome.tabGroups.query({ windowId: w3 });
    // Each group's tabs in strip order: recorded, not graded (a rebuilt group may come back reversed, LOCAL.md 66).
    const sizes = await Promise.all(groups.map(async (g) => {
      const tabs = (await chrome.tabs.query({ groupId: g.id })).sort((a, b) => a.index - b.index);
      return `'${g.title}' ${tabs.length} [${tabs.map((t) => t.title).join(' | ')}]`;
    }));
    log(`restored window ${w3}: groups ${sizes.join(', ') || 'none'}`);
  } catch (e) {
    return log('FAIL: restore failed: ' + e);
  }

  // check-e181.ps1 -Group: "E18 g4".."E18 g6" opened in W3 on Work become a second group, which the script closes
  // (Alt+Shift+W) and reopens (Ctrl+Shift+T) from Home -- a group of its own, whatever happened to the first.
  const more = await waitFor(() => tabsTitled(['E18 g4', 'E18 g5', 'E18 g6']), 240000);
  if (!more) return;
  const second = await chrome.tabs.group({ tabIds: more.map((t) => t.id) });
  await chrome.tabGroups.update(second, { title: 'E18.1 second' });
  log(`grouped second ${more.length} tab(s) in window ${more[0].windowId}`);

  // E18.2: "E18 g7" alone becomes a ONE-tab group, which the script closes and reopens from Home -- a group with no
  // second tab, so nothing but patch 59 pulls the window to it.
  const single = await waitFor(() => tabsTitled(['E18 g7']), 240000);
  if (!single) return;
  const lone = await chrome.tabs.group({ tabIds: [single[0].id] });
  await chrome.tabGroups.update(lone, { title: 'E18.2 single' });
  log(`grouped single 1 tab(s) in window ${single[0].windowId}`);
})();
