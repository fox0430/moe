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

## Register system for vim-style text operations
##
## This module provides a comprehensive register system similar to Vim:
## - Unnamed register ("): The default register for all operations
## - Numbered registers (0-9): 0 for yank, 1-9 for delete history
##   (deletes over lines, or over `%`, `}`, `n` and the like; shorter
##   deletions go to `-`)
## - Named registers (a-z, A-Z): User-defined registers (uppercase appends)
## - Small delete register (-): For deletions less than one line
## - Clipboard registers (*, +): System clipboard integration

import std/[monotimes, options, strutils, tables, times]

import pkg/results

import config, clipboard_backend, logger, register_names
import types/registers_types

export registers_types, register_names

proc initRegisters*(): Registers =
  ## Initialize a new register set
  result = Registers(
    noNamed: Register(),
    smallDelete: Register(),
    named: initTable[char, Register](),
    primarySelection: Register(),
    clipboardSelection: Register(),
    clipboardReadOutcome: croNotAttempted,
    clipboardReadError: "",
    primaryReadOutcome: croNotAttempted,
    primaryReadError: "",
    lastClipboardWriteTime: MonoTime(),
  )

  # Initialize number registers
  for i in 0 .. 9:
    result.number[i] = Register()

  # Initialize named registers
  for c in 'a' .. 'z':
    result.named[c] = Register()

proc setClipboardTool*(r: Registers, tool: ClipboardTool) =
  ## Set the clipboard tool for system clipboard integration
  r.clipboardTool = some(tool)
  r.clipboardReadOutcome = croNotAttempted
  r.clipboardReadError = ""
  r.clipboardReadValue = ""
  r.primaryReadOutcome = croNotAttempted
  r.primaryReadError = ""
  r.primaryReadValue = ""

proc isLine*(r: Register): bool =
  ## The register goes in as whole lines.
  r.kind == rkLines

proc isEmpty*(r: Register): bool =
  ## The register was never written, as Vim's y_array is NULL: a put of it is
  ## E353. What an empty yank leaves is one empty line, which puts nothing.
  r.buffer.len == 0

proc isWithinLine(r: Register): bool =
  ## No line break, as a delete Vim's op_delete puts in "- (line_count 1).
  r.kind != rkLines and r.buffer.len <= 1 and
    (r.buffer.len == 0 or '\n' notin r.buffer[0])

proc holdsNoText*(r: Register): bool =
  ## Not even a line break, as what a delete within an empty line takes.
  r.isWithinLine and (r.buffer.len == 0 or r.buffer[0].len == 0)

proc getContent*(r: Register): string =
  ## The register's text. Linewise text ends every line with a line break,
  ## a block every row but the last, as Vim's getreg() gives it.
  if r.buffer.len == 0:
    ""
  elif r.kind == rkLines:
    r.buffer.join("\n") & "\n"
  else:
    r.buffer.join("\n")

proc selectionContent*(r: Register): string =
  ## The register's text as a system selection holds it: a block's rows each
  ## end in a line break, as Vim's clip_convert_selection gives them.
  if r.kind == rkBlock and r.buffer.len > 0:
    r.getContent & "\n"
  else:
    r.getContent

proc getLines*(r: Register): seq[string] =
  ## Get register content as lines
  r.buffer

proc withoutLastLineBreak*(text: string): string =
  ## Linewise text without the line break that ends its last line.
  if text.endsWith('\n'):
    text[0 ..^ 2]
  else:
    text

proc linewiseLines*(text: string): seq[string] =
  ## The lines of linewise text: a line break that ends it ends its last line
  ## rather than starting another, as Vim's setreg() takes it. Only LF breaks
  ## lines; a CR stays in the line it is in.
  text.withoutLastLineBreak.split('\n')

proc toRegister*(content: string, isLine: bool): Register =
  ## `content` as a register holds it.
  if isLine:
    Register(kind: rkLines, buffer: content.linewiseLines)
  else:
    Register(kind: rkChars, buffer: @[content])

proc asLines(r: Register): seq[string] =
  ## The register's text as lines, charwise text split at its line breaks.
  if r.kind == rkChars:
    r.getContent.split('\n')
  else:
    r.buffer

proc selectionText(raw: string): string =
  ## Text read from a system selection, its CRLF line breaks made LF.
  raw.replace("\r\n", "\n")

proc fromSelection(text: string): Register =
  ## `selectionText` as a register holds it: linewise when it ends in a line
  ## break, as Vim takes the clipboard, and nothing when the selection is.
  if text.len == 0:
    Register()
  else:
    toRegister(text, text.endsWith('\n'))

proc shows(reg: Register, raw: string): bool =
  ## `raw`, read from a system selection, is `reg`'s text: as it was written,
  ## or with its line breaks made CRLF by the selection. A raw buffer's CR
  ## stays in its lines, so the text is not made LF before comparing.
  let own = reg.selectionContent
  raw == own or ('\r' in raw and raw.selectionText == own)

proc appended(r: Register, text: Register): Register =
  ## `r` with `text` added after it, as `"A` adds in Vim's op_yank: linewise
  ## if `text` is, else of `r`'s kind. Added to characters, the text continues
  ## the last line; to lines or a block, it starts a line or row of its own,
  ## and the block keeps its width. A register that kept even an empty yank
  ## is added to.
  if r.isEmpty:
    return text
  let kind = if text.kind == rkLines: rkLines else: r.kind
  case kind
  of rkChars:
    Register(kind: rkChars, buffer: @[r.getContent & text.getContent])
  of rkLines:
    Register(kind: rkLines, buffer: r.asLines & text.asLines)
  of rkBlock:
    blockRegister(r.buffer & text.asLines, r.width)

# Clipboard integration (synchronous so that put-time reads see the writes)

proc sendToClipboard(r: Registers, reg: Register) =
  ## Send to system CLIPBOARD and sync `+` cache.
  if r.clipboardTool.isSome:
    let writeResult = writeToClipboardSync(r.clipboardTool.get, reg.selectionContent)
    if writeResult.isErr:
      logError "registers", "Failed to write to CLIPBOARD: " & writeResult.error
    else:
      r.clipboardSelection = reg
      if not writeResult.get:
        r.lastClipboardWriteTime = getMonoTime()

proc sendToPrimarySelection(r: Registers, reg: Register) =
  ## Send to X11 PRIMARY selection if available (synchronous) and sync the `*`
  ## cache, so that reading it back keeps the register's kind.
  if r.clipboardTool.isSome:
    let writeResult =
      writeToPrimarySelectionSync(r.clipboardTool.get, reg.selectionContent)
    if writeResult.isErr:
      logError "registers", "Failed to write to PRIMARY: " & writeResult.error
    else:
      r.primarySelection = reg

proc getFromClipboard(r: Registers): Result[string, string] =
  ## Get CLIPBOARD content. Records outcome for fallback reuse.
  if r.clipboardTool.isNone:
    r.clipboardReadOutcome = croNotAttempted
    r.clipboardReadError = ""
    r.clipboardReadValue = ""
    return err("No clipboard tool configured")
  result = readFromClipboardSync(r.clipboardTool.get)
  if result.isOk:
    r.clipboardReadOutcome = croSucceeded
    r.clipboardReadError = ""
    r.clipboardReadValue = result.get
  else:
    r.clipboardReadOutcome = croFailed
    r.clipboardReadError = result.error
    r.clipboardReadValue = ""

proc getFromPrimarySelection(r: Registers): Result[string, string] =
  ## Get PRIMARY content. Records outcome for fallback reuse.
  if r.clipboardTool.isNone:
    r.primaryReadOutcome = croNotAttempted
    r.primaryReadError = ""
    r.primaryReadValue = ""
    return err("No clipboard tool configured")
  result = readFromPrimarySelectionSync(r.clipboardTool.get)
  if result.isOk:
    r.primaryReadOutcome = croSucceeded
    r.primaryReadError = ""
    r.primaryReadValue = result.get
  else:
    r.primaryReadOutcome = croFailed
    r.primaryReadError = result.error
    r.primaryReadValue = ""

proc markClipboardWritten*(r: Registers, text: Register, writeConfirmed: bool) =
  ## Record that CLIPBOARD was sent `text` and sync registers.
  r.noNamed = text
  r.clipboardSelection = text
  if not writeConfirmed:
    r.lastClipboardWriteTime = getMonoTime()

# Writing registers, as Vim's op_yank and op_delete

proc slot(r: Registers, name: char): var Register =
  ## The register `name` writes to. A name with no register of its own writes
  ## to "0, as `""yy` does in Vim's get_yank_register.
  if name.isNumberRegisterName:
    return r.number[ord(name) - ord('0')]
  elif name.isNamedRegisterName:
    return r.named[name.toLowerAscii]
  elif name.isSmallDeleteRegisterName:
    return r.smallDelete
  elif name.isPrimarySelectionRegisterName:
    return r.primarySelection
  elif name.isClipboardSelectionRegisterName:
    return r.clipboardSelection
  else:
    return r.number[0]

proc yankInto(r: Registers, name: char, text: Register): Register =
  ## Write `text` to the register `name` names, adding to it for A-Z, and
  ## return what that register then holds. The clipboard registers also go
  ## to their system selection.
  result =
    if name in {'A' .. 'Z'}:
      r.slot(name).appended(text)
    else:
      text
  r.slot(name) = result
  if name.isPrimarySelectionRegisterName:
    r.sendToPrimarySelection(result)
  elif name.isClipboardSelectionRegisterName:
    r.sendToClipboard(result)

proc setUnnamed(r: Registers, text: Register, wroteClipboard: bool) =
  ## Make the unnamed register hold `text`, the register written last, and
  ## send it to the system selections unless a clipboard register was just
  ## written. The unnamed register mirrors CLIPBOARD, as Vim's
  ## clipboard=unnamedplus: a put reads CLIPBOARD back, so after `"*y` it puts
  ## what CLIPBOARD holds, as Vim does.
  r.noNamed = text
  if not wroteClipboard:
    r.sendToClipboard(text)
    r.sendToPrimarySelection(text)

proc storeYanked*(r: Registers, name: Option[char], text: Register) =
  ## Store yanked text in the register `"x` named, else in "0, and make the
  ## unnamed register hold it. The black hole register keeps nothing.
  let target = name.get('0')
  if target.isBlackHoleRegisterName:
    return
  r.setUnnamed(r.yankInto(target, text), target.isClipboardRegisterName)

proc storeYanked*(r: Registers, name: Option[char], content: string, isLine: bool) =
  ## `storeYanked` of characters or lines.
  r.storeYanked(name, toRegister(content, isLine))

proc storeDeleted*(
    r: Registers, name: Option[char], text: Register, useRegOne = false
) =
  ## Store deleted text as Vim's op_delete: in the register `"x` named; in "1,
  ## shifting "1-"8 down, when it is linewise, spans lines or `useRegOne` (the
  ## motion was `%`, `}`, `n` and the like); and in "- when it is within a
  ## line and no register, or a clipboard one, was named. The unnamed
  ## register holds it, or all of the register it was added to with `"A`.
  ## The black hole register keeps nothing.
  if name.isSome and name.get.isBlackHoleRegisterName:
    return
  let withinLine = text.isWithinLine
  var unnamed = text
  if name.isSome:
    unnamed = r.yankInto(name.get, text)
  if not withinLine or useRegOne:
    for i in countdown(8, 1):
      r.number[i + 1] = r.number[i]
    r.number[1] = text
    if name.isNone or name.get notin {'A' .. 'Z'}:
      unnamed = text
  # The unnamed register mirrors the system selections, as Vim's
  # clipboard=unnamed,unnamedplus, which fills "- for `"*` and `"+` too.
  if withinLine and (name.isNone or name.get.isClipboardRegisterName):
    r.smallDelete = text
  r.setUnnamed(unnamed, name.isSome and name.get.isClipboardRegisterName)

proc storeDeleted*(
    r: Registers, name: Option[char], content: string, isLine: bool, useRegOne = false
) =
  ## `storeDeleted` of characters or lines.
  r.storeDeleted(name, toRegister(content, isLine), useRegOne)

proc setRegister*(
    r: Registers, name: char, content: string, isLine: bool
): Result[(), string] =
  ## Write the register `name` as Vim's setreg() does: the unnamed register
  ## still holds what it did, unless `name` is `"`, which writes "0 and makes
  ## it the unnamed register.
  if not name.isValidRegisterName:
    return err("Invalid register name: " & $name)
  if name.isBlackHoleRegisterName:
    return ok(())
  let written = r.yankInto(name, toRegister(content, isLine))
  if name == '"':
    r.setUnnamed(written, wroteClipboard = false)
  ok(())

proc isWithinClipboardClaimWindow(r: Registers): bool =
  ## True while the wl-copy claim may still serve the pre-write content.
  ## The zero write-time (no write yet) must not open the window.
  r.clipboardTool == some(cbtWlClipboard) and r.lastClipboardWriteTime != MonoTime() and
    getMonoTime() - r.lastClipboardWriteTime < initDuration(milliseconds = 500)

proc restartClipboardClaimWindow*(r: Registers) =
  ## Restart the wl-copy claim window from now (test seam).
  r.lastClipboardWriteTime = getMonoTime()

proc expireClipboardClaimWindow*(r: Registers) =
  ## Expire the claim window by zeroing the write time (test seam).
  r.lastClipboardWriteTime = MonoTime()

proc setClipboardWriteAgo*(r: Registers, millisecondsAgo: int) =
  ## Test seam: place the last CLIPBOARD write `millisecondsAgo` in the past
  ## to pin the claim window to either side of its boundary.
  r.lastClipboardWriteTime =
    getMonoTime() - initDuration(milliseconds = millisecondsAgo)

# Public API for getting registers

proc tryUpdateClipboardSelectionRegister(r: Registers) =
  ## Try to update clipboard selection register from system CLIPBOARD
  let clipResult = r.getFromClipboard()
  if clipResult.isOk:
    let content = clipResult.get
    if content.len > 0 and not r.clipboardSelection.shows(content):
      if not r.isWithinClipboardClaimWindow:
        r.clipboardSelection = content.selectionText.fromSelection
    elif content.len > 0 and r.isWithinClipboardClaimWindow:
      # The write has landed: close the claim window so external changes
      # are adopted again.
      r.lastClipboardWriteTime = MonoTime()

proc tryUpdatePrimarySelectionRegister(r: Registers) =
  ## Try to update primary selection register from system PRIMARY selection
  let clipResult = r.getFromPrimarySelection()
  if clipResult.isOk:
    let content = clipResult.get
    if content.len > 0 and not r.primarySelection.shows(content):
      r.primarySelection = content.selectionText.fromSelection

proc getNoNamedRegister*(r: Registers): Register =
  ## Get unnamed register, syncing with system CLIPBOARD.
  let clipResult = r.getFromClipboard()
  if clipResult.isOk:
    let clipContent = clipResult.get
    if clipContent.len > 0 and not r.noNamed.shows(clipContent):
      if not r.isWithinClipboardClaimWindow:
        r.noNamed = clipContent.selectionText.fromSelection
    elif clipContent.len > 0 and r.isWithinClipboardClaimWindow:
      r.lastClipboardWriteTime = MonoTime()
  else:
    logDebug "registers",
      "Clipboard read failed, falling back to internal register: " & clipResult.error

  r.noNamed

proc getSmallDeleteRegister*(r: Registers): Register =
  ## Get the small delete register (-)
  r.smallDelete

proc getNumberRegister*(r: Registers, num: int): Register =
  ## Get a number register (0-9)
  if num >= 0 and num <= 9:
    r.number[num]
  else:
    Register()

proc getNumberRegister*(r: Registers, c: char): Register =
  ## Get a number register by character
  if c.isNumberRegisterName:
    r.number[ord(c) - ord('0')]
  else:
    Register()

proc getNamedRegister*(r: Registers, name: char): Register =
  ## Get a named register (a-z)
  let lowerName = name.toLowerAscii
  if lowerName in r.named:
    r.named[lowerName]
  else:
    Register()

proc getClipboardRegister*(r: Registers, name: char): Register =
  ## Get clipboard register by name, updating from the appropriate system selection
  ## '*' -> PRIMARY selection, '+' or '~' -> CLIPBOARD selection
  if name.isPrimarySelectionRegisterName:
    r.tryUpdatePrimarySelectionRegister()
    r.primarySelection
  else:
    r.tryUpdateClipboardSelectionRegister()
    r.clipboardSelection

proc getClipboardRegister*(r: Registers): Register =
  ## Get clipboard register (defaults to CLIPBOARD selection '+')
  r.getClipboardRegister('+')

proc getRegister*(r: Registers, name: char): Register =
  ## Get any register by name
  if name == '"':
    r.getNoNamedRegister()
  elif name.isNumberRegisterName:
    r.getNumberRegister(name)
  elif name.isNamedRegisterName:
    r.getNamedRegister(name)
  elif name.isSmallDeleteRegisterName:
    r.getSmallDeleteRegister()
  elif name.isClipboardRegisterName:
    r.getClipboardRegister(name)
  else:
    Register()

proc clipboardFallbackRead*(
    r: Registers, tool: ClipboardTool, registerName: char
): Result[string, string] =
  ## Fallback for empty paste; reuses cached read to avoid second tool spawn.
  let cacheApplies = r.clipboardTool.isSome and r.clipboardTool.get == tool
  if registerName.isPrimarySelectionRegisterName:
    # PRIMARY only reuses PRIMARY outcome.
    if cacheApplies and r.primaryReadOutcome != croNotAttempted:
      let outcome = r.primaryReadOutcome
      r.primaryReadOutcome = croNotAttempted
      if outcome == croFailed:
        return err(r.primaryReadError)
      return ok(r.primaryReadValue)
    return readFromPrimarySelectionSync(tool)
  if cacheApplies and r.clipboardReadOutcome != croNotAttempted and
      (registerName == '"' or registerName.isClipboardSelectionRegisterName):
    let outcome = r.clipboardReadOutcome
    r.clipboardReadOutcome = croNotAttempted
    if outcome == croFailed:
      return err(r.clipboardReadError)
    return ok(r.clipboardReadValue)
  return readFromClipboardSync(tool)

proc nothingInRegister*(name: char): string =
  ## The error for putting the empty register `name` (Vim's E353).
  "E353: Nothing in register " & $name

proc textToPut*(
    r: Registers, name: char, clipboard: ClipboardConfig
): Result[Register, string] =
  ## What a put of the register `name` puts. An empty register that shows a
  ## system selection reads it. An empty result is nothing to put, Vim's
  ## E353. Fails only when reading the selection does.
  let reg = r.getRegister(name)
  if not reg.isEmpty or not name.showsSelection or not clipboard.enable:
    return ok(reg)
  ok((?r.clipboardFallbackRead(clipboard.tool, name)).selectionText.fromSelection)

proc getRegisterContent*(r: Registers, name: char): string =
  ## Get register content as string
  r.getRegister(name).getContent()

proc isRegisterLinewise*(r: Registers, name: char): bool =
  ## Check if register content is linewise
  r.getRegister(name).isLine
