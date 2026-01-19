#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[options, strutils, tables, osproc, streams]

import pkg/results

import config

type
  Register* = object ## A single register containing text
    isLine*: bool ## Whether the content is linewise (vs characterwise)
    buffer*: seq[string] ## Content lines

  Registers* = ref object ## Container for all register types
    clipboardTool: Option[ClipboardTool]

    noNamed: Register ## The unnamed register (") - latest yank/delete content

    smallDelete: Register ## Small delete register (-) - deleted text less than one line

    number: array[10, Register]
      ## Numbered registers (0-9)
      ## 0: Most recent yank
      ## 1-9: Delete history (1 is most recent, shifts on new delete)

    named: Table[char, Register]
      ## Named registers (a-z)
      ## Lowercase overwrites, uppercase appends

    clipboard: Register ## Clipboard register (*, +) - system clipboard content

proc initRegisters*(): Registers =
  ## Initialize a new register set
  result = Registers(
    noNamed: Register(isLine: false, buffer: @[]),
    smallDelete: Register(isLine: false, buffer: @[]),
    named: initTable[char, Register](),
    clipboard: Register(isLine: false, buffer: @[]),
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

proc isClipboardRegisterName*(c: char): bool =
  ## Check if character is a clipboard register name (*, +, ~)
  ## Note: All three registers point to the same system clipboard
  c in {'*', '+', '~'}

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
  ## Append content to register
  if r.buffer.len == 0:
    r.setRegister(content, isLine)
  elif isLine:
    let newLines = content.splitLines()
    r.buffer.add(newLines)
    r.isLine = true
  else:
    if r.buffer.len > 0:
      r.buffer[^1].add(content)
    else:
      r.buffer = @[content]

# Clipboard integration (self-contained to avoid circular imports)

proc getClipboardCommand(tool: ClipboardTool, operation: string): Option[seq[string]] =
  ## Get the command to execute for clipboard operations
  case tool
  of ctXclip:
    case operation
    of "read":
      return some(@["xclip", "-selection", "clipboard", "-o"])
    of "write":
      return some(@["xclip", "-selection", "clipboard", "-i"])
    else:
      return none(seq[string])
  of ctXsel:
    case operation
    of "read":
      return some(@["xsel", "--clipboard", "--output"])
    of "write":
      return some(@["xsel", "--clipboard", "--input"])
    else:
      return none(seq[string])
  of ctWlClipboard:
    case operation
    of "read":
      return some(@["wl-paste", "-n"])
    of "write":
      return some(@["wl-copy"])
    else:
      return none(seq[string])
  of ctWin32yank:
    case operation
    of "read":
      return some(@["win32yank.exe", "-o", "--lf"])
    of "write":
      return some(@["win32yank.exe", "-i", "--crlf"])
    else:
      return none(seq[string])
  of ctPbcopy:
    case operation
    of "read":
      return some(@["pbpaste"])
    of "write":
      return some(@["pbcopy"])
    else:
      return none(seq[string])

proc sendToClipboard(r: Registers, content: string): Result[(), string] =
  ## Send content to system clipboard if available
  if r.clipboardTool.isNone:
    return ok(())

  let cmdOpt = getClipboardCommand(r.clipboardTool.get, "write")
  if cmdOpt.isNone:
    return err("Clipboard tool not available")

  let cmd = cmdOpt.get()
  try:
    let process = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
    let inputStream = process.inputStream
    inputStream.write(content)
    inputStream.close()
    let exitCode = process.waitForExit()
    process.close()
    if exitCode == 0:
      return ok(())
    else:
      return err("Failed to write to clipboard")
  except OSError as e:
    return err("Clipboard error: " & e.msg)
  except IOError as e:
    return err("Clipboard I/O error: " & e.msg)

proc getFromClipboard(r: Registers): Result[string, string] =
  ## Get content from system clipboard if available
  if r.clipboardTool.isNone:
    return err("No clipboard tool configured")

  let cmdOpt = getClipboardCommand(r.clipboardTool.get, "read")
  if cmdOpt.isNone:
    return err("Clipboard tool not available")

  let cmd = cmdOpt.get()
  try:
    # Use startProcess instead of execCmdEx to avoid shell adding newline
    let p = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
    let output = p.outputStream.readAll()
    let exitCode = p.waitForExit()
    p.close()

    if exitCode == 0:
      return ok(output)
    else:
      return err("Failed to read from clipboard")
  except OSError as e:
    return err("Clipboard error: " & e.msg)
  except IOError as e:
    return err("Clipboard I/O error: " & e.msg)

# Public API for setting registers

proc setNoNamedRegister*(r: Registers, content: string, isLine: bool) =
  ## Set the unnamed register (") and sync to clipboard
  r.noNamed.setRegister(content, isLine)
  discard r.sendToClipboard(content)

proc setNoNamedRegister*(r: Registers, lines: seq[string], isLine: bool) =
  ## Set the unnamed register from lines
  r.noNamed.setRegister(lines, isLine)
  discard r.sendToClipboard(lines.join("\n"))

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

proc setClipboardRegister*(r: Registers, content: string, isLine: bool) =
  ## Set clipboard register and sync to system clipboard
  r.clipboard.setRegister(content, isLine)
  r.setNoNamedRegister(content, isLine)

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
    r.setClipboardRegister(content, isLine)
    ok(())
  else:
    err("Invalid register name: " & $name)

# Public API for getting registers

proc tryUpdateClipboardRegister(r: Registers) =
  ## Try to update clipboard register from system clipboard
  let clipResult = r.getFromClipboard()
  if clipResult.isOk:
    let content = clipResult.get
    if content.len > 0 and content != r.clipboard.getContent:
      let hasNewline = content.contains('\n')
      r.clipboard.setRegister(content, hasNewline)

proc getNoNamedRegister*(r: Registers): Register =
  ## Get the unnamed register, updating from clipboard if available
  r.tryUpdateClipboardRegister()
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

proc getClipboardRegister*(r: Registers): Register =
  ## Get clipboard register, updating from system clipboard first
  r.tryUpdateClipboardRegister()
  r.clipboard

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
    r.getClipboardRegister()
  else:
    Register(isLine: false, buffer: @[])

proc getRegisterContent*(r: Registers, name: char): string =
  ## Get register content as string
  r.getRegister(name).getContent()

proc isRegisterLinewise*(r: Registers, name: char): bool =
  ## Check if register content is linewise
  r.getRegister(name).isLine
