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
## - Named registers (a-z, A-Z): User-defined registers (uppercase appends)
## - Small delete register (-): For deletions less than one line
## - Clipboard registers (*, +): System clipboard integration

import std/[options, strutils, tables]

import pkg/results

import config, clipboard
import types/registers_types

export registers_types

proc initRegisters*(): Registers =
  ## Initialize a new register set
  result = Registers(
    noNamed: Register(isLine: false, buffer: @[]),
    smallDelete: Register(isLine: false, buffer: @[]),
    named: initTable[char, Register](),
    primarySelection: Register(isLine: false, buffer: @[]),
    clipboardSelection: Register(isLine: false, buffer: @[]),
  )

  # Initialize number registers
  for i in 0 .. 9:
    result.number[i] = Register(isLine: false, buffer: @[])

  # Initialize named registers
  for c in 'a' .. 'z':
    result.named[c] = Register(isLine: false, buffer: @[])

proc setClipboardTool*(r: Registers, tool: ClipboardTool) =
  ## Set the clipboard tool for system clipboard integration
  r.clipboardTool = some(tool)

proc isNamedRegisterName*(c: char): bool =
  ## Check if character is a valid named register name (a-z or A-Z)
  c in {'a' .. 'z', 'A' .. 'Z'}

proc isNumberRegisterName*(c: char): bool =
  ## Check if character is a valid number register name (0-9)
  c in {'0' .. '9'}

proc isSmallDeleteRegisterName*(c: char): bool =
  ## Check if character is the small delete register name (-)
  c == '-'

proc isPrimarySelectionRegisterName*(c: char): bool =
  ## Check if character is the primary selection register name (*)
  c == '*'

proc isClipboardSelectionRegisterName*(c: char): bool =
  ## Check if character is the clipboard selection register name (+, ~)
  c in {'+', '~'}

proc isClipboardRegisterName*(c: char): bool =
  ## Check if character is any clipboard register name (*, +, ~)
  c.isPrimarySelectionRegisterName or c.isClipboardSelectionRegisterName

proc isValidRegisterName*(c: char): bool =
  ## Check if character is any valid register name
  c.isNamedRegisterName or c.isNumberRegisterName or c.isSmallDeleteRegisterName or
    c.isClipboardRegisterName or c == '"'

proc isEmpty*(r: Register): bool =
  ## Check if register is empty
  r.buffer.len == 0 or (r.buffer.len == 1 and r.buffer[0].len == 0)

proc getContent*(r: Register): string =
  ## Get register content as a single string
  if r.buffer.len == 0:
    return ""
  elif r.isLine:
    return r.buffer.join("\n")
  else:
    return r.buffer.join("")

proc getLines*(r: Register): seq[string] =
  ## Get register content as lines
  r.buffer

# Private helpers for setting register content

proc setRegister(r: var Register, content: string, isLine: bool) =
  ## Set register content from a string
  r.isLine = isLine
  if isLine:
    r.buffer = content.splitLines()
  else:
    r.buffer = @[content]

proc setRegister(r: var Register, lines: seq[string], isLine: bool) =
  ## Set register content from lines
  r.isLine = isLine
  r.buffer = lines

proc appendRegister(r: var Register, content: string, isLine: bool) =
  ## Append content to register (vim `"A` semantics: linewise wins).
  if r.buffer.len == 0:
    r.setRegister(content, isLine)
  elif isLine or r.isLine:
    r.buffer.add(content.splitLines())
    r.isLine = true
  else:
    r.buffer[^1].add(content)

# Clipboard integration (uses async clipboard module)

proc sendToClipboard(r: Registers, content: string) =
  ## Send content to system CLIPBOARD selection if available (fire-and-forget)
  if r.clipboardTool.isSome:
    writeToClipboardAsync(r.clipboardTool.get, content)

proc sendToPrimarySelection(r: Registers, content: string) =
  ## Send content to X11 PRIMARY selection if available (fire-and-forget)
  if r.clipboardTool.isSome:
    writeToPrimarySelectionAsync(r.clipboardTool.get, content)

proc getFromClipboard(r: Registers): Result[string, string] =
  ## Get content from system CLIPBOARD selection if available
  if r.clipboardTool.isNone:
    return err("No clipboard tool configured")
  return readFromClipboardSync(r.clipboardTool.get)

proc getFromPrimarySelection(r: Registers): Result[string, string] =
  ## Get content from X11 PRIMARY selection if available
  if r.clipboardTool.isNone:
    return err("No clipboard tool configured")
  return readFromPrimarySelectionSync(r.clipboardTool.get)

# Public API for setting registers

proc setNoNamedRegister*(r: Registers, content: string, isLine: bool) =
  ## Set the unnamed register (") and sync to clipboard and primary selection
  r.noNamed.setRegister(content, isLine)
  r.sendToClipboard(content)
  r.sendToPrimarySelection(content)

proc setNoNamedRegister*(r: Registers, lines: seq[string], isLine: bool) =
  ## Set the unnamed register from lines
  r.noNamed.setRegister(lines, isLine)
  let joined = lines.join("\n")
  r.sendToClipboard(joined)
  r.sendToPrimarySelection(joined)

proc setSmallDeleteRegister*(r: Registers, content: string) =
  ## Set the small delete register (-) for deletions less than one line
  r.smallDelete.setRegister(content, false)
  r.setNoNamedRegister(content, false)

proc setYankedRegister*(r: Registers, content: string, isLine: bool) =
  ## Set register 0 (yank register) and unnamed register
  r.number[0].setRegister(content, isLine)
  r.setNoNamedRegister(content, isLine)

proc setYankedRegister*(r: Registers, lines: seq[string], isLine: bool) =
  ## Set register 0 (yank register) from lines
  r.number[0].setRegister(lines, isLine)
  r.setNoNamedRegister(lines, isLine)

proc setDeletedRegister*(r: Registers, content: string, isLine: bool) =
  ## Set delete register with history shift
  ## - If linewise or multiline: goes to register 1, shifting 1-8 to 2-9
  ## - If characterwise single line: goes to small delete register (-)
  if isLine or content.contains('\n'):
    # Shift registers 1-8 to 2-9
    for i in countdown(8, 1):
      r.number[i + 1] = r.number[i]
    r.number[1].setRegister(content, isLine)
    r.setNoNamedRegister(content, isLine)
  else:
    r.setSmallDeleteRegister(content)

proc setDeletedRegister*(r: Registers, lines: seq[string], isLine: bool) =
  ## Set delete register from lines with history shift
  # Shift registers 1-8 to 2-9
  for i in countdown(8, 1):
    r.number[i + 1] = r.number[i]
  r.number[1].setRegister(lines, isLine)
  r.setNoNamedRegister(lines, isLine)

proc setNamedRegister*(
    r: Registers, name: char, content: string, isLine: bool
): Result[(), string] =
  ## Set a named register (a-z overwrites, A-Z appends)
  if not name.isNamedRegisterName:
    return err("Invalid register name: " & $name)

  let lowerName = name.toLowerAscii
  if name in {'A' .. 'Z'}:
    # Uppercase: append to register
    r.named[lowerName].appendRegister(content, isLine)
  else:
    # Lowercase: overwrite register
    r.named[lowerName].setRegister(content, isLine)

  r.setNoNamedRegister(content, isLine)
  ok(())

proc setNamedRegister*(
    r: Registers, name: char, lines: seq[string], isLine: bool
): Result[(), string] =
  ## Set a named register from lines
  if not name.isNamedRegisterName:
    return err("Invalid register name: " & $name)

  let lowerName = name.toLowerAscii
  if name in {'A' .. 'Z'}:
    r.named[lowerName].appendRegister(lines.join("\n"), isLine)
  else:
    r.named[lowerName].setRegister(lines, isLine)

  r.setNoNamedRegister(lines, isLine)
  ok(())

proc setClipboardRegister*(r: Registers, name: char, content: string, isLine: bool) =
  ## Set clipboard register by name and sync to the appropriate system selection
  ## '*' -> PRIMARY selection, '+' or '~' -> CLIPBOARD selection
  if name.isPrimarySelectionRegisterName:
    r.primarySelection.setRegister(content, isLine)
    r.sendToPrimarySelection(content)
  else:
    r.clipboardSelection.setRegister(content, isLine)
    r.sendToClipboard(content)
  r.noNamed.setRegister(content, isLine)

proc setClipboardRegister*(r: Registers, content: string, isLine: bool) =
  ## Set clipboard register (defaults to CLIPBOARD selection '+')
  r.setClipboardRegister('+', content, isLine)

proc setRegister*(
    r: Registers, name: char, content: string, isLine: bool
): Result[(), string] =
  ## Set any register by name
  ## " - unnamed register
  ## 0-9 - number registers
  ## a-z/A-Z - named registers
  ## - - small delete register
  ## *, + - clipboard registers
  if name == '"':
    r.setNoNamedRegister(content, isLine)
    ok(())
  elif name.isNumberRegisterName:
    let idx = ord(name) - ord('0')
    r.number[idx].setRegister(content, isLine)
    r.setNoNamedRegister(content, isLine)
    ok(())
  elif name.isNamedRegisterName:
    r.setNamedRegister(name, content, isLine)
  elif name.isSmallDeleteRegisterName:
    r.smallDelete.setRegister(content, false)
    r.setNoNamedRegister(content, false)
    ok(())
  elif name.isClipboardRegisterName:
    r.setClipboardRegister(name, content, isLine)
    ok(())
  else:
    err("Invalid register name: " & $name)

# Public API for getting registers

proc tryUpdateClipboardSelectionRegister(r: Registers) =
  ## Try to update clipboard selection register from system CLIPBOARD
  let clipResult = r.getFromClipboard()
  if clipResult.isOk:
    let content = clipResult.get
    if content.len > 0 and content != r.clipboardSelection.getContent:
      let hasNewline = content.contains('\n')
      r.clipboardSelection.setRegister(content, hasNewline)

proc tryUpdatePrimarySelectionRegister(r: Registers) =
  ## Try to update primary selection register from system PRIMARY selection
  let clipResult = r.getFromPrimarySelection()
  if clipResult.isOk:
    let content = clipResult.get
    if content.len > 0 and content != r.primarySelection.getContent:
      let hasNewline = content.contains('\n')
      r.primarySelection.setRegister(content, hasNewline)

proc getNoNamedRegister*(r: Registers): Register =
  ## Get the unnamed register, syncing with system clipboard and primary selection.
  ## Behaves like Vim's clipboard=unnamed,unnamedplus:
  ## moe writes to both CLIPBOARD and PRIMARY on yank/delete, so if they differ,
  ## an external app changed one of them. Use the externally changed one.
  ## If both differ from internal, prefer PRIMARY (mouse selection is more recent).
  var clipContent = ""
  var primaryContent = ""

  let clipResult = r.getFromClipboard()
  if clipResult.isOk:
    clipContent = clipResult.get

  let primaryResult = r.getFromPrimarySelection()
  if primaryResult.isOk:
    primaryContent = primaryResult.get

  let current = r.noNamed.getContent
  let clipChanged = clipContent.len > 0 and clipContent != current
  let primaryChanged = primaryContent.len > 0 and primaryContent != current

  # TODO: Cache the last written value to avoid spawning external processes on
  # every paste when the clipboard hasn't changed.

  if primaryChanged and clipChanged:
    # Both differ from internal register. If CLIPBOARD == PRIMARY, an external
    # app set both (e.g. Ctrl+C). Otherwise, they diverged: prefer the one
    # that differs from the other (i.e. the more recently changed one).
    # Since moe sets both to the same value, if PRIMARY != CLIPBOARD,
    # it means an external app changed one after moe's last write.
    if primaryContent != clipContent:
      # PRIMARY was changed independently (mouse selection) — prefer it
      let hasNewline = primaryContent.contains('\n')
      r.noNamed.setRegister(primaryContent, hasNewline)
    else:
      # Both changed to the same value (external Ctrl+C) — use either
      let hasNewline = clipContent.contains('\n')
      r.noNamed.setRegister(clipContent, hasNewline)
  elif primaryChanged:
    # Only PRIMARY changed (mouse selection in external app)
    let hasNewline = primaryContent.contains('\n')
    r.noNamed.setRegister(primaryContent, hasNewline)
  elif clipChanged:
    # Only CLIPBOARD changed (Ctrl+C in external app)
    let hasNewline = clipContent.contains('\n')
    r.noNamed.setRegister(clipContent, hasNewline)

  r.noNamed

proc getSmallDeleteRegister*(r: Registers): Register =
  ## Get the small delete register (-)
  r.smallDelete

proc getNumberRegister*(r: Registers, num: int): Register =
  ## Get a number register (0-9)
  if num >= 0 and num <= 9:
    r.number[num]
  else:
    Register(isLine: false, buffer: @[])

proc getNumberRegister*(r: Registers, c: char): Register =
  ## Get a number register by character
  if c.isNumberRegisterName:
    r.number[ord(c) - ord('0')]
  else:
    Register(isLine: false, buffer: @[])

proc getNamedRegister*(r: Registers, name: char): Register =
  ## Get a named register (a-z)
  let lowerName = name.toLowerAscii
  if lowerName in r.named:
    r.named[lowerName]
  else:
    Register(isLine: false, buffer: @[])

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
    Register(isLine: false, buffer: @[])

proc getRegisterContent*(r: Registers, name: char): string =
  ## Get register content as string
  r.getRegister(name).getContent()

proc isRegisterLinewise*(r: Registers, name: char): bool =
  ## Check if register content is linewise
  r.getRegister(name).isLine
