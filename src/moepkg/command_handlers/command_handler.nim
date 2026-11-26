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

## Command mode handler
##
## Parses `:cmd` input and produces a `HandlerResult` directly.  Each execute*
## helper corresponds to a specific `CommandLineAction` (cla*) and returns the
## same `HandlerResult` variant that `processResult` consumes, so no
## intermediate cmr layer is required.

import std/[options, os, strutils]

import pkg/results

import ../[modes, command_line, command_config, command_registry, config_loader]
import ../buffer/[core, edit, fold, search, undo]
import ../setting_options
from ../syntax/tokenizer import SourceLanguage, getSourceLanguage
import handler_types, handler_result
export setting_options, handler_types

proc newCommandModeHandler*(
    parser: CommandLineParser, config: CommandConfig, commandRegistry: CommandRegistry
): CommandModeHandler =
  ## Create a new Command mode handler
  CommandModeHandler(parser: parser, config: config, commandRegistry: commandRegistry)

const AllEditableModes = @[
  EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
  EditorMode.VisualLine, EditorMode.Replace,
]

proc unsavedChangesErr(): HandlerResult =
  ## Error returned when a destructive command runs on a modified buffer without
  ## the ! override.
  HandlerResult(
    kind: hrError, errorMessage: "No write since last change (add ! to override)"
  )

proc modesForMapAction(kind: CommandLineAction): seq[EditorMode] =
  ## Resolve the target modes for a :map/:unmap/:mapclear-family action. The
  ## letter prefix (n/i/v/r/c) picks a single mode; the bare form (:map,
  ## :unmap, :mapclear) covers all editable modes.
  case kind
  of claNmap, claNnoremap, claNunmap, claNmapclear:
    @[EditorMode.Normal]
  of claImap, claInoremap, claIunmap, claImapclear:
    @[EditorMode.Insert]
  of claVmap, claVnoremap, claVunmap, claVmapclear:
    @[EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]
  of claRmap, claRunmap, claRmapclear:
    @[EditorMode.Replace]
  of claCmap, claCnoremap, claCunmap, claCmapclear:
    @[EditorMode.Command]
  else:
    AllEditableModes

proc executeQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    force: bool,
    isSharedBuffer: bool = false,
): HandlerResult =
  ## Execute quit command (:q, :q!) - closes current window.
  ## isSharedBuffer=true skips the isModified check for shared buffers.
  if not force and not isSharedBuffer:
    if buffer.isModified:
      return unsavedChangesErr()
  return HandlerResult(kind: hrCloseWindow, forceClose: force, asQuit: true)

proc executeQuitAll*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    force: bool,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Execute :qa / :qa!. `otherModifiedCount` covers buffers other than `buffer`.
  if not force:
    let total = (if buffer.isModified: 1 else: 0) + otherModifiedCount
    if total > 0:
      if total == 1:
        return unsavedChangesErr()
      return HandlerResult(
        kind: hrError,
        errorMessage:
          "No write since last change: " & $total &
          " buffers modified (add ! to override)",
      )
  HandlerResult(kind: hrQuit, endJobs: force)

proc executeSave*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): HandlerResult =
  ## Execute save command (:w, :w!)
  HandlerResult(kind: hrSave, saveFilename: filename, forceSave: force)

proc executeSaveAs*(
    handler: CommandModeHandler, filename: Option[string], force: bool
): HandlerResult =
  ## Execute :saveas, :saveas!
  if filename.isNone:
    return HandlerResult(kind: hrError, errorMessage: "Argument required")
  HandlerResult(kind: hrSave, saveFilename: filename, forceSave: force, saveAs: true)

proc executeSaveAll*(handler: CommandModeHandler, force: bool): HandlerResult =
  ## Execute save all command (:wa, :wa!)
  HandlerResult(kind: hrSaveAll, forceSaveAll: force)

proc executeSaveAndQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): HandlerResult =
  ## Execute save and quit command (:wq)
  HandlerResult(
    kind: hrSaveAndQuit, saveAndQuitFilename: filename, forceQuitAfterSave: force
  )

proc executeSaveIfModifiedAndQuit*(
    handler: CommandModeHandler, filename: Option[string], force: bool
): HandlerResult =
  ## Execute :x/:xit, writing only when the buffer is modified.
  HandlerResult(
    kind: hrSaveAndQuit,
    saveAndQuitFilename: filename,
    forceQuitAfterSave: force,
    writeOnlyIfModified: true,
  )

proc executeSaveAllAndQuit*(handler: CommandModeHandler, force: bool): HandlerResult =
  ## Execute save all and quit command (:wqa, :xa, :wqa!)
  HandlerResult(kind: hrSaveAllAndQuit, forceSaveAllAndQuitAfter: force)

proc executeEdit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): HandlerResult =
  ## Execute edit command (:e/:e! with optional filename).
  ## Opens a directory in Filer mode; reloads the current buffer when no
  ## filename is given.
  if filename.isSome:
    let expanded = expandTilde(filename.get)
    if dirExists(expanded):
      return
        HandlerResult(kind: hrEnterFiler, enterFilerPath: some(absolutePath(expanded)))
    return HandlerResult(
      kind: hrEdit, editFilename: some(absolutePath(expanded)), forceEdit: force
    )
  if not force and buffer.isModified:
    return unsavedChangesErr()
  HandlerResult(kind: hrEdit, editFilename: none(string), forceEdit: force)

proc executeFiler*(handler: CommandModeHandler, path: Option[string]): HandlerResult =
  ## Execute filer command (:filer with optional path).
  ## A regular file opens its parent directory.
  if path.isNone:
    return HandlerResult(kind: hrEnterFiler, enterFilerPath: none(string))
  let expanded = absolutePath(expandTilde(path.get))
  if dirExists(expanded):
    return HandlerResult(kind: hrEnterFiler, enterFilerPath: some(expanded))
  if fileExists(expanded):
    return HandlerResult(kind: hrEnterFiler, enterFilerPath: some(parentDir(expanded)))
  HandlerResult(kind: hrError, errorMessage: "E344: Can't find directory: " & path.get)

proc executeGotoLine*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    address: ExAddress,
    currentLine: int = 0,
): HandlerResult =
  ## Move to the line an address names.
  ##
  ## Unlike a range, an address past the end lands on the last line rather than
  ## being refused, as in vim. Line 0 is the first line, and above it is E16.
  # Saturating again: the offset may already be at the top.
  let line = satAdd(address.addressLine(currentLine, buffer.len - 1), 1)
  if line < 0:
    return HandlerResult(kind: hrError, errorMessage: "E16: Invalid range")
  HandlerResult(kind: hrGotoLine, lineNumber: clamp(line, 1, buffer.len))

proc parseSetIntValue(spec: SetOptionSpec, value: string): HandlerResult =
  ## Validate and dispatch an integer-typed `:set X=N` option.
  doAssert spec.kind == sokInt, "parseSetIntValue called with non-int spec"
  try:
    let intVal = parseInt(value)
    if intBoundOk(spec.intBound, intVal):
      return
        HandlerResult(kind: hrSetIntOption, intOption: spec.intOption, intValue: intVal)
    HandlerResult(
      kind: hrError, errorMessage: spec.longName & " " & intBoundError(spec.intBound)
    )
  except ValueError:
    HandlerResult(kind: hrError, errorMessage: "Invalid value for " & spec.longName)

proc parseSetFloatValue(spec: SetOptionSpec, value: string): HandlerResult =
  ## Validate and dispatch a float-typed `:set X=N.N` option.
  doAssert spec.kind == sokFloat, "parseSetFloatValue called with non-float spec"
  try:
    let floatVal = parseFloat(value)
    if floatVal >= 0:
      return HandlerResult(
        kind: hrSetFloatOption, floatOption: spec.floatOption, floatValue: floatVal
      )
    HandlerResult(kind: hrError, errorMessage: spec.longName & " must be non-negative")
  except ValueError:
    HandlerResult(kind: hrError, errorMessage: "Invalid value for " & spec.longName)

type SetPrefix = enum
  spNone
  spNo ## `noX`
  spInv ## `invX`

proc isNamed(spec: SetOptionSpec, name: string): bool =
  name == spec.longName or (spec.shortName.len > 0 and name == spec.shortName)

proc findSetOption(name: string): Option[(SetOptionSpec, SetPrefix)] =
  ## The option `name` names, and the `no`/`inv` before it.
  for spec in SetOptionTable:
    if spec.isNamed(name):
      return some((spec, spNone))
  for (prefix, head) in [(spNo, "no"), (spInv, "inv")]:
    if name.startsWith(head):
      for spec in SetOptionTable:
        if spec.isNamed(name[head.len .. ^1]):
          return some((spec, prefix))

proc executeSet*(
    handler: CommandModeHandler,
    option: string,
    value: Option[string],
    valueAfterSpace = false,
): HandlerResult =
  ## Execute `:set X`, `noX`, `invX`, `X!`, `X?` and `X=value`, as in Vim but
  ## one option at a time. A value option alone shows its value, as `X?` does.
  ## Dispatches via `SetOptionTable` (setting_options.nim).
  template rejected(code: string): HandlerResult =
    HandlerResult(
      kind: hrError,
      errorMessage:
        code & ": " & option & (
          if value.isNone: ""
          elif valueAfterSpace: " " & value.get
          else: "=" & value.get
        ),
    )

  let opt = option.toLower
  var nameEnd = 0
  while nameEnd < opt.len and opt[nameEnd] in {'a' .. 'z', '0' .. '9'}:
    nameEnd.inc
  let found = findSetOption(opt[0 ..< nameEnd])
  if found.isNone:
    return HandlerResult(kind: hrError, errorMessage: "Unknown option: " & option)
  let (spec, prefix) = found.get
  let suffix = opt[nameEnd .. ^1]
  if spec.kind != sokBool and prefix != spNone and suffix != "?":
    return rejected("E474: Invalid argument")
  if suffix notin ["", "!", "?"] or (suffix == "!" and spec.kind != sokBool) or
      (suffix.len > 0 and value.isSome and not valueAfterSpace):
    return rejected("E488: Trailing characters")

  # Vim's 'syntax' is the buffer's language (`syntax=java`), and `syntax=OFF`
  # and `syntax=ON` are its values too: off highlights nothing, on goes back to
  # the file's language. Unlike Vim, where `syntax=ON` loads nothing after
  # `:syntax off`, ours also turns the global switch (`:set nosyntax`) back on.
  if spec.kind == sokBool and spec.boolOption == bsoSyntax and prefix == spNone and
      suffix == "" and value.isSome:
    case value.get.toLower
    of "on", "true":
      return HandlerResult(kind: hrSetSyntaxLanguage, followFiletype: true)
    of "off", "false", "", "none":
      return HandlerResult(kind: hrSetSyntaxLanguage, highlightLanguage: langNone)
    else:
      # Vim takes an unknown name and highlights nothing; ours is refused
      # below, as the languages are built in.
      let language = getSourceLanguage(value.get)
      if language != langNone:
        return HandlerResult(kind: hrSetSyntaxLanguage, highlightLanguage: language)
  # A bool option refuses any other value, so that `nu=0` cannot turn it on.
  if valueAfterSpace or (spec.kind == sokBool and value.isSome):
    return rejected("E474: Invalid argument")

  if suffix == "?" or (spec.kind != sokBool and value.isNone):
    return HandlerResult(kind: hrShowOption, shownOption: spec)
  case spec.kind
  of sokBool:
    if suffix == "!" or prefix == spInv:
      HandlerResult(kind: hrToggleBoolOption, toggledOption: spec.boolOption)
    else:
      HandlerResult(
        kind: hrSetBoolOption, boolOption: spec.boolOption, boolValue: prefix == spNone
      )
  of sokInt:
    parseSetIntValue(spec, value.get)
  of sokFloat:
    parseSetFloatValue(spec, value.get)

proc executeHelp*(handler: CommandModeHandler, topic: Option[string]): HandlerResult =
  ## Execute help command (:help, :help topic) - opens the help viewer.
  HandlerResult(kind: hrEnterHelpViewer)

proc executeVSplit*(
    handler: CommandModeHandler, filename: Option[string]
): HandlerResult =
  ## Execute vertical split command (:vs, :vs filename)
  HandlerResult(kind: hrVSplit, vsplitFilename: filename)

proc executeHSplit*(
    handler: CommandModeHandler, filename: Option[string]
): HandlerResult =
  ## Execute horizontal split command (:sp, :sp filename)
  HandlerResult(kind: hrHSplit, hsplitFilename: filename)

proc executeNew*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrNew)

proc executeVnew*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrVnew)

proc executeEnew*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrEnew)

proc executeBufferNext*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferNext)

proc executeBufferPrev*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferPrev)

proc executeBufferFirst*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferFirst)

proc executeBufferLast*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferLast)

proc executeBuffer*(handler: CommandModeHandler, arg: string): HandlerResult =
  HandlerResult(kind: hrBuffer, bufferArg: arg)

proc executeBufferDelete*(
    handler: CommandModeHandler, force: bool, bufferArg: string = ""
): HandlerResult =
  ## Execute bdelete command (:bd, :bdelete). `bufferArg` names the target by
  ## number or name; empty means the current buffer. The target resolution and
  ## the modified and running-job checks live in
  ## `deleteCurrentBuffer`/`deleteBufferByArg`.
  HandlerResult(
    kind: hrBufferDelete, forceBufferDelete: force, deleteBufferArg: bufferArg
  )

proc inconsistentMessage(exc: ref TransactionRollbackError): string =
  ## A failed rollback (untrustworthy buffer) as a status message.
  exc.msg & " (buffer state may be inconsistent)"

proc stripTrailingWhitespace*(buffer: TextBuffer): Result[int, string] =
  ## Remove trailing whitespace from every line as one change: how many lines
  ## it changed. A failed rollback raises `TransactionRollbackError`.
  if buffer.readOnly:
    return err("Buffer is read-only")
  # Raw buffer: stripping may corrupt code units.
  if not buffer.allowsTextTransforms:
    return err(rawBytesRejection("strip trailing whitespace"))
  # Nothing to strip makes no change, and opens none.
  var anyTrailing = false
  for lineIdx in 0 ..< buffer.len:
    let line = buffer.getLine(lineIdx)
    if line.len > 0 and line[^1] in Whitespace:
      anyTrailing = true
      break
  if not anyTrailing:
    return ok 0
  var strippedCount = 0
  let txr = withTransaction(buffer, "stripwhitespace"):
    for lineIdx in 0 ..< buffer.len:
      let line = buffer.getLine(lineIdx)
      let trimmed = line.strip(leading = false, trailing = true)
      if trimmed != line:
        let replaceResult = buffer.replaceLine(lineIdx, trimmed)
        if replaceResult.isErr:
          return err(replaceResult.error)
        strippedCount.inc
  if txr.isErr:
    return err(txr.error)
  ok strippedCount

proc executeStripWhitespace*(buffer: TextBuffer): HandlerResult =
  ## Execute stripwhitespace command (:stripwhitespace, :stripws)
  ## Removes trailing whitespace from all lines.
  let stripped =
    try:
      buffer.stripTrailingWhitespace()
    except TransactionRollbackError as exc:
      return HandlerResult(kind: hrError, errorMessage: exc.inconsistentMessage)
  if stripped.isErr:
    return HandlerResult(kind: hrError, errorMessage: stripped.error)
  HandlerResult(kind: hrStripWhitespace, strippedLineCount: stripped.get)

proc executeQuickRun*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrQuickRun)

proc resolveAddress(
    a: ExAddress, buffer: TextBuffer, currentLine: int
): Result[int, string] =
  ## The 0-based line an address names, -1 for line 0, or why the buffer has
  ## none.
  ##
  ## The only place an address is judged: the parser cannot tell that `:0` and
  ## `:1-1` name the same line.
  let line = a.addressLine(currentLine, buffer.len - 1)
  # Line 0 is the gap above the first line and addresses it: `:0,5d` and
  # `:1-1,5d` both start at line 1. Anything further up is refused.
  if line < -1 or line >= buffer.len:
    return err("Line out of range")
  ok line

proc resolveExLines(
    buffer: TextBuffer, range: ExLineRange, currentLine: int
): Result[tuple[first, last: int], string] =
  ## The 0-based lines `range` names, folds aside, or why it names none. `%`
  ## clamps to the buffer; a typed address is refused rather than moved.
  var first, last: int
  case range.kind
  of erkAll:
    first = 0
    last = buffer.len - 1
  of erkAddresses:
    first = ?resolveAddress(range.first, buffer, currentLine)
    last = ?resolveAddress(range.last, buffer, currentLine)
    # Judged before line 0 becomes line 1, as Vim does (E493): `1,$-1` in a
    # one-line buffer is backwards, not line 1.
    if first > last:
      return err("Invalid range: start line > end line")
    first = max(first, 0)
    last = max(last, 0)
  of erkCurrent:
    if currentLine < 0 or currentLine >= buffer.len:
      return err("Line out of range")
    first = currentLine
    last = currentLine

  ok (first, last)

proc resolveExRange*(
    buffer: TextBuffer, range: ExLineRange, currentLine: int
): Result[tuple[first, last: int], string] =
  ## Turn the range an Ex command was given into the 0-based span of lines it
  ## covers, or say why it covers none: the lines it names, widened over the
  ## closed folds it reaches into.
  let (first, last) = ?buffer.resolveExLines(range, currentLine)
  # A range reaching into a closed fold covers all of its lines.
  let snapped = buffer.foldState.snapRangeToFolds(first, last)
  # Re-clamp: a stale fold can name lines past the end of the buffer.
  ok (max(0, snapped.startLine), min(snapped.endLine, buffer.len - 1))

proc executeFilter*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    command: string,
    range: ExLineRange,
    currentLine: int,
): HandlerResult =
  ## Describe a filter run for the editor to carry out asynchronously.
  if buffer.readOnly:
    return HandlerResult(kind: hrError, errorMessage: "Buffer is read-only")
  if not buffer.allowsTextTransforms:
    return HandlerResult(kind: hrError, errorMessage: rawBytesRejection("filter"))
  if command.len == 0:
    return HandlerResult(kind: hrError, errorMessage: "Filter command required")

  let resolved = buffer.resolveExRange(range, currentLine)
  if resolved.isErr:
    return HandlerResult(kind: hrError, errorMessage: resolved.error)
  let (first, last) = resolved.get

  HandlerResult(
    kind: hrFilter,
    hrFilterBufferId: buffer.id,
    hrFilterCommand: command,
    hrFilterFirst: first,
    hrFilterLast: last,
    hrFilterVersion: buffer.contentVersion,
  )

proc substituteRefusal(buffer: TextBuffer, countOnly: bool): Result[void, string] =
  ## Why :s refuses `buffer` before looking at its lines. Counting changes
  ## nothing, so a read-only buffer allows it.
  if buffer.readOnly and not countOnly:
    return err("Buffer is read-only")
  # Raw buffer: pattern may land inside code unit.
  if not buffer.allowsTextTransforms:
    return err(rawBytesRejection("substitute"))
  ok()

proc substituteLines*(
    buffer: TextBuffer, range: ExLineRange, currentLine: int, countOnly = false
): Result[tuple[first, last: int], string] =
  ## The lines :s runs on, or why it refuses before looking at its pattern.
  ?buffer.substituteRefusal(countOnly)
  buffer.resolveExRange(range, currentLine)

proc writeSubstitution(buffer: TextBuffer, spans: seq[LineEdit]): Result[void, string] =
  ## Write what :s made of its lines as one change, so the rows below shift
  ## once, not once per line. A failed rollback raises
  ## `TransactionRollbackError`.
  let txr = withTransaction(buffer, "substitute"):
    let replaceResult = buffer.replaceLineSpans(spans)
    if replaceResult.isErr:
      return err(replaceResult.error)
  if txr.isErr:
    return err(txr.error)
  ok()

proc notFoundMessage(pattern: string): string =
  "Pattern not found: " & pattern

proc notFound(pattern: string, flags: SubstituteFlags): HandlerResult =
  ## A :s that matched nothing; with `e` that is no error and says nothing.
  if flags.noError:
    HandlerResult(kind: hrSubstituteNoMatch)
  else:
    HandlerResult(kind: hrError, errorMessage: notFoundMessage(pattern))

proc countSubstitutions(
    buffer: TextBuffer,
    pattern: string,
    match: SearchMatch,
    lines: Slice[int],
    flags: SubstituteFlags,
): HandlerResult =
  ## What the `n` flag reports, as do_sub_msg does.
  var matches, matchedLines = 0
  for line in lines:
    let count = buffer.getLine(line).countSubstituteMatches(
        pattern, flags.ignoreCase, flags.global, match
      )
    matches += count
    if count > 0:
      matchedLines.inc
  if matches == 0:
    return notFound(pattern, flags)
  HandlerResult(
    kind: hrHandled,
    statusMessage:
      $matches & (if matches == 1: " match" else: " matches") & " on " & $matchedLines &
      (if matchedLines == 1: " line" else: " lines"),
  )

proc replaceMatches(
    buffer: TextBuffer,
    lines: Slice[int],
    pattern, replacement: string,
    flags: SubstituteFlags,
    match: SearchMatch,
    skipUnchanged = false,
): Result[tuple[count, lastLine: int], string] =
  ## Replace the matches of `pattern` in `lines` as one change: how many there
  ## were and the last line the change makes. With `skipUnchanged` a line that
  ## comes out as it was is not written. A failed rollback raises
  ## `TransactionRollbackError`.
  var
    count = 0
    lastLine = lines.a
    shift = 0
    spans: seq[LineEdit]
  for s in buffer.substitutions(
    lines, pattern, parseReplacement(replacement), flags.ignoreCase, flags.global, match
  ):
    count += s.count
    # The last line it makes, below what the lines above added.
    lastLine = s.line + shift + s.lines.high
    shift += s.lines.len - 1
    if not skipUnchanged or s.lines.len != 1 or s.lines[0] != buffer.getLine(s.line):
      spans.add LineEdit(start: s.line, delete: 1, insert: s.lines)
  if spans.len > 0:
    ?buffer.writeSubstitution(spans)
  ok (count: count, lastLine: lastLine)

proc executeSubstitute*(
    buffer: TextBuffer,
    pattern: string,
    replacement: string,
    flags: SubstituteFlags,
    match: SearchMatch,
    range: ExLineRange = ExLineRange(),
    currentLine: int = 0,
): HandlerResult =
  ## Execute substitute command (:s, :%s/pattern/replacement/flags), matching
  ## `pattern` as `match` says.
  let (rangeStart, rangeEnd) = buffer.substituteLines(
    range, currentLine, flags.countOnly
  ).valueOr:
    return HandlerResult(kind: hrError, errorMessage: error)
  if pattern.len == 0:
    return HandlerResult(kind: hrError, errorMessage: "Pattern required")
  let invalid = invalidRegex(pattern, flags.ignoreCase, match)
  if invalid.len > 0:
    return HandlerResult(kind: hrError, errorMessage: invalid)

  if flags.countOnly:
    return buffer.countSubstitutions(pattern, match, rangeStart .. rangeEnd, flags)

  let replaced =
    try:
      buffer.replaceMatches(rangeStart .. rangeEnd, pattern, replacement, flags, match)
    except TransactionRollbackError as exc:
      return HandlerResult(kind: hrError, errorMessage: exc.inconsistentMessage)
  let done = replaced.valueOr:
    return HandlerResult(kind: hrError, errorMessage: error)
  if done.count == 0:
    return notFound(pattern, flags)
  HandlerResult(
    kind: hrSubstitute,
    hrSubstituteCount: done.count,
    hrSubstituteLastLine: done.lastLine,
  )

proc substituteInBuffer*(
    buffer: TextBuffer,
    pattern: string,
    replacement: string,
    flags: SubstituteFlags,
    range: ExLineRange,
): Result[void, string] =
  ## A :s that edits `buffer` alone, for a hook: `range` is lines as numbered,
  ## which a closed fold does not widen, and a line that comes out as it was
  ## is left alone, so there is no change when there is nothing to change.
  ## The counting flag is not taken. `pattern` compiles, as reading the hook
  ## made sure. A failed rollback raises `TransactionRollbackError`.
  ?buffer.substituteRefusal(countOnly = false)
  let (first, last) = ?buffer.resolveExLines(range, 0)
  let done = ?buffer.replaceMatches(
    first .. last, pattern, replacement, flags, smRegex, skipUnchanged = true
  )
  if done.count == 0 and not flags.noError:
    return err(notFoundMessage(pattern))
  ok()

proc executeDelete*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    range: ExLineRange = ExLineRange(),
    currentLine: int = 0,
): HandlerResult =
  ## Execute delete command (:d, :%d, :1,10d)
  if buffer.readOnly:
    return HandlerResult(kind: hrError, errorMessage: "Buffer is read-only")
  let resolved = buffer.resolveExRange(range, currentLine)
  if resolved.isErr:
    return HandlerResult(kind: hrError, errorMessage: resolved.error)
  let (rangeStart, rangeEnd) = resolved.get

  let text = buffer.linewiseText(rangeStart, rangeEnd)

  let lineCount = rangeEnd - rangeStart + 1

  let txr =
    try:
      withTransaction(buffer, "delete lines"):
        let deleteResult = buffer.deleteLines(rangeStart, rangeEnd)
        if deleteResult.isErr:
          return HandlerResult(kind: hrError, errorMessage: deleteResult.error)
    except TransactionRollbackError as exc:
      # Surface a failed rollback (untrustworthy buffer) as a status message.
      return HandlerResult(
        kind: hrError, errorMessage: exc.msg & " (buffer state may be inconsistent)"
      )
  if txr.isErr:
    return HandlerResult(kind: hrError, errorMessage: txr.error)

  HandlerResult(
    kind: hrDeleteLines,
    hrDeletedText: text,
    hrDeletedLineCount: lineCount,
    hrDeleteStartLine: rangeStart,
  )

proc handleCommandModeInput*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    cmdResult: CommandLineResult,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Dispatch an already parsed Command mode input.
  ## isSharedBuffer: true if the buffer is shared across multiple windows
  ## currentLine: 0-based cursor line, used for range substitution with '.'
  ## otherModifiedCount: modified buffers other than `buffer` (for :qa)

  case cmdResult.kind
  of claQuit:
    handler.executeQuit(buffer, cmdResult.forceQuit, isSharedBuffer)
  of claQuitAll:
    handler.executeQuitAll(buffer, cmdResult.forceQuitAll, otherModifiedCount)
  of claSave:
    handler.executeSave(buffer, cmdResult.filename, cmdResult.forceSave)
  of claSaveAs:
    handler.executeSaveAs(cmdResult.filename, cmdResult.forceSave)
  of claSaveAll:
    handler.executeSaveAll(cmdResult.forceSaveAll)
  of claSaveAndQuit:
    handler.executeSaveAndQuit(
      buffer, cmdResult.saveFilename, cmdResult.forceSaveAndQuit
    )
  of claSaveIfModifiedAndQuit:
    handler.executeSaveIfModifiedAndQuit(
      cmdResult.saveFilename, cmdResult.forceSaveAndQuit
    )
  of claSaveAllAndQuit:
    handler.executeSaveAllAndQuit(cmdResult.forceSaveAllAndQuit)
  of claEdit:
    handler.executeEdit(buffer, cmdResult.editFilename, cmdResult.forceEdit)
  of claEnew:
    handler.executeEnew()
  of claGoto:
    handler.executeGotoLine(buffer, cmdResult.gotoAddress, currentLine)
  of claSet:
    handler.executeSet(cmdResult.option, cmdResult.value, cmdResult.valueAfterSpace)
  of claSyntax:
    if cmdResult.syntaxOn:
      HandlerResult(kind: hrSetSyntaxLanguage, followFiletype: true, allBuffers: true)
    else:
      HandlerResult(kind: hrSetBoolOption, boolOption: bsoSyntax, boolValue: false)
  of claHelp:
    handler.executeHelp(cmdResult.topic)
  of claUndo:
    HandlerResult(kind: hrUndo)
  of claRedo:
    HandlerResult(kind: hrRedo)
  of claVSplit:
    handler.executeVSplit(cmdResult.vsplitFilename)
  of claHSplit:
    handler.executeHSplit(cmdResult.hsplitFilename)
  of claNew:
    handler.executeNew()
  of claVnew:
    handler.executeVnew()
  of claBufferNext:
    handler.executeBufferNext()
  of claBufferPrev:
    handler.executeBufferPrev()
  of claBufferFirst:
    handler.executeBufferFirst()
  of claBufferLast:
    handler.executeBufferLast()
  of claBufferDelete:
    handler.executeBufferDelete(cmdResult.forceBufferDelete, cmdResult.deleteBufferArg)
  of claBuffer:
    handler.executeBuffer(cmdResult.bufferArg)
  of claStripWhitespace:
    buffer.executeStripWhitespace()
  of claFiler:
    handler.executeFiler(cmdResult.filerPath)
  of claChangeDir:
    HandlerResult(kind: hrChangeDir, changeDirPath: cmdResult.changeDirPath)
  of claPrintWorkingDir:
    HandlerResult(kind: hrPrintWorkingDir)
  of claLogViewer:
    HandlerResult(kind: hrEnterLogViewer)
  of claJobs:
    HandlerResult(kind: hrJobs, hrStopJobs: cmdResult.stopJobs)
  of claQuickRun:
    handler.executeQuickRun()
  of claBufferManager:
    HandlerResult(kind: hrEnterBufferManager)
  of claBackupManager:
    HandlerResult(kind: hrEnterBackupManager)
  of claRecoveryManager:
    HandlerResult(kind: hrEnterRecoveryManager, allRecovery: cmdResult.allRecovery)
  of claRecentFile:
    when defined(macosx):
      HandlerResult(kind: hrError, errorMessage: ":recent is not supported on macOS")
    else:
      HandlerResult(kind: hrRecentFile)
  of claClearSearchHighlight:
    HandlerResult(kind: hrClearSearchHighlight)
  of claShellCommand:
    HandlerResult(kind: hrShellCommand, shellCommand: cmdResult.shellCommand)
  of claBackground:
    HandlerResult(kind: hrBackground)
  of claJumpList:
    HandlerResult(kind: hrJumpList)
  of claChanges:
    HandlerResult(kind: hrChanges)
  of claBookmarks:
    HandlerResult(kind: hrEnterBookmarkManager)
  of claVersion:
    HandlerResult(kind: hrVersion)
  of claConflictNext:
    HandlerResult(kind: hrConflictNext)
  of claConflictPrev:
    HandlerResult(kind: hrConflictPrev)
  of claBuild:
    HandlerResult(kind: hrBuild)
  of claDebug:
    HandlerResult(kind: hrDebug)
  of claConfig:
    HandlerResult(kind: hrConfig)
  of claPutConfigFile:
    HandlerResult(kind: hrPutConfigFile)
  of claMan:
    HandlerResult(kind: hrMan, hrManPage: cmdResult.manPage)
  of claTheme:
    HandlerResult(kind: hrTheme, hrThemeName: cmdResult.themeName)
  of claLspLog:
    HandlerResult(kind: hrLspLog)
  of claLspFormat:
    HandlerResult(kind: hrLspFormat)
  of claLspRestart:
    HandlerResult(kind: hrLspRestart)
  of claLspFold:
    HandlerResult(kind: hrLspFold)
  of claLspExecuteCommand:
    HandlerResult(
      kind: hrLspExecuteCommand,
      hrLspCommand: cmdResult.lspCommand,
      hrLspCommandArgs: cmdResult.lspCommandArgs,
    )
  of claLspCallHierarchyIncoming:
    HandlerResult(kind: hrLspCallHierarchyIncoming)
  of claLspCallHierarchyOutgoing:
    HandlerResult(kind: hrLspCallHierarchyOutgoing)
  of claTerminal:
    HandlerResult(
      kind: hrEnterTerminal, enterTerminalCommand: cmdResult.terminalCommand
    )
  of claSubstitute:
    executeSubstitute(
      buffer, cmdResult.pattern, cmdResult.replacement, cmdResult.substituteFlags,
      cmdResult.match, cmdResult.substituteRange, currentLine,
    )
  of claFilter:
    handler.executeFilter(
      buffer, cmdResult.filterCommand, cmdResult.filterRange, currentLine
    )
  of claDeleteLines:
    handler.executeDelete(buffer, cmdResult.deleteRange, currentLine)
  of claMap, claNmap, claImap, claVmap, claRmap, claCmap:
    let modes = modesForMapAction(cmdResult.kind)
    if cmdResult.mapRhs == "":
      # No rhs: list mappings. mapLhs (if any) filters by prefix.
      HandlerResult(
        kind: hrMapList, mapListModes: modes, mapListPrefix: cmdResult.mapLhs
      )
    else:
      HandlerResult(
        kind: hrMapAdd,
        mapAddLhs: cmdResult.mapLhs,
        mapAddRhs: cmdResult.mapRhs,
        mapAddModes: modes,
        mapAddNoremap: cmdResult.noremap,
      )
  of claNoremap, claNnoremap, claInoremap, claVnoremap, claCnoremap:
    # Unreachable: the executor folds these onto the base map kind (carrying
    # noremap=true). Present only to keep the case exhaustive.
    HandlerResult(kind: hrError, errorMessage: "internal: unfolded noremap action")
  of claUnmap, claNunmap, claIunmap, claVunmap, claRunmap, claCunmap:
    HandlerResult(
      kind: hrMapRemove,
      mapRemoveLhs: cmdResult.unmapLhs,
      mapRemoveModes: modesForMapAction(cmdResult.kind),
    )
  of claMapclear, claNmapclear, claImapclear, claVmapclear, claRmapclear, claCmapclear:
    HandlerResult(kind: hrMapClear, mapClearModes: modesForMapAction(cmdResult.kind))
  of claOnlyWindow:
    HandlerResult(kind: hrOnlyWindow)
  of claEditConfigFile:
    let configPath = getConfigPath()
    HandlerResult(kind: hrEdit, editFilename: some(configPath), forceEdit: false)
  of claFileTree:
    HandlerResult(
      kind: hrEnterFileTree,
      enterFileTreePath:
        if cmdResult.kind == claFileTree:
          cmdResult.fileTreePath
        else:
          none(string),
    )
  of claCquit:
    HandlerResult(kind: hrCquit)
  of claPicker:
    HandlerResult(kind: hrPickerEnter, pickerSpec: cmdResult.pickerSpec)
  of claUnknown:
    HandlerResult(kind: hrError, errorMessage: cmdResult.errorMessage)

proc handleCommandModeInput*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Parse and dispatch Command mode text, including an empty `:` overlay.
  if commandText.len <= 1:
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: ""
    )
  handler.handleCommandModeInput(
    buffer,
    handler.parser.parseAndExecute(commandText),
    isSharedBuffer,
    currentLine,
    otherModifiedCount,
  )
