#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## Tests for editor_frame.nim

import std/[unittest, os]

import pkg/celina

import ../src/moepkg/[types, editor, config, message_log]
import ../src/moepkg/[highlight, editor_frame]
import ../src/moepkg/buffer {.all.}

suite "notify - routing and logging":
  test "status line route sets the status message":
    let config = newEditorConfig()
    let e = newEditor(config)
    e.config.notification.popupNotifications = false
    clearMessageLog()

    e.notify("hello")

    check e.state.statusMessage == "hello"
    check e.state.notificationPopup.queue.len == 0

  test "popup route queues the message with its level":
    let config = newEditorConfig()
    let e = newEditor(config)
    e.config.notification.popupNotifications = true
    e.state.setStatusQuiet("")
    clearMessageLog()

    e.notify("Build error: boom", nlError)

    check e.state.notificationPopup.queue.len == 1
    check e.state.notificationPopup.queue[0].message == "Build error: boom"
    check e.state.notificationPopup.queue[0].level == nlError
    check e.state.statusMessage.len == 0

  test "both routes record to the message log":
    # What the log holds must not depend on a display preference: with popups
    # on, the status-line setter (which logs) is bypassed.
    for popups in [false, true]:
      let config = newEditorConfig()
      let e = newEditor(config)
      e.config.notification.popupNotifications = popups
      clearMessageLog()

      e.notify("QuickRun error: boom", nlError)

      check getMessageLog().len == 1
      check getMessageLog()[0] == "QuickRun error: boom"

  test "empty message is not logged":
    let config = newEditorConfig()
    let e = newEditor(config)
    e.config.notification.popupNotifications = false
    clearMessageLog()

    e.notify("")

    check getMessageLog().len == 0

suite "updateForFrame - split buffer re-parse budget":
  test "advances in-flight re-parses of inactive buffers across frames":
    let config = newEditorConfig()
    let e = newEditor(config)

    # Second buffer with a large Rust file and an in-flight re-parse; it is
    # registered in e.buffers but is not the active buffer.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_split.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 5000:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    e.addBuffer(buf)

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    # Start the flight (as the render pass would for a visible split buffer).
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil

    let frameBuffer = newBuffer(80, 24)
    let oldFrontier = buf.incrementalHighlight.pendingReparse.reparseEnd
    # The frame must advance the inactive buffer's re-parse from its loop, not
    # wait for the buffer to become active again.
    discard e.updateForFrame(frameBuffer)
    check buf.incrementalHighlight.pendingReparse != nil
    check buf.incrementalHighlight.pendingReparse.reparseEnd > oldFrontier

    var frames = 1
    while buf.incrementalHighlight.pendingReparse != nil and frames < 100:
      discard e.updateForFrame(frameBuffer)
      inc frames
    check frames < 100
    check buf.incrementalHighlight.pendingReparse == nil
    check buf.incrementalHighlight.lineStates.states.len == buf.len
    # The per-frame URI scan keeps the inactive buffer's underlines current;
    # it is clamped to the syntax progress, so the loop must also drive the
    # initial-load resume, or the tail rows never get scanned.
    var uriFrames = 1
    while buf.uriScanParsedUpTo < buf.len - 1 and uriFrames < 100:
      discard e.updateForFrame(frameBuffer)
      inc uriFrames
    check uriFrames < 100
    check buf.uriScanParsedUpTo == buf.len - 1

  test "a new edit mid-re-parse restarts the inactive buffer's flight":
    let config = newEditorConfig()
    let e = newEditor(config)

    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_restart.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 5000:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    e.addBuffer(buf)

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    let oldAnchor = buf.incrementalHighlight.pendingReparse.anchor

    let frameBuffer = newBuffer(80, 24)
    # A second edit lands while the re-parse is in flight: the next frame's
    # trigger must restart from the new anchor, not resume from the old
    # frontier, so the pre-edit rows are re-parsed.
    discard buf.beginTransaction()
    discard buf.insert(1000, "let second = 1;")
    discard buf.commitTransaction()
    discard e.updateForFrame(frameBuffer)

    let pr = buf.incrementalHighlight.pendingReparse
    check pr != nil
    check pr.anchor == 1000
    check pr.anchor != oldAnchor
    check pr.lineCount == buf.len
    # The restart rewinds to the discarded flight's start (its rows below the
    # new anchor have no valid segments), not to the new anchor.
    check pr.reparseStart == 0

    var frames = 1
    while buf.incrementalHighlight.pendingReparse != nil and frames < 100:
      discard e.updateForFrame(frameBuffer)
      inc frames
    check frames < 100
    check buf.incrementalHighlight.pendingReparse == nil
    check buf.incrementalHighlight.lineStates.states.len == buf.len

  test "advances the active buffer's in-flight re-parse across frames":
    # The active-buffer branch (updateHighlight / continueIncrementalHighlight
    # on the frame's active buffer) must drive a multi-frame flight, not just
    # the inactive-buffer loop.
    let config = newEditorConfig()
    let e = newEditor(config)

    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_active.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 5000:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    e.addBuffer(buf)
    # Make it the active buffer so the frame drives it from the active-buffer
    # branch instead of the inactive-buffer loop.
    e.activeWindow.buffer = buf

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    let oldFrontier = buf.incrementalHighlight.pendingReparse.reparseEnd

    # Continuation frames change no content, so the LSP overlay caches must
    # stay valid while the flight advances and after it completes; only a
    # fresh edit invalidates.
    e.state.lspCache.inlayHintCache.isValid = true
    e.state.lspCache.semanticTokensCache = SemanticTokensCache(isValid: true)

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)
    check buf.incrementalHighlight.pendingReparse != nil
    check buf.incrementalHighlight.pendingReparse.reparseEnd > oldFrontier
    # Still in flight after this frame: no invalidation.
    check e.state.lspCache.inlayHintCache.isValid
    check e.state.lspCache.semanticTokensCache.isValid

    var frames = 1
    while buf.incrementalHighlight.pendingReparse != nil and frames < 100:
      e.state.lspCache.inlayHintCache.isValid = true
      e.state.lspCache.semanticTokensCache = SemanticTokensCache(isValid: true)
      discard e.updateForFrame(frameBuffer)
      inc frames
    check frames < 100
    check buf.incrementalHighlight.pendingReparse == nil
    check buf.incrementalHighlight.lineStates.states.len == buf.len
    # The frame that completed the flight changed no content: the overlay
    # caches stay valid.
    check e.state.lspCache.inlayHintCache.isValid
    check e.state.lspCache.semanticTokensCache.isValid

  test "a frame advances an in-flight re-parse once, not twice":
    # Regression: the frame's explicit continuation plus the delegation
    # inside `continueInitialHighlight` advanced the same flight twice in
    # one frame, double-charging the frame budget.
    let config = newEditorConfig()
    let e = newEditor(config)

    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_single_advance.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 5000:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    e.addBuffer(buf)
    e.activeWindow.buffer = buf

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    let oldFrontier = buf.incrementalHighlight.pendingReparse.reparseEnd

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)
    check buf.incrementalHighlight.pendingReparse != nil
    # At most one budget slice (1000) per frame; the double advance moved
    # it by ~2000.
    check buf.incrementalHighlight.pendingReparse.reparseEnd <= oldFrontier + 1000
    check buf.incrementalHighlight.pendingReparse.reparseEnd > oldFrontier

  test "a re-parse completing within a frame charges the shared budget":
    # The inactive-buffer budget must be charged the ACTUAL lines a re-parse
    # consumed, even when the flight completes within the continuation call
    # (a completed trigger used to charge nothing).
    let config = newEditorConfig()
    let e = newEditor(config)

    # A small Rust buffer whose flight completes within the frame's
    # continuation call (~500 lines of remaining work).
    var flightBuf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_charge.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 600:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard flightBuf.loadFile(path)
    while flightBuf.continueInitialHighlight():
      discard
    discard flightBuf.beginTransaction()
    discard flightBuf.insert(0, "let inserted = 1;")
    discard flightBuf.commitTransaction()
    check flightBuf.updateHighlight(100)
    check flightBuf.incrementalHighlight.pendingReparse != nil
    # The trigger rewound the URI scan to the re-parse start; mark it done so
    # the frame's scan is a no-op and this test isolates the re-parse charge.
    flightBuf.uriScanParsedUpTo = flightBuf.len - 1
    e.addBuffer(flightBuf)

    # Two plain-text buffers after it in e.buffers order.
    var plain: seq[TextBuffer]
    for i in 0 ..< 2:
      var buf = newTextBuffer()
      let p = getTempDir() / "moe_test_frame_charge" & $i & ".txt"
      defer:
        removeFile(p)
      var c = ""
      for j in 0 ..< 10_000:
        c.add("plain line " & $j & "\n")
      writeFile(p, c)
      discard buf.loadFile(p)
      buf.uriScanParsedUpTo = -1
      e.addBuffer(buf)
      plain.add(buf)

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)

    # The flight completed within the frame's continuation and its actual
    # (~500-line) work was charged, so plain[1] did NOT get a full
    # 1000-line chunk this frame.
    check flightBuf.incrementalHighlight.pendingReparse == nil
    check plain[0].uriScanParsedUpTo == 999
    check plain[1].uriScanParsedUpTo < 999

  test "a trigger completing a flight within a frame charges the shared budget":
    # Regression: a trigger that restarts AND completes a flight within the
    # frame's in-loop updateHighlight call lost its consumed-line charge
    # (the continuation branch reset the counter), so later buffers got more
    # budget than the cap allows.
    let config = newEditorConfig()
    let e = newEditor(config)

    # A small Rust buffer whose flight the frame's trigger restarts from ~0
    # and completes within the same call (~600 lines of work).
    var flightBuf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_trigger_charge.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 600:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard flightBuf.loadFile(path)
    while flightBuf.continueInitialHighlight():
      discard
    discard flightBuf.beginTransaction()
    discard flightBuf.insert(0, "let inserted = 1;")
    discard flightBuf.commitTransaction()
    check flightBuf.updateHighlight(100)
    check flightBuf.incrementalHighlight.pendingReparse != nil
    # Mark the URI scan done so the trigger's rewind re-arms it; the re-cover
    # is charged like any scan.
    flightBuf.uriScanParsedUpTo = flightBuf.len - 1
    # A second edit lands mid-flight: the next frame's trigger restarts it
    # from ~0 and completes it within the call.
    discard flightBuf.beginTransaction()
    discard flightBuf.insert(300, "let second = 1;")
    discard flightBuf.commitTransaction()
    e.addBuffer(flightBuf)

    var plain: seq[TextBuffer]
    for i in 0 ..< 2:
      var buf = newTextBuffer()
      let p = getTempDir() / "moe_test_frame_trigger_charge" & $i & ".txt"
      defer:
        removeFile(p)
      var c = ""
      for j in 0 ..< 10_000:
        c.add("plain line " & $j & "\n")
      writeFile(p, c)
      discard buf.loadFile(p)
      buf.uriScanParsedUpTo = -1
      e.addBuffer(buf)
      plain.add(buf)

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)

    # The trigger's ~600-line re-parse plus the URI re-cover exhaust the
    # shared budget: plain[0] gets less than a full chunk and plain[1]
    # nothing (without the charge both would scan full chunks).
    check flightBuf.incrementalHighlight.pendingReparse == nil
    check plain[0].uriScanParsedUpTo < 999
    check plain[1].uriScanParsedUpTo == -1

  test "inactive buffers share one frame budget":
    let config = newEditorConfig()
    let e = newEditor(config)

    # Three large plain-text buffers: their URI scans are the only per-frame
    # work. The shared 2000-line budget must cap the aggregate scan: the
    # first two buffers consume it and the third is deferred.
    var bufs: seq[TextBuffer]
    for i in 0 ..< 3:
      var buf = newTextBuffer()
      let path = getTempDir() / "moe_test_frame_budget" & $i & ".txt"
      defer:
        removeFile(path)
      var content = ""
      for j in 0 ..< 10_000:
        content.add("plain line " & $j & "\n")
      writeFile(path, content)
      discard buf.loadFile(path)
      buf.uriScanParsedUpTo = -1
      e.addBuffer(buf)
      bufs.add(buf)

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)

    check bufs[0].uriScanParsedUpTo == 999
    check bufs[1].uriScanParsedUpTo == 999
    # The budget is exhausted by the first two buffers; the third must not
    # run this frame.
    check bufs[2].uriScanParsedUpTo == -1

    # ... and the loop catches up on later frames (the front buffers finish
    # first, then the deferred one).
    var frames = 1
    while bufs[2].uriScanParsedUpTo < bufs[2].len - 1 and frames < 100:
      discard e.updateForFrame(frameBuffer)
      inc frames
    check frames < 100
    check bufs[2].uriScanParsedUpTo == bufs[2].len - 1

  test "the frame loop drives an incomplete initial load of an inactive buffer":
    # Regression: the per-frame load-resume and its `loadLines` budget
    # accounting had no test. Without the resume, an inactive buffer's URI
    # scan (clamped to the load frontier) never reaches the tail rows.
    let config = newEditorConfig()
    let e = newEditor(config)

    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_load_resume.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 5000:
      if i == 4000:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    # Advance the initial load by one chunk only: the frontier stalls at 999.
    check buf.continueInitialHighlight()
    check buf.incrementalHighlight.parsedUpTo < buf.len - 1
    e.addBuffer(buf)
    # An edit below the load frontier (the inserted row shifts the URI from
    # 4000 to 4001); the load re-parses the uncovered band below the edit.
    discard buf.beginTransaction()
    discard buf.insert(2000, "let inserted = 1;")
    discard buf.commitTransaction()

    let frameBuffer = newBuffer(80, 24)
    # The frame loop must advance the load and, with it, the URI scan
    # (clamped to the load frontier) until the tail rows are covered.
    var frames = 1
    while (
      buf.incrementalHighlight.parsedUpTo < buf.len - 1 or
      buf.uriScanParsedUpTo < buf.len - 1
    ) and frames < 100
    :
      discard e.updateForFrame(frameBuffer)
      inc frames
    check frames < 100
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1
    check buf.uriScanParsedUpTo == buf.len - 1
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(4001, uriCol)

  test "an inactive YAML buffer stuck in a handoff hazard does not drain the shared budget":
    # Regression: a chunk fully inside a handoff hazard doubles `chunkLen`
    # and defers; the rejected attempt used to bump `parsedLines` by the
    # full window, so one stuck buffer drained the shared budget and
    # starved buffers served later.
    let config = newEditorConfig()
    let e = newEditor(config)

    # Buffer 1: a YAML top-level block scalar with a >1000-line blank run —
    # a re-parse anchored at the top sits fully inside the handoff hazard
    # for at least the first `ChunkSize`-sized window.
    var stuck = newTextBuffer()
    let stuckPath = getTempDir() / "moe_test_frame_stuck.yaml"
    defer:
      removeFile(stuckPath)
    var stuckContent = "long: |\n"
    for i in 0 ..< 5000:
      stuckContent.add("\n")
    stuckContent.add("after: tail\n")
    writeFile(stuckPath, stuckContent)
    discard stuck.loadFile(stuckPath)
    while stuck.continueInitialHighlight():
      discard
    e.addBuffer(stuck)

    # Buffer 2: a plain buffer served after `stuck`. Its URI scan is the
    # canary — before the fix, the stuck buffer drained the budget and this
    # scan never advanced.
    var canary = newTextBuffer()
    let canaryPath = getTempDir() / "moe_test_frame_canary.txt"
    defer:
      removeFile(canaryPath)
    var canaryContent = ""
    for i in 0 ..< 500:
      canaryContent.add("plain line " & $i & "\n")
    writeFile(canaryPath, canaryContent)
    discard canary.loadFile(canaryPath)
    canary.uriScanParsedUpTo = -1
    e.addBuffer(canary)

    # Edit at the top of the stuck buffer to trigger a flight inside the
    # handoff hazard.
    discard stuck.beginTransaction()
    discard stuck.insert(1, "")
    discard stuck.commitTransaction()

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)

    # The canary must have made progress in the same frame — its URI scan
    # covers its full length in one chunk.
    check canary.uriScanParsedUpTo == canary.len - 1
    # And the stuck buffer's flight defers (still pending, no chunk accepted).
    check stuck.incrementalHighlight.pendingReparse != nil

  test "flag-only edit on an inactive buffer is processed by the frame loop":
    # Regression: the inactive-buffer branch used to gate on
    # `pendingReparse != nil`, so a flag-only edit (LSP publishDiagnostics,
    # setReservedWords) with no flight was skipped until the buffer became
    # active.
    let config = newEditorConfig()
    let e = newEditor(config)

    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_flag_only.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 200:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    e.addBuffer(buf)

    # Simulate an LSP publishDiagnostics that sets the flag with no flight.
    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 10,
        startCol: 0,
        endLine: 10,
        endCol: 5,
        severity: bdsError,
        message: "test error",
      )
    ]
    buf.diagnosticsDirty = true
    buf.highlightNeedsUpdate = true
    check buf.incrementalHighlight.pendingReparse == nil

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)

    check not buf.highlightNeedsUpdate
    check not buf.diagnosticsDirty
    check buf.highlight.getSegmentModifiers(10, 2) == {StyleModifier.Undercurl}

  test "render advances an in-flight re-parse once, not per visible row":
    # Regression: the draw path called `continueIncrementalHighlight(1000)`
    # from every painted row, so one frame's draw re-parsed
    # visibleHeight * 1000 lines and bypassed the frame budget. The advance
    # must happen once per window per frame.
    let config = newEditorConfig()
    let e = newEditor(config)

    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_render_advance.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 5000:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    e.addBuffer(buf)
    e.activeWindow.buffer = buf

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    let oldFrontier = buf.incrementalHighlight.pendingReparse.reparseEnd

    var screenBuffer = newBuffer(80, 24)
    e.render(screenBuffer)

    # `updateForFrame` advances the active buffer by at most one budget slice
    # (1000) and the draw pass one more chunk (1000); a per-row advance (the
    # regression) would move the frontier by ~visibleHeight * 1000.
    if buf.incrementalHighlight.pendingReparse != nil:
      check buf.incrementalHighlight.pendingReparse.reparseEnd <= oldFrontier + 2000
      check buf.incrementalHighlight.pendingReparse.reparseEnd > oldFrontier
    else:
      check false

suite "updateForFrame - LSP overlay invalidation":
  test "single-frame edit invalidates the inlay-hint cache":
    # Regression: an edit whose re-parse fit within the 1000-line budget with
    # no prior in-flight re-parse used to skip `invalidateInlayHintCache`,
    # leaving stale hints on shifted absolute lines.
    let config = newEditorConfig()
    let e = newEditor(config)

    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_frame_inlay_invalidate.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 20:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    e.addBuffer(buf)
    e.activeWindow.buffer = buf

    e.state.lspCache.inlayHintCache.isValid = true

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    # A small edit fits in one budget; hadFlight=false and updateHighlight
    # returns false, but the LSP overlay must still be invalidated.
    check buf.incrementalHighlight.pendingReparse == nil

    let frameBuffer = newBuffer(80, 24)
    discard e.updateForFrame(frameBuffer)

    check not e.state.lspCache.inlayHintCache.isValid
