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

## Style guard: the buffer-edit APIs return Result[(), string] and discarding
## them silently swallows edit failures (cursor/buffer desync, partial
## transactions, lost text). This test scans the source tree for `discard` of
## those APIs so a regression is caught at test time.
##
## The scan is multi-line aware: nph may split a `discard` onto its own line
## with the call on the following line (see the historical
## mode_dispatchers.nim visual-block replay), so a single-line grep is not
## sufficient. The `discard` keyword is matched at word boundaries (not only
## at line start) so `if cond: discard foo(...)` / `else: discard ...` /
## `for x in y: discard ...` forms are caught too, and nested calls inside a
## discarded wrapper (`discard wrap(buffer.insertText(...))`) are detected as
## well. Parser self-tests with fixture snippets guard against the scanner
## silently degrading.

import std/[unittest, os, strutils, sets, options]

const
  ## Buffer-edit / transaction APIs whose Result must not be discarded.
  TargetApis = [
    "insertText", "insertTextEnd", "deleteChar", "insert", "deleteLine", "deleteRange",
    "replaceLine", "splitLine", "joinLines", "transformRange", "beginTransaction",
    "commitTransaction", "rollbackTransaction", "withTransaction",
    "deleteBlockSelection", "deleteLineSelection", "undo", "redo",
  ].toHashSet

  ## Intentional discards that cannot propagate. Keyed by (path suffix,
  ## proc name). buffer/undo.nim's withTransaction finally-block rollback is
  ## the rollback path itself, so its failure has nowhere to be reported.
  AllowList = [("buffer/undo.nim", "rollbackTransaction")]

  ## Keywords that start a new statement. Used to stop multi-line assembly of
  ## a bare `discard` so an unrelated following call is never folded into it
  ## (e.g. the statement after an `except CatchableError:` handler's discard).
  StmtStartKeywords = [
    "let", "var", "const", "type", "return", "result", "if", "when", "for", "while",
    "case", "of", "else", "elif", "try", "except", "finally", "defer", "block", "proc",
    "template", "macro", "converter", "iterator", "raise", "assert", "yield", "break",
    "continue", "discard", "import", "export", "include", "from",
  ]

proc findSrcRoot(): string =
  ## Locate the src/ directory relative to this test file (tests/ is a sibling
  ## of src/). Walks up a few levels so it works regardless of the CWD the test
  ## is launched from.
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
  ## Cut a trailing `# comment` (naive about strings: double-quoted literals
  ## only). Full-line comments collapse to an empty string.
  var inString = false
  for i in 0 ..< line.len:
    let c = line[i]
    if c == '"':
      inString = not inString
    elif c == '#' and not inString:
      return line.substr(0, i - 1)
  return line

proc isInsideString(line: string, idx: int): bool =
  ## True when `idx` sits inside a double-quoted string literal (quote-count
  ## heuristic; escaped quotes are not modelled).
  var quotes = 0
  for k in 0 ..< idx:
    if line[k] == '"':
      inc quotes
  quotes mod 2 == 1

proc discardExprInLine(line: string): Option[string] =
  ## If `line` contains a discard statement, return the expression following
  ## the `discard` keyword (may be empty for the multi-line form). Returns
  ## none for comment lines and lines without a discard statement.
  ##
  ## The keyword is matched at a word boundary anywhere in the code part of
  ## the line, so `if cond: discard foo(...)`, `else: discard ...` and
  ## `x; discard ...` are all detected, while identifiers containing the word
  ## (`discarded`, `imrDiscarded`) and occurrences inside string literals are
  ## not.
  let code = stripComment(line).strip()
  if code.len == 0:
    return none(string)
  var pos = 0
  while pos < code.len:
    let idx = code.find("discard", pos)
    if idx < 0:
      break
    let beforeOk = idx == 0 or code[idx - 1] in {' ', '\t', ';', ':', '(', '=', ','}
    let afterIdx = idx + len("discard")
    let afterOk =
      afterIdx >= code.len or
      not (code[afterIdx].isAlphaNumeric or code[afterIdx] == '_')
    if beforeOk and afterOk and not code.isInsideString(idx):
      return some(code.substr(afterIdx).strip())
    pos = idx + 1
  return none(string)

proc startsWithStmtKeyword(line: string): bool =
  for kw in StmtStartKeywords:
    if line.startsWith(kw):
      if line.len == kw.len:
        return true
      let nxt = line[kw.len]
      if nxt in {' ', '\t', ':', '(', ';'}:
        return true
  return false

proc calledProcNames(expr: string): seq[string] =
  ## Extract every called proc name from a discarded expression: each
  ## identifier immediately preceding a `(`, reduced to its last dotted
  ## segment. Leading grouping parens are skipped (`discard (buffer.foo())`)
  ## and nested calls are included (`discard wrap(buffer.insertText(...))`
  ## reports both), so a target API hidden inside a wrapper call is caught.
  var i = 0
  while i < expr.len:
    let p = expr.find("(", i)
    if p < 0:
      break
    var k = p - 1
    while k >= 0 and expr[k] in {' ', '\t'}:
      dec k
    var ident = ""
    while k >= 0 and (expr[k].isAlphaNumeric or expr[k] == '_' or expr[k] == '.'):
      ident = expr[k] & ident # Prepend: we scan backwards from the paren.
      dec k
    if ident.len > 0:
      let dotIdx = ident.rfind(".")
      let name =
        if dotIdx >= 0:
          ident.substr(dotIdx + 1)
        else:
          ident
      if name notin result:
        result.add(name)
    i = p + 1

proc isAllowlisted(path: string, procName: string): bool =
  for (suffix, api) in AllowList:
    if path.endsWith(suffix) and procName == api:
      return true
  return false

proc scanFile(path: string): seq[string] =
  ## Return a list of human-readable violations found in `path`.
  let lines = readFile(path).splitLines()
  for i in 0 ..< lines.len:
    let exprOpt = discardExprInLine(lines[i])
    if exprOpt.isNone:
      continue
    # Assemble the expression, pulling in following lines for the multi-line
    # `discard` form until an opening paren (the call) is found.
    var expr = exprOpt.get
    var j = i
    while not expr.contains("(") and j + 1 < lines.len and j - i < 6:
      inc j
      let next = lines[j].strip()
      if next.len == 0 or next.startsWith("#"):
        continue
      if expr.len == 0 and next.startsWithStmtKeyword():
        # A bare `discard` ends its own statement (e.g. an exception handler
        # body); the following statement is not its expression.
        break
      expr = (expr & " " & next).strip()
    for procName in calledProcNames(expr):
      if procName notin TargetApis:
        continue
      if isAllowlisted(path, procName):
        continue
      result.add(
        path & ":" & $(i + 1) & ": discard of " & procName & " -> " & expr.strip()
      )

proc extractResultApis(path: string): seq[string] =
  ## Names of the exported procs/templates in `path` whose signature returns
  ## a Result. Signatures may span multiple lines, so lines are accumulated
  ## until the header is complete (ends with `=` or names a Result type).
  let lines = readFile(path).splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    var header = ""
    if line.startsWith("proc "):
      header = line.substr(len("proc "))
    elif line.startsWith("template "):
      header = line.substr(len("template "))
    else:
      inc i
      continue
    var sig = header.strip()
    var j = i
    while not sig.endsWith("=") and not sig.contains("Result[") and j + 1 < lines.len and
        j - i < 10:
      inc j
      sig = (sig & " " & lines[j].strip()).strip()
    var name = ""
    for c in sig:
      if c.isAlphaNumeric or c == '_':
        name.add(c)
      else:
        break
    if name.len > 0 and sig.contains(name & "*") and sig.contains("Result["):
      result.add(name)
    i = j + 1

suite "No discarded buffer-edit Results":
  test "no discard of buffer edit / transaction APIs in src/":
    let srcRoot = findSrcRoot()
    check srcRoot.len > 0

    var nimFiles: seq[string] = @[]
    if srcRoot.len > 0:
      # walkDirRec yields every path recursively; directories never end in
      # .nim, so the suffix filter selects exactly the Nim source files.
      for path in walkDirRec(srcRoot):
        if path.endsWith(".nim"):
          nimFiles.add(path)

    check nimFiles.len > 0

    var violations: seq[string] = @[]
    for file in nimFiles:
      violations.add(scanFile(file))

    if violations.len > 0:
      # Surface every offending site in the failure output.
      for v in violations:
        echo "  VIOLATION: ", v
    check violations.len == 0

  test "TargetApis covers every Result-returning API in buffer/edit.nim and buffer/undo.nim":
    let srcRoot = findSrcRoot()
    check srcRoot.len > 0

    var missing: seq[string] = @[]
    for rel in ["moepkg/buffer/edit.nim", "moepkg/buffer/undo.nim"]:
      let path = srcRoot / rel
      check fileExists(path)
      for name in extractResultApis(path):
        if name notin TargetApis:
          missing.add(rel & ": " & name)

    if missing.len > 0:
      for m in missing:
        echo "  MISSING from TargetApis: ", m
    check missing.len == 0

suite "Style guard parser self-tests":
  proc scanSnippet(snippet: string): seq[string] =
    ## Run the scanner on a fixture snippet and return the violations.
    let path = getTempDir() / "moe_style_guard_fixture.nim"
    writeFile(path, snippet)
    defer:
      removeFile(path)
    scanFile(path)

  test "detects plain discard of a target API":
    check scanSnippet("discard buffer.insertText(pos, \"x\")\n").len > 0

  test "detects multi-line discard split by the formatter":
    check scanSnippet("discard\n  buffer.insertText(pos, \"x\")\n").len > 0

  test "detects discard after a same-line colon (if/else/for bodies)":
    check scanSnippet("if cond: discard buffer.insertText(pos, \"x\")\n").len > 0
    check scanSnippet("else: discard buffer.deleteChar(pos)\n").len > 0
    check scanSnippet("for i in 0 .. 3: discard buffer.deleteLine(i)\n").len > 0

  test "detects discard of a parenthesized expression":
    check scanSnippet("discard (buffer.insertText(pos, \"x\"))\n").len > 0

  test "detects discard of a wrapper call around a target API":
    check scanSnippet("discard wrap(buffer.insertText(pos, \"x\"))\n").len > 0

  test "ignores bare discard followed by a new statement":
    let snippet =
      "try:\n" & "  doSomething()\n" & "except CatchableError:\n" & "  discard\n" &
      "  let r = buffer.insertText(pos, \"x\")\n"
    check scanSnippet(snippet).len == 0

  test "ignores identifiers that merely contain the word discard":
    check scanSnippet("let discarded = buffer.insertText(pos, \"x\")\n").len == 0
    check scanSnippet("case kind\nof imrDiscarded: foo()\n").len == 0

  test "ignores discard mentions in comments and strings":
    check scanSnippet("# discard buffer.insertText(pos, \"x\")\n").len == 0
    check scanSnippet("foo() # discard buffer.deleteLine(0)\n").len == 0
    check scanSnippet("let s = \"discard buffer.insertText(pos, x)\"\n").len == 0

  test "ignores discard of a non-target API":
    check scanSnippet("discard someOtherProc(pos)\n").len == 0

  test "honours the allowlist":
    let dir = getTempDir() / "moe_style_guard_fixture" / "buffer"
    createDir(dir)
    let path = dir / "undo.nim"
    writeFile(path, "discard b.rollbackTransaction()\n")
    defer:
      removeFile(path)
    check scanFile(path).len == 0
