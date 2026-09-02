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

## Lifecycle guard: an Insert/Replace session owns an open transaction and the
## replay/dot-repeat state, so the sites that tear it down (focus moves, buffer
## swaps, session entry/exit) are pinned here with their file and allowed
## count. A new site fails as a violation and a stale entry fails as stale, so
## neither a leaked transaction nor a dead exception can slip through.
##
## Matching runs on comment-stripped code and never on line numbers. The parser
## self-tests below catch a scanner that degrades into "matches nothing".

import std/[unittest, os, strutils, tables]

type
  Matcher = proc(code: string): int {.nimcall.}

  Invariant = object
    name: string
    guidance: string
    ## Base names skipped entirely: the pattern is too generic to be meaningful
    ## there (unrelated `.buffer` fields, or the module that owns the API).
    skipFiles: seq[string]
    match: Matcher
    ## src-relative path -> number of sites allowed in that file.
    allow: seq[(string, int)]

proc findSrcRoot(): string =
  ## Locate src/ relative to this test file so the scan works from any CWD.
  var dir = currentSourcePath.parentDir
  for _ in 0 .. 5:
    if dirExists(dir / "src" / "moepkg"):
      return dir / "src"
    let parent = dir.parentDir
    if parent.len == 0 or parent == dir:
      break
    dir = parent
  return ""

proc stripComment(line: string): string =
  ## Cut a trailing `# comment` (double-quoted literals only; escapes are not
  ## modelled). Full-line comments collapse to an empty string.
  var inString = false
  for i in 0 ..< line.len:
    let c = line[i]
    if c == '"':
      inString = not inString
    elif c == '#' and not inString:
      return line.substr(0, i - 1)
  return line

proc isInsideString(line: string, idx: int): bool =
  var quotes = 0
  for k in 0 ..< idx:
    if line[k] == '"':
      inc quotes
  quotes mod 2 == 1

proc isIdentChar(c: char): bool =
  c.isAlphaNumeric or c == '_'

proc occurrences(code: string, token: string): seq[int] =
  ## Start offsets of `token` in code positions, requiring an identifier
  ## boundary after it and rejecting matches inside string literals. `token`
  ## may start with a dot (`.buffer`), in which case the preceding character
  ## is unconstrained.
  var pos = 0
  while pos < code.len:
    let idx = code.find(token, pos)
    if idx < 0:
      break
    let before = idx == 0 or token[0] == '.' or not isIdentChar(code[idx - 1])
    let after = idx + token.len
    let boundaryOk = after >= code.len or not isIdentChar(code[after])
    if before and boundaryOk and not code.isInsideString(idx):
      result.add(idx)
    pos = idx + 1

proc skipSpaces(code: string, start: int): int =
  result = start
  while result < code.len and code[result] in {' ', '\t'}:
    inc result

proc assignsAt(code: string, after: int, compound: bool): int =
  ## If an assignment operator starts at/after `after` (spaces skipped),
  ## return the offset just past `=`; otherwise -1. `compound` also accepts
  ## `+=` / `-=`. Comparisons (`==`, `!=`, `>=`, `<=`) are rejected.
  var p = code.skipSpaces(after)
  if compound and p < code.len and code[p] in {'+', '-'}:
    inc p
  if p >= code.len or code[p] != '=':
    return -1
  if p + 1 < code.len and code[p + 1] == '=':
    return -1
  if p > 0 and code[p - 1] in {'!', '<', '>', '=', '*', '/'}:
    return -1
  if not compound and p > 0 and code[p - 1] in {'+', '-'}:
    return -1
  return p + 1

proc countCalls(code: string, name: string): int =
  ## Calls to `name`. A definition (`proc name*(`) does not match because of
  ## the export marker, and neither does a bare mention.
  for idx in code.occurrences(name):
    let p = code.skipSpaces(idx + name.len)
    if p < code.len and code[p] == '(':
      inc result

proc matchWindowBufferAssign(code: string): int =
  for idx in code.occurrences(".buffer"):
    let rhs = code.assignsAt(idx + len(".buffer"), compound = false)
    if rhs >= 0 and code.skipSpaces(rhs) < code.len:
      inc result

proc matchActivateWindow(code: string): int =
  code.countCalls("activateWindow")

proc matchActiveWindowIndexAssign(code: string): int =
  const Field = "windowManager.activeWindowIndex"
  for idx in code.occurrences(Field):
    if code.assignsAt(idx + Field.len, compound = true) >= 0:
      inc result

proc matchFinalizeForBufferSwitch(code: string): int =
  code.countCalls("finalizeInsertSessionForBufferSwitch")

proc countStartPosAssign(code: string, rhs: string): int =
  const Field = "insertModeStartPos"
  for idx in code.occurrences(Field):
    let after = code.assignsAt(idx + Field.len, compound = false)
    if after >= 0 and code.substr(code.skipSpaces(after)).startsWith(rhs):
      inc result

proc matchStartPosSome(code: string): int =
  code.countStartPosAssign("some")

proc matchStartPosNone(code: string): int =
  code.countStartPosAssign("none")

proc matchSessionBeginTransaction(code: string): int =
  ## `beginTransaction` opened with one of the session descriptions. The
  ## description is what makes a transaction a session, so this catches entry
  ## points that never touch `insertModeStartPos` (Replace does not).
  const Descriptions = [
    "Insert mode edit", "Append mode edit", "Visual to insert mode", "Replace mode edit"
  ]
  for idx in code.occurrences("beginTransaction"):
    let p = code.skipSpaces(idx + len("beginTransaction"))
    if p >= code.len or code[p] != '(':
      continue
    let rest = code.substr(p + 1)
    for d in Descriptions:
      if rest.startsWith('"' & d & '"'):
        inc result
        break

let Invariants = @[
  Invariant(
    name: "window buffer replacement",
    guidance:
      "Replacing a window's buffer abandons whatever session that window " &
      "owned. A new site must finalize the session first.",
    # `.buffer` also names unrelated fields in these modules.
    skipFiles: @["registers.nim", "sidebar.nim", "commands.nim"],
    match: matchWindowBufferAssign,
    allow: @[
      ("moepkg/editor_buffers.nim", 4),
      ("moepkg/editor_frame.nim", 1),
      ("moepkg/editor_navigation.nim", 1),
      ("moepkg/editor_window.nim", 1),
      ("moepkg/editor_window_state.nim", 1),
      ("moepkg/viewer_mode.nim", 1),
      ("moepkg/command_handlers/backup_ops.nim", 4),
      ("moepkg/command_handlers/editor_ops.nim", 1),
      ("moepkg/command_handlers/mode_dispatchers.nim", 2),
      ("moepkg/command_handlers/viewer_ops.nim", 3),
    ],
  ),
  Invariant(
    name: "window focus move",
    guidance:
      "Focus moves must leave the session of the window being left in a " &
      "consistent state; window_manager.nim owns the primitive.",
    skipFiles: @["window_manager.nim"],
    match: matchActivateWindow,
    allow: @[
      ("moepkg/viewer_mode.nim", 1),
      ("moepkg/command_handlers/editor_ops.nim", 2),
      ("moepkg/command_handlers/file_ops.nim", 1),
    ],
  ),
  Invariant(
    name: "active window index write",
    guidance:
      "Writing the index moves focus without going through the focus " &
      "primitive, so the session of the window being left is not consulted.",
    skipFiles: @["window_manager.nim"],
    match: matchActiveWindowIndexAssign,
    allow: @[
      ("moepkg/editor.nim", 1), # Initial window setup.
      # Terminal close scratch + restore, and the new right window.
      ("moepkg/editor_buffers.nim", 3),
      ("moepkg/handler.nim", 1), # Mouse jump to the clicked window.
      ("moepkg/command_handlers/editor_ops.nim", 1), # File tree index fixup.
    ],
  ),
  Invariant(
    name: "session finalize on buffer switch",
    guidance:
      "Finalizing outside the enumerated sites either double-commits or " &
      "commits a session the caller does not own.",
    skipFiles: @[],
    match: matchFinalizeForBufferSwitch,
    allow: @[
      ("moepkg/editor_buffers.nim", 3),
      ("moepkg/editor_navigation.nim", 1),
      ("moepkg/editor_window.nim", 1),
      ("moepkg/handler.nim", 1),
    ],
  ),
  Invariant(
    name: "session start position record",
    guidance: "Session entry points must stay enumerable.",
    skipFiles: @[],
    match: matchStartPosSome,
    allow: @[
      ("moepkg/command_handlers/mode_dispatchers.nim", 2),
      ("moepkg/command_registry/edit.nim", 6),
    ],
  ),
  Invariant(
    name: "session start position clear",
    guidance: "Session exit points and boundaries must stay enumerable.",
    skipFiles: @[],
    match: matchStartPosNone,
    allow: @[
      ("moepkg/editor_mode.nim", 2),
      ("moepkg/handler.nim", 1),
      ("moepkg/command_handlers/command_mode_handler.nim", 1),
      ("moepkg/command_handlers/handler_manager.nim", 1),
      ("moepkg/command_handlers/mode_dispatchers.nim", 2),
      ("moepkg/command_handlers/result_processor.nim", 1),
    ],
  ),
  Invariant(
    name: "session transaction open",
    guidance:
      "Every session opens its transaction with one of these descriptions, " &
      "so this sees entry points that never record a start position.",
    skipFiles: @[],
    match: matchSessionBeginTransaction,
    allow: @[
      ("moepkg/command_handlers/handler_manager.nim", 2),
      ("moepkg/command_handlers/mode_dispatchers.nim", 1),
      ("moepkg/command_handlers/normal_handler.nim", 2),
      ("moepkg/command_registry/edit.nim", 2),
    ],
  ),
]

proc nimFilesUnder(root: string): seq[string] =
  for path in walkDirRec(root):
    if path.endsWith(".nim"):
      result.add(path)

proc relativeTo(path, root: string): string =
  result = path.relativePath(root)
  when DirSep != '/':
    result = result.replace($DirSep, "/")

proc scan(
    inv: Invariant, files: seq[string], root: string
): Table[string, seq[string]] =
  ## src-relative path -> one entry per site, formatted for failure output.
  for file in files:
    if file.extractFilename in inv.skipFiles:
      continue
    let lines = readFile(file).splitLines()
    var sites: seq[string] = @[]
    for i in 0 ..< lines.len:
      let code = stripComment(lines[i])
      for _ in 0 ..< inv.match(code):
        sites.add($(i + 1) & ": " & code.strip())
    if sites.len > 0:
      result[relativeTo(file, root)] = sites

suite "Insert session lifecycle invariants":
  let srcRoot = findSrcRoot()
  let files =
    if srcRoot.len > 0:
      nimFilesUnder(srcRoot)
    else:
      @[]

  test "source tree is reachable":
    check srcRoot.len > 0
    check files.len > 0

  for inv in Invariants:
    test inv.name & ": sites match the pinned list":
      let found = scan(inv, files, srcRoot)
      let allowed = inv.allow.toTable

      var unexpected, stale: seq[string] = @[]
      for path, sites in found:
        let budget = allowed.getOrDefault(path, 0)
        if sites.len > budget:
          for s in sites[budget ..^ 1]:
            unexpected.add(path & ":" & s)
      for path, count in allowed:
        let actual = found.getOrDefault(path, @[]).len
        if actual < count:
          stale.add(path & ": pinned " & $count & ", found " & $actual)

      if unexpected.len > 0:
        echo "  ", inv.guidance
        for u in unexpected:
          echo "  UNPINNED SITE: ", u
      if stale.len > 0:
        echo "  Remove the entry, or lower its count, in Invariants."
        for s in stale:
          echo "  STALE ENTRY: ", s
      check unexpected.len == 0
      check stale.len == 0

suite "Invariant scanner self-tests":
  proc hits(m: Matcher, line: string): int =
    m(stripComment(line))

  test "window buffer replacement matches an assignment only":
    let m = matchWindowBufferAssign
    check m.hits("e.activeWindow.buffer = newBuffer") == 1
    check m.hits("  win.buffer = buffer") == 1
    check m.hits("if w.buffer == other:") == 0
    check m.hits("w.bufferStatus = x") == 0
    check m.hits("# w.buffer = x") == 0
    check m.hits("let s = \"w.buffer = x\"") == 0

  test "focus move matches calls, not mentions":
    let m = matchActivateWindow
    check m.hits("e.windowManager.activateWindow(i)") == 1
    check m.hits("proc activateWindow*(wm: WindowManager) =") == 0
    check m.hits("# calls activateWindow(i)") == 0

  test "active window index write accepts compound assignment":
    let m = matchActiveWindowIndexAssign
    check m.hits("e.windowManager.activeWindowIndex = 0") == 1
    check m.hits("e.windowManager.activeWindowIndex += 1") == 1
    check m.hits("if e.windowManager.activeWindowIndex == 0:") == 0
    check m.hits("let i = e.windowManager.activeWindowIndex") == 0

  test "session finalize matches the call, not the definition":
    let m = matchFinalizeForBufferSwitch
    check m.hits("e.finalizeInsertSessionForBufferSwitch(buf)") == 1
    check m.hits("proc finalizeInsertSessionForBufferSwitch*(e: Editor) =") == 0

  test "start position record and clear are distinguished":
    let some = matchStartPosSome
    let none = matchStartPosNone
    check some.hits("state.editState.insertModeStartPos = some(cursor)") == 1
    check some.hits("state.editState.insertModeStartPos = none(Pos)") == 0
    check none.hits("state.editState.insertModeStartPos = none(Pos)") == 1
    check none.hits("if state.editState.insertModeStartPos.isNone:") == 0

  test "session transaction open matches only session descriptions":
    let m = matchSessionBeginTransaction
    check m.hits("buffer.beginTransaction(\"Insert mode edit\")") == 1
    check m.hits("buffer.beginTransaction(\"Replace mode edit\", cursorPos = p)") == 1
    check m.hits("buffer.beginTransaction(\"Paste\")") == 0
    check m.hits("buffer.beginTransaction(description)") == 0

  test "an extra site in a pinned file is counted":
    let root = getTempDir() / "moe_insert_invariant_fixture"
    createDir(root / "moepkg")
    let path = root / "moepkg" / "editor_window.nim"
    writeFile(path, "e.activeWindow.buffer = a\ne.activeWindow.buffer = b\n")
    defer:
      removeDir(root)
    let inv = Invariant(
      name: "fixture",
      guidance: "",
      skipFiles: @[],
      match: matchWindowBufferAssign,
      allow: @[("moepkg/editor_window.nim", 1)],
    )
    let found = scan(inv, @[path], root)
    check found["moepkg/editor_window.nim"].len == 2
