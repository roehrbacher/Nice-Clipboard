// Run: node tests/history.test.js
const assert = require("assert")
const H = require("../ClipboardHistory.js")

let h = []
h = H.addEntry(h, { type: "text", text: "one" }, 3)
h = H.addEntry(h, { type: "text", text: "two" }, 3)
h = H.addEntry(h, { type: "text", text: "three" }, 3)
assert.deepStrictEqual(h.map(e => e.text), ["three", "two", "one"], "newest first")

h = H.addEntry(h, { type: "text", text: "one" }, 3)
assert.deepStrictEqual(h.map(e => e.text), ["one", "three", "two"], "re-copy moves to top, no duplicate")

h = H.togglePinAt(h, 2) // pin "two"
assert.strictEqual(h[2].pinned, true, "pin")
h = H.addEntry(h, { type: "text", text: "four" }, 3)
h = H.addEntry(h, { type: "text", text: "five" }, 3)
assert.ok(h.some(e => e.text === "two" && e.pinned), "pinned survives the limit")
assert.strictEqual(h.filter(e => !e.pinned).length, 3, "limit counts unpinned only")

{
  const before = h.findIndex(e => e.text === "two")
  h = H.addEntry(h, { type: "text", text: "two" }, 3)
  assert.strictEqual(h.filter(e => e.text === "two").length, 1, "no duplicate")
  assert.strictEqual(h.findIndex(e => e.text === "two"), before, "re-copy of a pinned entry keeps its place (drag order)")
  assert.strictEqual(h[before].pinned, true, "re-copy keeps the pin")
  h = H.addEntry(h, { type: "text", text: "two" }, 3) // put it on top for the next checks
  h = [h[before]].concat(h.filter((e, i) => i !== before))
}

let rows = H.displayRows(h, "", 50)
assert.strictEqual(rows[0].pinned, true, "pinned rows first")
assert.strictEqual(rows[0].slot, 1)
assert.strictEqual(rows[1].pinned, false)
assert.strictEqual(rows[1].slot, 2, "slots run top to bottom: history continues after the pinned rows")

rows = H.displayRows(h, "F.VE", 50)
assert.deepStrictEqual(rows.map(r => r.previewText), ["five"], "case-insensitive regex")
rows = H.displayRows(h, "(", 50)
assert.deepStrictEqual(rows, [], "invalid regex falls back to plain text")
rows = H.displayRows([{ type: "text", text: "c++ (x)" }], "c++ (", 50)
assert.strictEqual(rows.length, 1, "plain text match with regex chars")

let cleared = H.clearHistory(h)
assert.deepStrictEqual(cleared.map(e => e.text), ["two"], "clear keeps pinned")

let removed = H.removeEntryAt(h, 0)
assert.ok(!removed.some(e => e.text === "two"), "delete removes even pinned")

assert.strictEqual(H.parseEntryJson('{"type":"text","text":"   "}'), null, "blank ignored")
assert.deepStrictEqual(H.parseHistory("not json"), [], "broken file -> empty")
assert.deepStrictEqual(H.parseHistory('[{"type":"text","text":"a","pinned":true},"b"]'),
  [{ type: "text", text: "a", pinned: true }, { type: "text", text: "b" }], "stock format imports")

let f = H.displayRows([{ type: "text", text: "file:///home/x/a%20b.png\n" }], "", 5)
assert.strictEqual(f[0].entryType, "file")
assert.strictEqual(f[0].previewText, "a b.png")
let mixed = H.displayRows([{ type: "text", text: "see file:///etc/hosts\nnot a file" }], "", 5)
assert.strictEqual(mixed[0].entryType, "text", "mixed text is not a file list")

let big = "x".repeat(20000)
let br = H.displayRows([{ type: "text", text: big }], "", 5)
assert.ok(br[0].fullText.length <= 8192, "display capped")

let img = H.addEntry([], { type: "image", path: "/tmp/a.png", mime: "image/png", capturedAt: "Saturday 07:00" }, 5)
assert.strictEqual(H.displayRows(img, "image", 5).length, 1, "images searchable")

// Search field keys: text-field shortcuts must reach the field ("").
const K = H.KEY
const act = (key, mods = {}) => H.searchKeyAction(Object.assign({ key, ctrl: false, alt: false, shift: false, hasSelection: false }, mods))
assert.strictEqual(act(K.A, { ctrl: true }), "", "Ctrl+A selects all in the field")
assert.strictEqual(act(K.C, { ctrl: true, hasSelection: true }), "copySelection", "Ctrl+C copies the selected search text")
assert.strictEqual(act(K.Insert, { ctrl: true, hasSelection: true }), "copySelection", "Ctrl+Insert copies too")
assert.strictEqual(act(K.C, { ctrl: true }), "", "Ctrl+C without a selection is left to the field")
assert.strictEqual(act(K.X, { ctrl: true, hasSelection: true }), "cutSelection", "Ctrl+X cuts the selected search text")
assert.strictEqual(act(K.V, { ctrl: true }), "", "Ctrl+V pastes into the field")
assert.strictEqual(act(0x01000003, { ctrl: true }), "", "Ctrl+Backspace deletes a word")
assert.strictEqual(act(0x01000003), "", "Backspace edits")
assert.strictEqual(act(0x5a, { ctrl: true }), "", "Ctrl+Z undoes")
for (const k of [K.Left, K.Right, K.Up, K.Down, K.Home, K.End])
  assert.strictEqual(act(k, { shift: true }), "", "Shift+arrow/Home/End selects text: " + k)
for (const k of [K.Left, K.Right]) assert.strictEqual(act(k), "", "Left/Right move the text cursor")
assert.strictEqual(act(K.Up), "up")
assert.strictEqual(act(K.Down), "down")
assert.strictEqual(act(K.K, { ctrl: true }), "up")
assert.strictEqual(act(K.J, { ctrl: true }), "down")
assert.strictEqual(act(K.Home), "home")
assert.strictEqual(act(K.End), "end")
assert.strictEqual(act(K.PageDown), "pageDown")
assert.strictEqual(act(K.Return), "enter")
assert.strictEqual(act(K.Return, { shift: true }), "enter")
assert.strictEqual(act(K.Escape), "escape")
assert.strictEqual(act(0x33, { alt: true, slot: 3 }), "ignore", "plain Alt+3 does nothing since 1.29.0 (and types nothing)")
assert.strictEqual(act(0x21, { alt: true, shift: true, slot: 1 }), "slot", "Alt+Shift+1 (German ! key) = slot 1")
assert.strictEqual(act(0x33, { ctrl: true }), "", "Ctrl+3 is no longer a shortcut")
assert.strictEqual(act(K.P, { ctrl: true }), "pin", "Ctrl+P pins")
assert.strictEqual(act(K.F, { ctrl: true }), "pin", "Ctrl+F still pins")
assert.strictEqual(act(K.I, { ctrl: true }), "private", "Ctrl+I toggles incognito")
assert.strictEqual(act(K.Delete), "delete", "Del removes the entry")
assert.strictEqual(act(K.Delete, { hasSelection: true }), "", "Del with selected search text deletes the text")
assert.strictEqual(act(K.Delete, { shift: true }), "clear")
assert.strictEqual(act(0x61), "", "typing goes to the field")
assert.strictEqual(act(K.U, { ctrl: true }), "clearSearch", "Ctrl+U clears the search without touching the clipboard")

// ---- 1.3.0 ------------------------------------------------------------------
// 4: Ctrl+N / Alt+N find the row and paste on modifier release
{
  const rows = H.displayRows([{ type: "text", text: "a", pinned: true }, { type: "text", text: "b" }, { type: "text", text: "c" }], "", 50)
  assert.deepStrictEqual(rows.map(r => r.slot), [1, 2, 3], "Alt+1..3 top to bottom, pinned first")
  for (const k of [K.Control, K.Alt, K.Shift, K.Meta]) assert.ok(H.isModifierKey(k), "modifier " + k)
  assert.ok(!H.isModifierKey(0x31), "digit is not a modifier")
  assert.strictEqual(act(K.S, { ctrl: true }), "send", "Ctrl+S sends to the phone")
}
// 5: pinned rows need a second Del
assert.strictEqual(H.deleteAction(false, false), "delete", "unpinned: delete at once")
assert.strictEqual(H.deleteAction(true, false), "arm", "pinned: first Del arms")
assert.strictEqual(H.deleteAction(true, true), "delete", "pinned + armed: second Del deletes")
assert.strictEqual(H.pinnedCount([{ pinned: true }, {}, { pinned: true }]), 2)
// 2: popup scale
assert.strictEqual(H.popupScale(1080), 1, "24in 1080p unchanged")
assert.strictEqual(H.popupScale(1440), 1, "bigger screens unchanged")
assert.strictEqual(H.popupScale(750), 0.85, "small laptop screen (1200x750 logical) 15% smaller")
assert.strictEqual(H.popupScale(1000), 1000 / 1080, "in between: proportional")
// 9: Flux origin
{
  const st = { clipboard: [{ dir: "in", text: "hello", time: 1000 }, { dir: "out", text: "mine", time: 1000 }],
               devices: [{ paired: true, online: true }] }
  assert.strictEqual(H.fluxOrigin(st, "hello", 1005), "phone")
  assert.strictEqual(H.fluxOrigin(st, "mine", 1005), "", "own copies are not from the phone")
  assert.strictEqual(H.fluxOrigin(st, "hello", 2000), "", "old incoming copy does not count")
  assert.strictEqual(H.fluxOrigin(null, "hello", 1005), "")
  assert.ok(H.fluxPhoneOnline(st))
  assert.ok(!H.fluxPhoneOnline({ devices: [{ paired: true, online: false }] }))
  assert.strictEqual(H.fluxPhoneName({ devices: [{ paired: true, online: false, name: "A" }, { paired: true, online: true, name: "B" }] }), "B")
  assert.strictEqual(H.fluxPhoneName({ devices: [] }), "")
  assert.strictEqual(H.fluxLastSync(st), 1000)
  assert.strictEqual(H.fluxLastSync({}), 0)
  assert.strictEqual(H.agoLabel(0, 5), "never")
  assert.strictEqual(H.agoLabel(1000, 1030), "just now")
  assert.strictEqual(H.agoLabel(1000, 1000 + 300), "5 min ago")
  assert.strictEqual(H.agoLabel(1000, 1000 + 7200), "2 h ago")
  assert.strictEqual(H.agoLabel(1000, 1000 + 3 * 86400), "3 d ago")
  assert.strictEqual(H.phoneIconState("running", true), "online")
  assert.strictEqual(H.phoneIconState("running", false), "nophone")
  assert.strictEqual(H.phoneIconState("absent", true), "", "hidden without Flux")
  assert.strictEqual(H.phoneIconState("", false), "", "hidden before the first check")
  assert.strictEqual(H.phoneIconState("paused", false), "paused", "incognito pauses Flux")
  assert.strictEqual(H.phoneIconState("off", false), "off")
  assert.strictEqual(H.phoneTooltip("online", "Pixel"), "Pixel connected via Flux")
  assert.strictEqual(H.phoneTooltip("nophone", ""), "No phone connected")
  assert.strictEqual(H.phoneTooltip("paused", ""), "Flux paused (incognito)")
  assert.strictEqual(H.phoneTooltip("off", ""), "Flux not running")
  const h = H.setOrigin([{ type: "text", text: "hello" }], "hello", "phone")
  assert.strictEqual(H.parseHistory(JSON.stringify(h))[0].origin, "phone", "origin survives save/load")
  assert.strictEqual(H.displayRows(h, "", 5)[0].fromPhone, true)
  assert.strictEqual(H.addEntry(h, { type: "text", text: "hello" }, 50)[0].origin, undefined, "a local re-copy is not from the phone")
}

// 1.3.1: touchpad momentum
assert.strictEqual(H.kineticVelocity(0, 30, 150), 200, "first delta after a pause: instant speed")
assert.strictEqual(H.kineticVelocity(1000, 30, 200), 150, "a long pause starts over")
assert.strictEqual(Math.round(H.kineticVelocity(3000, 20, 10)), 2600, "smoothed")
assert.strictEqual(H.kineticFlickVelocity(2600, 16), 2600, "fingers lifted while moving: flick")
assert.strictEqual(H.kineticFlickVelocity(2600, 200), 0, "fingers stopped before lifting: no flick")
assert.strictEqual(H.kineticFlickVelocity(100, 10), 0, "slow drag: no flick")

// 1.4.0: action order phone, trash, pin (pin rightmost, never moves)
assert.deepStrictEqual(H.rowActionNames(false, true, true), ["send", "delete", "pin"], "send first")
assert.deepStrictEqual(H.rowActionNames(false, false, true), ["delete", "pin"], "no phone: no send")
assert.deepStrictEqual(H.rowActionNames(false, true, false), ["delete", "pin"], "images are not sent")
assert.deepStrictEqual(H.rowActionNames(true, true, true), ["send", "delete", "pin"], "1.31.0: armed delete keeps the buttons in place")

// 1.3.2: row actions by keyboard
{
  const st = (f, n, key, extra) => H.actionFocusStep(f, n, Object.assign({ key: key, ctrl: false, alt: false, shift: false, atTextEnd: true }, extra || {}))
  assert.deepStrictEqual(st(-1, 3, K.Right), { focus: 0, consumed: true, trigger: false }, "Right enters the actions")
  assert.deepStrictEqual(st(-1, 3, K.Right, { atTextEnd: false }), { focus: -1, consumed: false, trigger: false }, "Right inside the search text moves the text cursor")
  assert.strictEqual(st(0, 3, K.Right).focus, 1)
  assert.strictEqual(st(2, 3, K.Right).focus, 2, "stops at the last action")
  assert.deepStrictEqual(st(0, 3, K.Left), { focus: -1, consumed: true, trigger: false }, "Left from the first action returns to the row")
  assert.strictEqual(st(-1, 3, K.Left).consumed, false, "Left on the row edits the search")
  assert.deepStrictEqual(st(1, 3, K.Return), { focus: 1, consumed: true, trigger: true }, "Enter triggers the focused action")
  assert.strictEqual(st(-1, 3, K.Return).consumed, false, "Enter on the row pastes as usual")
  assert.deepStrictEqual(st(1, 3, K.Escape), { focus: -1, consumed: true, trigger: false }, "Esc returns to the row")
  assert.deepStrictEqual(st(1, 3, K.Down), { focus: -1, consumed: false, trigger: false }, "Down returns to the row and moves")
  assert.strictEqual(st(1, 3, K.Return, { shift: true }).trigger, false, "Shift+Enter is not an action press")
  assert.strictEqual(st(-1, 0, K.Right).focus, -1, "no actions: nothing to focus")
}

// clear button label
assert.strictEqual(H.clearLabelText(162, true), "󰩺  Clear history (162 items)")
assert.strictEqual(H.clearLabelText(162, false), "󰩺  Clear history (162)")
assert.strictEqual(H.clearLabelText(1, true), "󰩺  Clear history (1 item)")
assert.strictEqual(H.clearLabelText(-3, false), "󰩺  Clear history (0)")
assert.strictEqual(H.clearLabel(162, 200, 230, 24), "󰩺  Clear history (162 items)", "fits with gap")
assert.strictEqual(H.clearLabel(162, 200, 220, 24), "󰩺  Clear history (162)", "too tight: short")
assert.strictEqual(H.clearLabel(162, 200, 224, 24), "󰩺  Clear history (162 items)", "exact fit")

console.log("history tests: all passed")

// ---- drag reorder of pinned entries ----------------------------------------
{
  let g = [
    { type: "text", text: "a", pinned: true }, { type: "text", text: "x" },
    { type: "text", text: "b", pinned: true }, { type: "text", text: "c", pinned: true }
  ]
  const r = H.reorderPinned(g, [3, 0, 2]) // drag "c" to the top
  assert.deepStrictEqual(r.map(e => e.text), ["c", "x", "a", "b"], "pinned order follows the drag, unpinned stay")
  const rows = H.displayRows(r, "", 9)
  assert.deepStrictEqual(rows.map(x => x.slot + ":" + x.previewText), ["1:c", "2:a", "3:b", "4:x"], "Alt+N follows the new order")
  assert.deepStrictEqual(H.reorderPinned(g, [1, 0, 2]).map(e => e.text), ["a", "x", "b", "c"], "refuses unpinned index")
  assert.deepStrictEqual(H.reorderPinned(g, [0, 0, 2]).map(e => e.text), ["a", "x", "b", "c"], "refuses duplicates")
  const saved = H.parseHistory(JSON.stringify(r))
  assert.deepStrictEqual(saved.map(e => e.text), ["c", "x", "a", "b"], "order survives save/load")
  const again = H.addEntry(r, { type: "text", text: "a" }, 50)
  assert.deepStrictEqual(again.filter(e => e.pinned).map(e => e.text), ["c", "a", "b"], "re-copy keeps the dragged order")
  console.log("drag reorder: ok")
}

// ---- collapsible search header (1.9.0) -------------------------------------
assert.strictEqual(H.escapeAction("abc", true), "clear", "Esc clears a search first")
assert.strictEqual(H.escapeAction("", true), "collapse", "then collapses the empty field")
assert.strictEqual(H.escapeAction("", false), "close", "then closes the popup")
assert.strictEqual(H.searchShown("", false), false, "collapsed: title + search button")
assert.strictEqual(H.searchShown("", true), true, "button click expands")
assert.strictEqual(H.searchShown("x", false), true, "typing expands")
console.log("search header: ok")

// ---- 1.11.0 headings --------------------------------------------------------
assert.strictEqual(H.sectionName(true, 2, true, 5), "Results · 5", "searching: one Results heading")
assert.strictEqual(H.sectionName(false, 2, true, 5), "Results · 5")
assert.strictEqual(H.sectionName(true, 2, false, 9), "Pinned")
assert.strictEqual(H.sectionName(false, 2, false, 9, Date.now()), "History")
assert.strictEqual(H.sectionName(false, 0, false, 9, Date.now()), "", "no pins: no heading")
console.log("headings: ok")

// ---- 1.12.0 link / e-mail detection ---------------------------------------
{
  const L = H.linkTarget
  assert.deepStrictEqual(L("https://example.com/a?b=1"), { kind: "url", target: "https://example.com/a?b=1" })
  assert.deepStrictEqual(L("  http://x.org  "), { kind: "url", target: "http://x.org" }, "trimmed")
  assert.deepStrictEqual(L("www.example.com"), { kind: "url", target: "https://www.example.com" })
  assert.deepStrictEqual(L("roehrbacher.com"), { kind: "url", target: "https://roehrbacher.com" }, "bare domain")
  assert.deepStrictEqual(L("sub.example.at/path#x"), { kind: "url", target: "https://sub.example.at/path#x" })
  assert.deepStrictEqual(L("timon@roehrbacher.com"), { kind: "mail", target: "mailto:timon@roehrbacher.com" })
  assert.deepStrictEqual(L("mailto:a.b@x.de"), { kind: "mail", target: "mailto:a.b@x.de" })
  for (const f of ["notes.txt", "script.sh", "main.py", "README.md", "photo.png", "archive.zip", "a.b", "1.5", "v1.2.3", "file.json", "x.pdf"])
    assert.strictEqual(L(f), null, "not a link: " + f)
  for (const f of ["", "hello world", "https://x.com\nmore", "look at example.com", "user@host", "www.com", "ftp://x.com", "@x.com"])
    assert.strictEqual(L(f), null, "not a link: " + JSON.stringify(f))
  assert.deepStrictEqual(H.rowActionNames(false, true, true, "url"), ["link", "send", "delete", "pin"], "link button first (left)")
  assert.deepStrictEqual(H.rowActionNames(false, false, true, ""), ["delete", "pin"])
  assert.deepStrictEqual(H.rowActionNames(true, true, true, "url"), ["link", "send", "delete", "pin"], "1.31.0: armed keeps all")
  console.log("links: ok")
}

// ---- 1.13.0 phone / path / colour detection -------------------------------
{
  const P = H.phoneTarget
  assert.deepStrictEqual(P("+43 664 1234567"), { kind: "phone", target: "tel:+436641234567" })
  assert.deepStrictEqual(P("0043 (664) 123-45-67"), { kind: "phone", target: "tel:+436641234567" })
  assert.deepStrictEqual(P("0664/1234567"), { kind: "phone", target: "tel:06641234567" })
  assert.deepStrictEqual(P("01 5131234"), { kind: "phone", target: "tel:015131234" })
  assert.deepStrictEqual(P("tel:+4915112345678"), { kind: "phone", target: "tel:+4915112345678" })
  for (const f of ["123456", "0664 12", "01.02.2026", "2026-10-22", "12345678", "0.5", "+43 abc 123", "0664 1234567 and more", "+1234567890123456"])
    assert.strictEqual(P(f), null, "not a phone: " + f)
  const C = H.pathCandidate
  assert.strictEqual(C("/etc/hosts", "/home/t"), "/etc/hosts")
  assert.strictEqual(C("~/Work/", "/home/t"), "/home/t/Work")
  assert.strictEqual(C("~", "/home/t"), "/home/t")
  assert.strictEqual(C("file:///home/t/My%20File.txt", "/home/t"), "/home/t/My File.txt")
  assert.strictEqual(C("/home/t/with space", "/home/t"), "/home/t/with space")
  for (const f of ["relative/path", "/", "//share", "/a\n/b", "~user/x", "http://x.com/a", ""])
    assert.strictEqual(C(f, "/home/t"), "", "not a path: " + JSON.stringify(f))
  assert.strictEqual(H.pathOpenTarget("/home/t/a.txt", "f"), "/home/t", "file: parent folder")
  assert.strictEqual(H.pathOpenTarget("/home/t/Work", "d"), "/home/t/Work", "folder: itself")
  assert.strictEqual(H.pathOpenTarget("/x", "f"), "/")
  const K = H.colorTarget
  assert.deepStrictEqual(K("#ff8800"), { kind: "color", target: "#ff8800", label: "#ff8800" })
  assert.deepStrictEqual(K("#F80"), { kind: "color", target: "#ff8800", label: "#F80" })
  assert.deepStrictEqual(K("#ff880080"), { kind: "color", target: "#80ff8800", label: "#ff880080" }, "Qt #aarrggbb")
  assert.deepStrictEqual(K("rgb(255, 136, 0)"), { kind: "color", target: "#ff8800", label: "rgb(255, 136, 0)" })
  assert.deepStrictEqual(K("rgba(255,136,0,0.5)"), { kind: "color", target: "#80ff8800", label: "rgba(255,136,0,0.5)" })
  for (const f of ["#ff88", "#ggg", "rgb(256,0,0)", "ff8800", "#ff8800 text"])
    assert.strictEqual(K(f), null, "not a colour: " + f)
  const R = H.rowTarget
  assert.strictEqual(R("https://x.org", "/h").kind, "url")
  assert.strictEqual(R("#abc", "/h").kind, "color")
  assert.strictEqual(R("+43 1 5131234", "/h").kind, "phone")
  assert.deepStrictEqual(R("~/x", "/h"), { kind: "path?", target: "/h/x" })
  assert.strictEqual(R("hello", "/h"), null)
  assert.strictEqual(H.targetTooltip("url"), "Open link")
  assert.strictEqual(H.targetTooltip("mail"), "Send email")
  assert.strictEqual(H.targetTooltip("phone"), "Call number")
  assert.strictEqual(H.targetTooltip("path"), "Open in file manager")
  assert.strictEqual(H.targetTooltip("color", "#ff8800"), "Colour #ff8800")
  console.log("phone/path/colour: ok")
}

// ---- 1.13.0 maps / GitHub detection ----------------------------------------
{
  const G = H.coordTarget
  assert.deepStrictEqual(G("48.21, 16.37"), { kind: "maps", target: "48.21,16.37" })
  assert.deepStrictEqual(G("-33.8688 151.2093"), { kind: "maps", target: "-33.8688,151.2093" })
  assert.strictEqual(G(`48°12'30"N 16°22'19"E`).kind, "maps")
  assert.strictEqual(G("48° 12′ 30.5″ N, 16° 22′ 19″ E").kind, "maps")
  for (const f of ["1, 2", "48, 16", "95.1, 16.3", "48.2, 190.5", "1.5", "v1.2 3.4", `48°72'N 16°22'E`, "48.21, 16.37 x"])
    assert.strictEqual(G(f), null, "not coords: " + f)
  const A = H.addressTarget
  const yes = {
    "Neubaugasse 12, 1070 Wien": "Neubaugasse 12, 1070 Wien",
    "Hauptstraße 5/2/7\nA-3032 Eichgraben": "Hauptstraße 5/2/7, A-3032 Eichgraben",
    "Musterweg 3a, D-80331 München, Deutschland": "Musterweg 3a, D-80331 München, Deutschland",
    "Bahnhofstrasse 1, 8001 Zürich": "Bahnhofstrasse 1, 8001 Zürich",
    "1600 Amphitheatre Pkwy, Mountain View, CA 94043": "1600 Amphitheatre Pkwy, Mountain View, CA 94043",
    "350 Fifth Avenue\nNew York NY 10118": "350 Fifth Avenue, New York NY 10118",
    "10 Downing Street, London SW1A 2AA": "10 Downing Street, London SW1A 2AA",
    "221B Baker Street\nLondon\nNW1 6XE": "221B Baker Street, London, NW1 6XE",
  }
  for (const [k, v] of Object.entries(yes)) assert.deepStrictEqual(A(k), { kind: "maps", target: v }, "address: " + k)
  for (const f of ["Neubaugasse 12", "1070 Wien", "Room 12, 1070 items", "version 2, 2026 release notes are long", "call me at 5, 1234 times",
                   "Hello there 12, see you", "a,b,c,d,e,f,g", "Neubaugasse 12, 1070 Wien\nhttps://x.com", "Order 12345 Item 4, 1000 Stück=3"])
    assert.strictEqual(A(f), null, "not an address: " + JSON.stringify(f))
  assert.strictEqual(H.mapsUrl("Neubaugasse 12, 1070 Wien"), "https://www.google.com/maps/search/?api=1&query=Neubaugasse%2012%2C%201070%20Wien")
  const GH = H.githubTarget
  assert.deepStrictEqual(GH("roehrbacher/omarchy-clipboard#12"), { kind: "github", target: "https://github.com/roehrbacher/omarchy-clipboard/issues/12" })
  assert.strictEqual(GH("a-b/c.d_e#1").target, "https://github.com/a-b/c.d_e/issues/1")
  for (const f of ["-ab/repo#1", "ab-/repo#1", "a--b/repo#1", "owner/repo#0", "owner/repo #1", "owner/repo#", "owner/re po#1", "o/r/x#1", "owner/..#1", "a".repeat(40) + "/r#1", "#12", "owner#12"])
    assert.strictEqual(GH(f), null, "not GitHub: " + f)
  assert.strictEqual(H.rowTarget("owner/repo#5", "/h").kind, "github")
  assert.strictEqual(H.rowTarget("48.21, 16.37", "/h").kind, "maps")
  assert.strictEqual(H.rowTarget("Neubaugasse 12, 1070 Wien", "/h").kind, "maps")
  assert.strictEqual(H.targetTooltip("maps"), "Open in Maps")
  assert.strictEqual(H.targetTooltip("github"), "Open on GitHub")
  console.log("maps/github: ok")
}

{
  // 1.13.1: image file size
  assert.strictEqual(H.formatBytes(0), "")
  assert.strictEqual(H.formatBytes(812), "812 B")
  assert.strictEqual(H.formatBytes(250880), "245 KB")
  assert.strictEqual(H.formatBytes(1468006), "1.4 MB")
  assert.strictEqual(H.formatBytes(25 * 1024 * 1024), "25 MB")
  const img = H.normalizeEntry({ type: "image", path: "/x/a.png", mime: "image/png", capturedAt: "Thursday 20:40", bytes: 250880, screenshot: true })
  assert.strictEqual(img.bytes, 250880)
  assert.strictEqual(H.previewText(img), "Screenshot · 245 KB")
  assert.strictEqual(H.previewText(H.normalizeEntry({ type: "image", path: "/x/b.png", mime: "image/png", capturedAt: "Thursday 20:40" })), "Image", "old entries: no size, generic Image")
  assert.strictEqual(H.normalizeEntry({ type: "image", path: "/x/c.png", bytes: "junk" }).bytes, undefined)
  console.log("image size: ok")
}

{
  // 1.13.2: only real screenshots are labelled "Screenshot"
  const web = H.normalizeEntry({ type: "image", path: "/x/w.png", mime: "image/png", capturedAt: "Thursday 20:51", bytes: 76593, screenshot: false })
  assert.strictEqual(web.screenshot, undefined)
  assert.strictEqual(H.previewText(web), "Image · 75 KB")
  const shot = H.normalizeEntry({ type: "image", path: "/x/s.png", mime: "image/png", capturedAt: "Thursday 20:52", screenshot: true })
  assert.strictEqual(H.previewText(shot), "Screenshot")
  let hh = H.addEntry([], shot, 10)
  assert.strictEqual(hh[0].screenshot, true, "flag survives addEntry")
  console.log("screenshot label: ok")
}

{
  // 1.13.3: search over image rows
  const hist = [
    { type: "image", path: "/x/s.png", mime: "image/png", capturedAt: "Thursday 20:52", bytes: 76593, screenshot: true },
    { type: "image", path: "/x/w.png", mime: "image/png", capturedAt: "Thursday 20:51", bytes: 250880 },
    { type: "text", text: "hello" }
  ]
  const q = s => H.displayRows(hist, s, 50).map(r => r.previewText)
  assert.deepStrictEqual(q("screenshot"), ["Screenshot · 75 KB"], "only real screenshots")
  assert.deepStrictEqual(q("image"), ["Screenshot · 75 KB", "Image · 245 KB"], "all images")
  assert.deepStrictEqual(q("245 kb"), ["Image · 245 KB"], "by size")
  assert.deepStrictEqual(q("thursday"), ["Screenshot · 75 KB", "Image · 245 KB"], "copy day still searchable")
  console.log("image search: ok")
}

{
  // 1.14.0: day headings
  const now = new Date(2026, 9, 22, 21, 0).getTime()
  const D = (y, m, d, h) => new Date(y, m, d, h || 12).getTime()
  assert.strictEqual(H.dayLabel(D(2026, 9, 22, 0), now), "today")
  assert.strictEqual(H.dayLabel(D(2026, 9, 21, 23), now), "Yesterday")
  assert.strictEqual(H.dayLabel(D(2026, 9, 20), now), "Tue 20 Oct")
  assert.strictEqual(H.dayLabel(D(2026, 8, 30), now), "Wed 30 Sep")
  assert.strictEqual(H.dayLabel(0, now), "Earlier")
  assert.strictEqual(H.dayLabel(undefined, now), "Earlier")
  const S = H.sectionName
  assert.strictEqual(S(false, 1, false, 5, D(2026, 9, 22), now, false), "History", "today under History with pins")
  assert.strictEqual(S(false, 0, false, 5, D(2026, 9, 22), now, false), "", "no pins, one day: no heading (as before)")
  assert.strictEqual(S(false, 0, false, 5, D(2026, 9, 22), now, true), "History", "no pins but older days: History")
  assert.strictEqual(S(false, 0, false, 5, D(2026, 9, 21), now, true), "Yesterday")
  assert.strictEqual(S(true, 1, false, 5, D(2026, 9, 20), now, true), "Pinned", "no day headings in Pinned")
  assert.strictEqual(S(false, 1, true, 3, D(2026, 9, 20), now, true), "Results · 3", "no day headings while searching")
  const hist = [
    { type: "text", text: "p", pinned: true, at: D(2026, 9, 10) },
    { type: "text", text: "a", at: D(2026, 9, 22) },
    { type: "text", text: "b", at: D(2026, 9, 21) },
    { type: "text", text: "c" }
  ]
  const rows = H.displayRows(hist, "", 50)
  assert.deepStrictEqual(rows.map(r => r.at > 0), [true, true, true, false], "copy time reaches the rows")
  assert.strictEqual(H.spansDays(rows, now), true)
  assert.strictEqual(H.spansDays(rows.slice(0, 2), now), false, "pins don't count")
  assert.strictEqual(H.normalizeEntry({ type: "text", text: "x", at: 123 }).at, 123, "at persists")
  assert.strictEqual(H.normalizeEntry({ type: "text", text: "x", at: "junk" }).at, undefined)
  const big = H.displayRows([{ type: "text", text: "y".repeat(20000), at: 5 }], "", 5)
  assert.strictEqual(big[0].at, 5, "capped rows keep their time")
  console.log("day headings: ok")
}

{
  // 1.15.0: time-based auto-delete
  const DAY = 86400000, now = new Date(2026, 9, 22, 21, 0).getTime()
  assert.deepStrictEqual(H.KEEP_DAYS, [1, 2, 5, 10, 20])
  assert.strictEqual(H.DEFAULT_KEEP_DAYS, 5)
  assert.strictEqual(H.keepDaysOf(10), 10)
  assert.strictEqual(H.keepDaysOf(3), 5, "unknown value -> default")
  assert.strictEqual(H.keepDaysOf(undefined), 5)
  assert.strictEqual(H.keepDaysLabel(1), "1 day")
  assert.strictEqual(H.keepDaysLabel(20), "20 days")
  const hist = [
    { type: "text", text: "new", at: now - 1000 },
    { type: "text", text: "4d", at: now - 4 * DAY },
    { type: "text", text: "6d", at: now - 6 * DAY },
    { type: "text", text: "old pin", pinned: true, at: now - 90 * DAY },
    { type: "text", text: "untimed" }
  ]
  assert.deepStrictEqual(H.pruneByAge(hist, 5, now).map(e => e.text), ["new", "4d", "old pin", "untimed"], "5 days")
  assert.deepStrictEqual(H.pruneByAge(hist, 1, now).map(e => e.text), ["new", "old pin", "untimed"], "1 day; pins never deleted")
  assert.deepStrictEqual(H.pruneByAge(hist, 20, now).map(e => e.text), ["new", "4d", "6d", "old pin", "untimed"])
  const st = H.stampMissing(hist, now)
  assert.strictEqual(st.changed, true)
  const u = st.history[4]
  assert.strictEqual(u.at, now); assert.strictEqual(u.legacy, true)
  assert.strictEqual(hist[4].at, undefined, "input not mutated")
  assert.strictEqual(H.stampMissing(st.history, now).changed, false, "stamps once")
  // legacy items keep the "Earlier" heading and age out `days` after the upgrade
  const norm = H.normalizeEntry(u)
  assert.strictEqual(norm.legacy, true)
  const rows = H.displayRows([norm], "", 5)
  assert.strictEqual(H.dayLabel(rows[0].at, now), "Earlier")
  assert.strictEqual(H.pruneByAge([norm], 1, now + 2 * DAY).length, 0)
  console.log("auto-delete: ok")
}

// 1.16.0: search filters, OCR/QR actions
{const H=require('../ClipboardHistory.js'),a=require('assert')
const now=Date.now()
const h=[{type:"text",text:"https://x.com/a",at:now-1000,app:"chromium"},{type:"text",text:"#ff0000",at:now-3*3600e3},{type:"text",text:"hello",pinned:true,at:now-2*86400e3,app:"kitty"},
{type:"image",path:"/a.png",screenshot:true,at:now,ocr:"Rechnung Betrag 42",scanned:true},{type:"image",path:"/b.png",at:now,qr:"WIFI:T:WPA;S:Home;P:se\\;cret;;",scanned:true}]
const t=q=>H.displayRows(h,q,50).map(r=>r.index).join(",")
a.strictEqual(t("type:link"),"0");a.strictEqual(t("type:color"),"1");a.strictEqual(t("type:image"),"3,4");a.strictEqual(t("type:screenshot"),"3")
a.strictEqual(t("app:chrom"),"0");a.strictEqual(t("is:pinned"),"2");a.strictEqual(t("<2h"),"0,3,4");a.strictEqual(t("today type:text"),"0,1")
a.strictEqual(t("rechnung"),"3");a.strictEqual(t("is:pinned hello"),"2");a.strictEqual(t("today"),"0,1,3,4")
a.deepStrictEqual(H.imageTextActions(H.parseHistory(JSON.stringify(h))[4]),{link:null,copy:"se;cret",copyTip:"Copy Wi-Fi password",wifi:true,ocr:"",ocrTip:""})
const u=H.imageTextActions({type:"image",path:"/c",qr:"https://example.com/x",ocr:"foo"});a.strictEqual(u.link.kind,"url");a.strictEqual(u.ocrTip,"Copy text from image")
a.strictEqual(H.imageTextActions({type:"image",path:"/c",qr:"info@example.com"}).link.target,"mailto:info@example.com")
a.strictEqual(H.imageTextActions({type:"image",path:"/c",qr:"BEGIN:VCARD"}).copyTip,"Copy QR code text")
const re=H.addEntry(H.parseHistory(JSON.stringify(h)),{type:"image",path:"/a.png"},100);a.strictEqual(re[0].ocr,"Rechnung Betrag 42")
console.log("filters/ocr: ok")}

// ---- 1.17.0: Markdown paste, paste queue --------------------------------
{
  const html = '<p>Some <b>bold</b> <a href="https://e.x">link</a></p>'
  let m = H.addEntry([], { type: "text", text: "Some bold link", html }, 10)
  assert.strictEqual(m[0].html, html, "html kept on capture")
  assert.strictEqual(H.hasRichHtml(m[0]), true, "formatted html offers Markdown")
  assert.strictEqual(H.hasRichHtml({ type: "text", text: "x", html: "<span>x</span>" }), false, "plain html: no Markdown button")
  assert.strictEqual(H.hasRichHtml({ type: "text", text: "x" }), false, "no html: no Markdown button")
  m = H.addEntry(m, { type: "text", text: "Some bold link" }, 10)
  assert.strictEqual(m[0].html, html, "re-copy from history keeps the html")
  assert.strictEqual(H.normalizeEntry({ type: "text", text: "x", html: "a".repeat(300000) }).html, undefined, "oversized html dropped")
  const rows = H.displayRows(m, "", 10)
  assert.strictEqual(rows[0].hasMarkdown, true, "row flag")
  assert.deepStrictEqual(H.rowActionNames(false, false, true, "", false, true), ["markdown", "plaintext", "delete", "pin"], "markdown button")

  let q = []
  q = H.toggleQueued(q, "a"); q = H.toggleQueued(q, "b"); q = H.toggleQueued(q, "c")
  assert.deepStrictEqual([H.queueNumber(q, "a"), H.queueNumber(q, "b"), H.queueNumber(q, "c"), H.queueNumber(q, "z")], [1, 2, 3, 0], "order numbers")
  q = H.toggleQueued(q, "a")
  assert.deepStrictEqual([H.queueNumber(q, "b"), H.queueNumber(q, "c"), H.queueNumber(q, "a")], [1, 2, 0], "ctrl+click again removes, rest move up")
  assert.deepStrictEqual(H.queueItems([{ type: "text", text: "t", html: "<b>t</b>", app: "x", at: 1 }, { type: "image", path: "/p.png", mime: "image/png", ocr: "o" }, null]),
    [{ type: "text", text: "t" }, { type: "image", path: "/p.png", mime: "image/png" }], "queue items carry only what is pasted")
  assert.strictEqual(H.queueButtonLabel(3, null), "Paste queue: 3 items in order", "1.20.0: short info line (fits, no ...)"); assert.strictEqual(H.queueButtonLabel(1, null), "", "1 selected: no queue")
  assert.strictEqual(H.queueButtonLabel(0, { pos: 1, count: 5 }), "Pasting 2 of 5 · Cancel")
  assert.strictEqual(H.queueButtonLabel(0, null), "")
  const K = H.KEY || { Escape: 0x01000000, Return: 0x01000004 }
  assert.strictEqual(H.searchKeyAction({ key: 0x20, ctrl: true }), "queueToggle", "Ctrl+Space")
  assert.strictEqual(H.searchKeyAction({ key: 0x01000004, ctrl: true, queued: 2 }), "enter", "1.19.0: Ctrl+Enter no longer starts")
  assert.strictEqual(H.searchKeyAction({ key: 0x01000004, ctrl: true, queued: 0 }), "enter", "Ctrl+Enter without queue = Enter")
  assert.strictEqual(H.searchKeyAction({ key: 0x01000000, queued: 2 }), "queueClear", "Esc clears the selection first")
  assert.strictEqual(H.searchKeyAction({ key: 0x01000000, queued: 0 }), "escape")
  console.log("markdown/queue: ok")
}

// ---- 1.18.0: QR previews, click action, drag between sections ----------
{
  const img = q => ({ type: "image", path: "/x.png", mime: "image/png", bytes: 2048, qr: q, scanned: true, scanv: 2 })
  assert.strictEqual(H.previewText(img("WIFI:T:WPA;S:ExampleNet;P:not-real;;")), "Wi-Fi name: ExampleNet")
  assert.deepStrictEqual(H.imageTextActions(img("WIFI:T:WPA;S:ExampleNet;P:not-real;;")), { link: null, copy: "not-real", copyTip: "Copy Wi-Fi password", wifi: true, ocr: "", ocrTip: "" })
  assert.strictEqual(H.previewText(img("https://example.com/menu")), "QR link: example.com/menu")
  assert.strictEqual(H.imageTextActions(img("https://example.com/menu")).link.kind, "url")
  assert.strictEqual(H.previewText(img("mailto:someone@example.org")), "QR e-mail: someone@example.org")
  assert.strictEqual(H.imageTextActions(img("MATMSG:TO:someone@example.org;SUB:Hi;;")).link.target, "mailto:someone@example.org")
  assert.strictEqual(H.previewText(img("Locker 12, code 0000")), "QR: Locker 12, code 0000")
  assert.strictEqual(H.previewText({ type: "image", path: "/s.png", screenshot: true, bytes: 2048 }), "Screenshot · 2 KB")
  assert.strictEqual(H.imageTextActions({ type: "image", path: "/s", ocr: "x", screenshot: true }).ocrTip, "Copy text from screenshot")
  assert.strictEqual(H.imageTextActions({ type: "image", path: "/s", ocr: "x" }).ocrTip, "Copy text from image")
  assert.strictEqual(H.needsScan({ type: "image", path: "/a", scanned: true }), true, "zbar-only scans are redone")
  assert.strictEqual(H.needsScan(H.normalizeEntry({ type: "image", path: "/a", scanned: true, scanv: 3 })), false)
  assert.strictEqual(H.needsScan(H.normalizeEntry({ type: "image", path: "/a", scanned: true, scanv: 2 })), true, "1.20.0: v2 scans redone once (QR mask, junk filter)")
  assert.strictEqual(H.clickActionOf("copy"), "copy"); assert.strictEqual(H.clickActionOf(undefined), "paste")
  // 2 pinned + 4 history rows; drag history row 4 up: pinned at slot 1, back down: home again
  assert.deepStrictEqual(H.dragPlan(1, 2, 6, false, 4), { index: 1, pinned: true })
  assert.deepStrictEqual(H.dragPlan(2, 2, 6, false, 4), { index: 2, pinned: true }, "right under the last pin is still pinned")
  assert.deepStrictEqual(H.dragPlan(3, 2, 6, false, 4), { index: 4, pinned: false })
  // pinned row 0 (1 other pin) dragged into history: unpinned, shown under Pinned
  assert.deepStrictEqual(H.dragPlan(4, 1, 6, true, 0), { index: 1, pinned: false })
  assert.deepStrictEqual(H.dragPlan(0, 1, 6, true, 0), { index: 0, pinned: true })
  assert.ok(H.SEARCH_FILTER_EXAMPLES.length === 11 && H.SEARCH_FILTER_EXAMPLES.some(f => f.value === "app:firefox"))
  console.log("qr/click/drag: ok")
}

// ---- 1.19.0 ----------------------------------------------------------------
{
  const both = H.imageTextActions({ type: "image", path: "/q.png", qr: "WIFI:T:WPA;S:ExampleNet;P:not-real;;", ocr: "Guest network", screenshot: true })
  assert.deepStrictEqual([both.copy, both.wifi, both.ocr, both.ocrTip], ["not-real", true, "Guest network", "Copy text from screenshot"], "QR + OCR: both")
  const url = H.imageTextActions({ type: "image", path: "/q.png", qr: "https://example.com", ocr: "Menu" })
  assert.deepStrictEqual([url.link.kind, url.ocrTip], ["url", "Copy text from image"])
  assert.deepStrictEqual(H.rowActionNames(false, false, false, "url", true, false, true), ["link", "copytext", "ocrtext", "delete", "pin"])
  assert.strictEqual(H.queueOnPick(1), false); assert.strictEqual(H.queueOnPick(2), true)
  assert.deepStrictEqual(H.queueItemKeys([{ type: "text", text: "a" }, { type: "image", path: "/i/x.png" }]), ["text:a", "image:/i/x.png"])
  const sha = "a".repeat(64)
  assert.strictEqual(H.clipKeyOf({ type: "image", path: "/d/images/" + sha + ".png" }, null), "image:" + sha)
  assert.strictEqual(H.clipKeyOf({ type: "text", text: "hi" }, t => "md5(" + t + ")"), "text:md5(hi)")
  let h = [{ type: "text", text: "new", at: 5000 }, { type: "text", text: "old pin", pinned: true, at: 1 }, { type: "text", text: "older", at: 100 }]
  h = H.unpinToTop(h, 1, 9999)
  assert.deepStrictEqual(h.map(e => e.text + (e.pinned ? "*" : "") + "@" + e.at), ["old pin@9999", "new@5000", "older@100"], "unpinned goes to the top of History, now")
  assert.strictEqual(H.displayRows(h, "", 10)[0].fullText, "old pin")
  console.log("1.19.0: ok")
}

// 1.20.0: OCR language list and the empty-clipboard fill.
{
  const rows = H.ocrAvailableRows([], {})
  assert.strictEqual(rows.length, 16, "16 popular languages")
  assert.deepStrictEqual(rows.map(r => r.code).sort(), ["eng","deu","fra","spa","ita","por","nld","pol","ces","tur","rus","ukr","chi_sim","jpn","kor","ara"].sort(), "Arch package codes")
  assert.strictEqual(H.ocrLanguageName("chi_sim"), "Chinese (simplified)", "Chinese simplified = chi_sim")
  const now = Date.now()
  const hist = [{ type: "text", text: "newest", at: now }, { type: "text", text: "pin top", pinned: true, at: now - 5 }, { type: "text", text: "pin 2", pinned: true, at: now - 9 }]
  assert.strictEqual(H.firstPinnedIndex(hist), 1, "top pinned row's history index")
  assert.strictEqual(H.firstPinnedIndex([{ type: "text", text: "a", at: now }]), -1, "no pinned item: nothing")
  assert.strictEqual(H.firstPinnedIndex([]), -1, "empty history: nothing")
  console.log("ok 1.20.0 OCR language rows + first pinned")
}

{
  // 1.25.0: OCR notification preview
  assert.strictEqual(H.ocrPreview("  Hello\n\n  world\t!  "), "“Hello world !”", "whitespace collapsed to one line")
  const long = H.ocrPreview("a".repeat(300), 120)
  assert.strictEqual(Array.from(long).length, 120 + 2, "cut to 120 chars incl. … plus quotes")
  assert.ok(long.endsWith("…”"), "ellipsis at the end")
  assert.strictEqual(H.ocrPreview("x".repeat(120), 120), "“" + "x".repeat(120) + "”", "exactly 120: no ellipsis")
  assert.strictEqual(H.ocrPreview("a <b>bold</b> & c"), "“a &lt;b&gt;bold&lt;/b&gt; &amp; c”", "markup escaped")
  assert.strictEqual(H.ocrPreview("--exec"), "“--exec”", "never starts with a dash")
  assert.strictEqual(H.ocrPreview("word ".repeat(10), 12), "“word word w…”", "custom length")
  const emoji = H.ocrPreview("😀".repeat(200), 5)
  assert.strictEqual(emoji, "“😀😀😀😀…”", "no broken surrogate pairs")
  console.log("ok 1.25.0 OCR preview")
}

{
  // 1.26.0: clear counts unpinned only
  const hist = [
    { type: "text", text: "p1", pinned: true }, { type: "text", text: "p2", pinned: true },
    { type: "text", text: "p3", pinned: true }, { type: "text", text: "p4", pinned: true },
    { type: "text", text: "h1" }, { type: "text", text: "h2" }, { type: "text", text: "h3" }
  ]
  assert.strictEqual(H.unpinnedCount(hist), 3, "3 history + 4 pinned: clear deletes 3")
  assert.strictEqual(H.pinnedCount(hist), 4)
  assert.strictEqual(H.clearLabelText(H.unpinnedCount(hist), true), "󰩺  Clear history (3 items)", "label counts unpinned only")
  assert.deepStrictEqual(H.clearHistory(hist).map(e => e.text), ["p1", "p2", "p3", "p4"], "clearing keeps every pin")
  assert.strictEqual(H.unpinnedCount(H.clearHistory(hist)), 0, "nothing left to clear afterwards")
  assert.strictEqual(H.phoneGlyph("online").codePointAt(0), 0xF17FD, "connected: cellphone-check")
  assert.strictEqual(H.phoneGlyph("nophone").codePointAt(0), 0xF0950, "not connected: cellphone-off")
  console.log("ok 1.26.0 clear count, phone glyph")
}

{
  // 1.27.0: OCR language suggestions from locale / keyboard layout / dictionaries
  const L = H.ocrHintLanguage
  assert.deepStrictEqual(L("de_AT.UTF-8"), { code: "deu", source: "locale" })
  assert.deepStrictEqual(L("de"), { code: "deu", source: "locale" }, "LANGUAGE entries have no country")
  assert.deepStrictEqual(L("sr_RS@latin"), null, "unknown language: no suggestion")
  assert.deepStrictEqual(L("C.UTF-8"), null)
  assert.deepStrictEqual(L("POSIX"), null)
  assert.deepStrictEqual(L("kb:at"), { code: "deu", source: "kb" }, "Austrian layout = German")
  assert.deepStrictEqual(L("kb:ch"), { code: "deu", source: "kb" })
  assert.deepStrictEqual(L("kb:br"), { code: "por", source: "kb" })
  assert.deepStrictEqual(L("kb:us"), { code: "eng", source: "kb" })
  assert.deepStrictEqual(L("kb:de(nodeadkeys)"), { code: "deu", source: "kb" }, "variant in parentheses")
  assert.deepStrictEqual(L("dict:fr_FR"), { code: "fra", source: "dict" })
  assert.deepStrictEqual(L("zh_CN.UTF-8"), { code: "chi_sim", source: "locale" })
  assert.deepStrictEqual(L("cs_CZ.UTF-8"), { code: "ces", source: "locale" })
  assert.deepStrictEqual(L(""), null)
  const hints = ["en_US.UTF-8", "de_AT.UTF-8", "kb:us", "kb:at", "dict:de_AT", "dict:fr_FR"]
  const s = H.ocrSuggestions(hints, ["eng"], [])
  assert.deepStrictEqual(s.map(x => x.code), ["deu", "fra"], "English never, German once, in hint order")
  assert.strictEqual(s[0].cmd, "sudo pacman -S tesseract-data-deu")
  assert.strictEqual(s[0].text, "Looks like you also use German (your language settings). Install OCR for it?")
  assert.strictEqual(s[1].source, "a spell-check dictionary")
  assert.deepStrictEqual(H.ocrSuggestions(["kb:at"], ["eng"], []).map(x => x.source), ["your keyboard layout"])
  assert.deepStrictEqual(H.ocrSuggestions(hints, ["eng", "deu"], []).map(x => x.code), ["fra"], "installed packs are not suggested")
  assert.deepStrictEqual(H.ocrSuggestions(hints, ["eng"], ["deu"]).map(x => x.code), ["fra"], "dismissed ones stay hidden")
  assert.deepStrictEqual(H.ocrSuggestions(undefined, undefined, undefined), [], "no hints: nothing")
  assert.deepStrictEqual(H.ocrDismissedOf(["deu", "x; rm", 3, "chi_sim"]), ["deu", "chi_sim"])
  assert.deepStrictEqual(H.ocrDismissedOf("deu"), [])
  console.log("ok 1.27.0 OCR language suggestions")
}

{
  // 1.27.0: direct feedback payload and replies
  assert.deepStrictEqual(JSON.parse(H.feedbackPayload("  hi there \n", "1.27.0")), { message: "hi there", version: "1.27.0", website: "" })
  assert.deepStrictEqual(H.feedbackResultFromCurl('{"ok":true}\n0'), { ok: true, note: "Feedback sent, thanks! Timon reads every message." })
  assert.strictEqual(H.feedbackResultFromCurl('{"ok":false,"error":"slow down"}\n0').note, "Too many: try again in a minute")
  assert.strictEqual(H.feedbackResultFromCurl('{"ok":false,"error":"too long"}\n0').ok, false)
  assert.strictEqual(H.feedbackResultFromCurl('\n6').note, "Not sent: offline? Text kept", "DNS failure")
  assert.strictEqual(H.feedbackResultFromCurl('\n28').ok, false, "timeout")
  assert.strictEqual(H.feedbackResultFromCurl('<html>502</html>\n0').ok, false, "non-JSON reply")
  assert.strictEqual(H.feedbackResultFromCurl('').ok, false)
  console.log("ok 1.27.0 direct feedback")
}

{
  // OCR preview: truncated ones end with …” (1.28.0); limit 120 again (1.29.0)
  const inv = "Invoice number 2026-11-0042 due on 30 November. Please transfer the amount to the account below and quote the number as reference."
  const p = H.ocrPreview(inv)
  assert.ok(p.startsWith("“") && p.endsWith("…”"), "truncated preview keeps the closing quote after the ellipsis: " + p)
  assert.ok(Array.from(H.ocrPreview(inv + " " + inv)).length === 120 + 2, "default limit 120 (+ quotes)")
  assert.ok(!/\s…/.test(p), "no space before the ellipsis")
  assert.strictEqual(H.ocrPreview("short text"), "“short text”", "short: quotes, no ellipsis")
  assert.ok(H.ocrPreview("a & b ".repeat(40)).endsWith("…”"), "escaping does not eat the quote")

  // 1.28.0: OCR languages sorted by name; install argv only for plain codes
  const names = H.ocrAvailableRows(["eng"], {}).map(r => r.name)
  assert.deepStrictEqual(names, names.slice().sort(), "alphabetical by shown name")
  assert.strictEqual(names[0], "Arabic"); assert.strictEqual(names[names.length - 1], "Ukrainian")
  const script = "/home/u/.config/omarchy/plugins/timon.clipboard/ocr-install.sh"
  const argv = H.ocrInstallArgv("deu", script, "German")
  assert.strictEqual(argv[0], "bash"); assert.strictEqual(argv[1], "-c")
  assert.ok(argv[2].includes("--app-id=org.omarchy.terminal") && argv[2].includes("uwsm-app"), "Omarchy floating terminal")
  assert.ok(!argv[2].includes("deu") && !argv[2].includes("omarchy-pkg-add"), "code passed as argv, own script, no omarchy-pkg-add")
  assert.deepStrictEqual(argv.slice(3), [script, "deu", "German"])
  assert.deepStrictEqual(H.ocrInstallArgv("deu", script, "German", true).slice(3), [script, "--remove", "deu", "German"], "1.31.0 remove")
  assert.deepStrictEqual(H.ocrInstallArgv("deu", ""), [], "needs the script path")
  for (const bad of ["", "de", "deu; rm -rf ~", "deu'", "DEU", "../x", "deu fra"]) assert.deepStrictEqual(H.ocrInstallArgv(bad, script), [], "rejected: " + bad)

  // 1.29.0: Alt+Shift+1…9, 0 = 10 slots: pins first, then newest history
  const hist = [{ text: "h0" }, { text: "p1", pinned: true }, { text: "h2" }, { text: "p2", pinned: true }, { text: "p3", pinned: true }]
  assert.deepStrictEqual([1, 2, 3, 4, 5, 6].map(n => H.slotHistoryIndex(hist, n)), [1, 3, 4, 0, 2, -1])
  assert.strictEqual(H.slotHistoryIndex(hist, 0), -1); assert.strictEqual(H.slotHistoryIndex(hist, 11), -1)
  assert.strictEqual(H.slotHint(hist, 3), "Alt+Shift+2", "pinned row")
  assert.strictEqual(H.slotHint(hist, 0), "Alt+Shift+4", "newest history row after 3 pins")
  const nine = Array.from({ length: 9 }, (_, i) => ({ text: "p" + i, pinned: true })).concat([{ text: "new" }, { text: "old" }])
  assert.strictEqual(H.slotHistoryIndex(nine, 10), 9, "9 pins: Alt+Shift+0 = newest history item")
  assert.strictEqual(H.slotHint(nine, 9), "Alt+Shift+0"); assert.strictEqual(H.slotHint(nine, 10), "", "11th row has no slot")
  const four = Array.from({ length: 4 }, (_, i) => ({ text: "p" + i, pinned: true })).concat(Array.from({ length: 8 }, (_, i) => ({ text: "h" + i })))
  assert.deepStrictEqual([5, 6, 7, 8, 9, 10].map(n => H.slotHistoryIndex(four, n)), [4, 5, 6, 7, 8, 9], "4 pins: Alt+Shift+5…9, 0 = history 1…6")
  const twelve = Array.from({ length: 12 }, (_, i) => ({ text: "p" + i, pinned: true }))
  assert.strictEqual(H.slotHint(twelve, 9), "Alt+Shift+0"); assert.strictEqual(H.slotHint(twelve, 10), "", "pins past 10 have no key")
  assert.strictEqual(H.slotFromKey(10, 0x21), 1, "keycode 10 = the 1 key, whatever Shift makes of it")
  assert.strictEqual(H.slotFromKey(19, 0x3d), 10, "keycode 19 = the 0 key = slot 10")
  assert.strictEqual(H.slotFromKey(0, 0x35), 5); assert.strictEqual(H.slotFromKey(0, 0x30), 10); assert.strictEqual(H.slotFromKey(38, 0x61), 0)
  assert.strictEqual(H.searchKeyAction({ key: 0x22, slot: 2, alt: true, ctrl: false, shift: true }), "slot", "Alt+Shift+2")
  assert.strictEqual(H.searchKeyAction({ key: 0x32, slot: 2, alt: true, ctrl: false, shift: false }), "ignore", "plain Alt+2 does nothing")
  assert.strictEqual(H.searchKeyAction({ key: 0x22, slot: 2, alt: true, ctrl: true, shift: true }), "", "not with Ctrl")

  // 1.29.0: global shortcuts summary (global-keys.sh output)
  const gk = H.globalKeysSummary("Alt+V\ttaken\tClipboard history\n" + [1,2,3,4,5,6,7,8,9].map(n => "Alt+Shift+" + n + "\ttaken\tPaste pinned clipboard item " + n).join("\n") + "\nAlt+Shift+0\tbound\t\n")
  assert.strictEqual(gk.text, "Active: Alt+Shift+0. Already bound in your Hyprland config, left alone: Alt+V, Alt+Shift+1–9")
  assert.strictEqual(H.globalKeysSummary("Alt+V\tours\t\nAlt+Shift+1\tbound\t\nAlt+Shift+2\tbound\t").text, "Active: Alt+V, Alt+Shift+1, 2")
  assert.deepStrictEqual(H.globalKeysSummary("all\terror\tHyprland did not answer").errors, ["Hyprland did not answer"])
  assert.strictEqual(H.keyLabels(["Alt+Shift+9", "Alt+Shift+0", "Alt+Shift+1"]), "Alt+Shift+1, 9, 0")
  assert.strictEqual(H.keyLabels(["Alt+V"].concat([1,2,3,4,5,6,7,8,9,0].map(n => "Alt+Shift+" + n))), "Alt+V, Alt+Shift+1–0", "1.32.0: all ten read 1–0")

  // 1.29.0: feedback sent wording, dev demo banner
  assert.strictEqual(H.feedbackResult(0, '{"ok":true}').note, "Feedback sent, thanks! Timon reads every message.")
  const demo = H.ocrDemoSuggestion(["eng", "deu", "spa"], "any")
  assert.strictEqual(demo.code, "fra", "first not installed language"); assert.ok(demo.text.includes("demo"))
  assert.strictEqual(H.ocrDemoSuggestion(["eng"], "ita").code, "ita")
  assert.strictEqual(H.ocrDemoSuggestion(["eng", "ita"], "ita").code, "deu", "installed one is skipped")
  console.log("ok 1.28.0/1.29.0 OCR preview, sorted languages, install argv, Alt+Shift slots, feedback, demo banner")

  // 1.30.0: no GitHub fallback in feedback notes, Enter sends
  assert.ok(!H.feedbackResult(0, '<html>').note.includes("GitHub"), "no Ctrl+Shift+Enter hint")
  assert.strictEqual(H.feedbackResult(0, '<html>').ok, false)
  assert.strictEqual(H.feedbackKey(0x01000004, false, false), "send", "Enter")
  assert.strictEqual(H.feedbackKey(0x01000005, false, false), "send", "keypad Enter")
  assert.strictEqual(H.feedbackKey(0x01000004, true, false), "newline", "Shift+Enter")
  assert.strictEqual(H.feedbackKey(0x01000004, false, true), "send", "Ctrl+Enter still sends")
  assert.strictEqual(H.feedbackKey(0x41, false, false), "", "letters type")
  assert.strictEqual(H.feedbackUrl, undefined)
  // 1.30.0: OCR pack sizes from pacman, never guessed
  const sz = { deu: { download: "5.94 MiB", installed: "14.72 MiB" }, deu_frak: { download: "752.64 KiB", installed: "1932.36 KiB" }, bad: { download: "?", installed: "" } }
  const mb = v => H.megabytes(H.pacmanBytes(v))
  assert.strictEqual(mb(sz.deu.installed), "15 MB")
  assert.strictEqual(mb(sz.deu.download), "6.2 MB")
  assert.strictEqual(mb(sz.deu_frak.download), "0.8 MB")
  assert.strictEqual(mb(sz.bad.download), "", "unknown = nothing")
  assert.strictEqual(mb(""), "")
  assert.strictEqual(H.pacmanBytes("1.50 GiB"), 1.5 * 1073741824)
  // 1.30.0: update check helpers
  assert.strictEqual(H.versionNewer("1.31.0", "1.30.0"), true)
  assert.strictEqual(H.versionNewer("v1.30.1", "1.30.0"), true)
  assert.strictEqual(H.versionNewer("1.30.0", "1.30.0"), false)
  assert.strictEqual(H.versionNewer("1.9.0", "1.30.0"), false, "numeric, not string compare")
  assert.strictEqual(H.versionNewer("", "1.30.0"), false)
  assert.strictEqual(H.versionNewer("latest", "1.30.0"), false)
  assert.strictEqual(H.updateCheckDue(0, 5e9), true)
  assert.strictEqual(H.updateCheckDue(1e9, 1e9 + 3600), false, "not twice a day")
  assert.strictEqual(H.updateCheckDue(1e9, 1e9 + 86400), true)
  assert.strictEqual(H.updateCheckDue(1e9, 1e9 - 10), true, "clock went back")
  assert.ok(H.updateHowTo(true).includes("omarchy plugin update timon.clipboard"))
  assert.ok(H.updateHowTo(false).includes("GitHub page"))
  console.log("ok 1.30.0 feedback keys, OCR sizes, update check")

  // 1.31.0: undo delete
  const h0 = [{ type: "text", text: "a" }, { type: "text", text: "p", pinned: true }, { type: "text", text: "b" }]
  let st = H.pushUndo([], h0[1], 1)
  const h1 = H.removeEntryAt(h0, 1)
  const r = H.restoreEntry(h1, st[st.length - 1])
  assert.deepStrictEqual(r.history, h0, "back at its place, still pinned"); assert.strictEqual(r.index, 1)
  const r2 = H.restoreEntry([{ type: "text", text: "p" }, { type: "text", text: "a" }], { entry: h0[1], index: 1 })
  assert.deepStrictEqual(r2.history.map(e => e.text), ["a", "p"], "a newer copy of the same item is replaced, not doubled")
  assert.strictEqual(H.restoreEntry([], { entry: h0[0], index: 9 }).index, 0, "index clamped")
  for (let i = 0; i < 15; i++) st = H.pushUndo(st, { type: "text", text: "x" + i }, 0)
  assert.strictEqual(st.length, 10, "keeps the last 10"); assert.strictEqual(st[st.length - 1].entry.text, "x14")
  assert.strictEqual(H.deleteAction(true, false), "arm", "button click / pinned: arm first")
  // 1.31.0: OCR language rows
  const packs = { eng: { installed: "22.38 MiB", requiredBy: ["omasnap", "tesseract"] }, deu: { installed: "14.72 MiB", download: "5.94 MiB", requiredBy: ["tesseract"] }, ita: { installed: "15.21 MiB", requiredBy: ["tesseract"] }, fra: { download: "5.11 MiB" } }
  const rows = H.ocrInstalledRows(["deu", "eng", "ita"], packs, ["ita"], "")
  assert.deepStrictEqual(rows.map(x => x.name), ["English", "German", "Italian"])
  assert.strictEqual(rows[0].protect, "Needed by omasnap"); assert.strictEqual(rows[1].protect, "")
  assert.strictEqual(rows[1].size, "15 MB"); assert.strictEqual(rows[2].inUse, false); assert.strictEqual(rows[0].inUse, true)
  assert.strictEqual(H.ocrInstalledRows(["deu"], packs, [], "")[0].protect, "Tesseract needs at least one language")
  assert.strictEqual(H.ocrInstalledRows(["deu", "eng"], packs, ["eng"], "")[0].toggleNote, "", "off one can be turned on")
  assert.strictEqual(H.ocrInstalledRows(["deu", "eng"], packs, ["eng"], "")[1].toggleNote, "At least one language stays on")
  assert.strictEqual(H.ocrInstalledRows(["deu", "eng"], packs, [], "deu")[0].inUse, false, "OMARCHY_OCR_LANGS decides")
  assert.ok(H.ocrAvailableRows(["deu", "eng", "ita"], packs).every(x => ["deu", "eng", "ita"].indexOf(x.code) < 0), "only not installed ones to add")
  assert.strictEqual(H.ocrAvailableRows(["deu"], packs).find(x => x.code === "fra").size, "5.4 MB", "download size")
  assert.deepStrictEqual(H.toggleOcrOff([], "ita", ["eng", "ita"]), ["ita"])
  assert.deepStrictEqual(H.toggleOcrOff(["ita"], "ita", ["eng", "ita"]), [])
  assert.deepStrictEqual(H.toggleOcrOff(["ita"], "eng", ["eng", "ita"]), ["ita"], "last one stays on")
  assert.deepStrictEqual(H.toggleOcrOff(["spa"], "ita", ["eng", "ita"]), ["ita"], "stale codes dropped")
  const un = H.uninstallArgv("/p/uninstall.sh", true)
  assert.deepStrictEqual(un.slice(3), ["/p/uninstall.sh", "--languages"]); assert.ok(un[2].includes("org.omarchy.terminal"))
  assert.deepStrictEqual(H.uninstallArgv("/p/uninstall.sh", false).slice(3), ["/p/uninstall.sh"])
  console.log("ok 1.31.0 undo delete, OCR language rows, uninstall argv")
}

// 1.32.0 / 1.33.0: left click setting (pasteKeep migrates), clear count, hero meta, phone quarantine
{
  assert.strictEqual(H.clickActionOf("copy"), "copy"); assert.strictEqual(H.clickActionOf("paste"), "paste")
  assert.strictEqual(H.clickActionOf(undefined), "paste", "new installs: select, paste & close")
  assert.strictEqual(H.clickActionOf("pasteKeep"), "paste", "1.32's keep-open setting goes back to the default")
  assert.strictEqual(H.clearHistoryLabel(3), "Clear history: delete 3 items (pins stay)")
  assert.strictEqual(H.clearHistoryLabel(1), "Clear history: delete 1 item (pins stay)")
  assert.strictEqual(H.clearHistoryLabel(0), "Clear history (nothing to delete, pins stay)")
  assert.strictEqual(H.heroMetaLabel(54, 3), "54 items · 3 pinned"); assert.strictEqual(H.heroMetaLabel(1, 0), "1 item")
  assert.strictEqual(H.fluxQuarantineActive(0, 0, 1000), false, "never paused")
  assert.strictEqual(H.fluxQuarantineActive(1000, 0, 2000), true, "resumed, phone not back yet")
  assert.strictEqual(H.fluxQuarantineActive(1000, 3000, 7000), true, "phone back < 5 s ago")
  assert.strictEqual(H.fluxQuarantineActive(1000, 3000, 9000), false, "phone back > 5 s ago")
  assert.strictEqual(H.fluxQuarantineActive(1000, 0, 1000 + 600001), false, "10 min cap")
  console.log("1.32.0: ok")
}

// 1.32.2: the end of a terminal OCR job, as ocr-install.sh reports it.
{
  const end = (o, installing, removing, started) => H.ocrJobEnded(JSON.stringify(o), installing, removing, started)
  assert.deepStrictEqual(end({ code: "ita", remove: true, rc: 130, at: 100 }, "", "ita", 100), { job: "remove", ok: false }, "cancelled removal")
  assert.deepStrictEqual(end({ code: "fra", remove: false, rc: 0, at: 105 }, "fra", "", 100), { job: "install", ok: true }, "finished install")
  assert.deepStrictEqual(end({ code: "eng", remove: true, rc: 3, at: 105 }, "", "eng", 100), { job: "remove", ok: false }, "refused removal")
  assert.strictEqual(end({ code: "fra", remove: false, rc: 1, at: 99 }, "fra", "", 100), null, "file from before this job")
  assert.strictEqual(end({ code: "deu", remove: false, rc: 1, at: 105 }, "fra", "", 100), null, "another language")
  assert.strictEqual(end({ code: "fra", remove: true, rc: 1, at: 105 }, "fra", "", 100), null, "install running, removal reported")
  assert.strictEqual(end({ code: "fra", remove: false, rc: 1, at: 105 }, "", "", 100), null, "nothing running")
  assert.strictEqual(H.ocrJobEnded("not json", "fra", "", 0), null)
  assert.strictEqual(H.ocrJobEnded("", "fra", "", 0), null)
  console.log("1.32.2: ok")
}

// 1.33.1: typing in the feedback box while a send is on its way. After the
// Worker confirmed, only the text that was sent leaves the field.
{
  assert.strictEqual(H.feedbackLeftAfterSend("hello", "hello"), "", "nothing typed meanwhile: field empties")
  assert.strictEqual(H.feedbackLeftAfterSend("hello and a second thought", "hello"), "and a second thought", "words typed after Send stay")
  assert.strictEqual(H.feedbackLeftAfterSend("hello\nmore", "hello"), "more")
  assert.strictEqual(H.feedbackLeftAfterSend("hi hello", "hello"), "hi hello", "edited elsewhere: kept whole")
  assert.strictEqual(H.feedbackLeftAfterSend("", "hello"), "", "cleared meanwhile: stays empty")
  console.log("1.33.1: ok")
}
