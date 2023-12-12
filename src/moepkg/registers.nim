#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[options, strutils, sequtils, tables, strformat, times]
import pkg/results
import clipboard, settings, unicodeext

type
  Register* = object
    isLine*: bool
    buffer*: seq[Runes]
    timestamp: DateTime

  NoNamedRegister* = Register

  SmallDeleteRegister* = Register

  ClipBoardRegister* = Register

  NumberRegisters* = array[10, Register]

  NamedRegisters* = OrderedTable[char, Register]

  OperationRegister* = object
    commands*: seq[Runes]

  NormalModeOperationsRegister* = OperationRegister

  OperationRegisters* = OrderedTable[char, OperationRegister]

  Registers* = ref object
    clipboardTool: Option[ClipboardTool]

    noNamed: NoNamedRegister
      ## The latest updating register buffer.

    smallDelete: SmallDeleteRegister
      ## Register name: '-'.
      ## Small delete (Deleted in the line).

    number: array[10, Register]
      ## Register names: '0'~ '9'.
      ## '0': Yanked lines.
      ## '1' ~ '9': Deleted lines.

    named: OrderedTable[char, Register]
      ## Register names: 'A' ~ 'Z', 'a' ~ 'z'.
      ## You can use these registers.

    clipboard: ClipBoardRegister
      ## Register names: '*', '+' and '~'. These registers are same currnetly.
      ## Read only from editor users.
      ## Store the buffer from OS clipboard.

    normalModeOperations: NormalModeOperationsRegister
      ## A retister for normal mode operations (commands).
      ## Records all normal mode operations.

    operations: OperationRegisters
      ## Register names: '0' ~ '9', 'A' ~ 'Z' 'a' ~ 'z'.
      ## Registers for the editor operations.
      ##
      ## key: Rgister name
      ## value: Operations (editor commands)

proc initOperationRegisters(): OperationRegisters =
  concat(toSeq('0'..'9'), toSeq('A'..'Z'), toSeq('a'..'z'))
    .mapIt((it, OperationRegister()))
    .toOrderedTable

proc initNoNamedRegister(t: DateTime): NoNamedRegister =
  NoNamedRegister(timestamp: t)

proc initNumberRegisters(t: DateTime): NumberRegisters =
  for i in 0 .. 9: result[i].timestamp = t

proc initSmallDeleteRegister(t: DateTime): SmallDeleteRegister =
  SmallDeleteRegister(timestamp: t)

proc initNamedRegisters(t: DateTime): NamedRegisters =
  concat(toSeq('A'..'Z'), toSeq('a'..'z'))
    .mapIt((it, Register(timestamp: t)))
    .toOrderedTable

proc initClipBoardRegister(t: DateTime): ClipBoardRegister =
  ClipBoardRegister(timestamp: t)

proc initRegisters*(): Registers =
  result = Registers()

  let n = now()
  result.noNamed = initNoNamedRegister(n)
  result.number = initNumberRegisters(n)
  result.smallDelete = initSmallDeleteRegister(n)
  result.named = initNamedRegisters(n)
  result.operations = initOperationRegisters()

proc setClipboardTool*(r: var Registers, tool: ClipboardTool) {.inline.} =
  ## Set the clipboard tool for Linux and init the clipboard register.

  if tool != none:
    r.clipboardTool = some(tool)
    r.clipboard = initClipBoardRegister(now())

proc isNamedRegisterName*(c: char): bool {.inline.} =
  c in Letters

proc isNamedRegisterName*(s: string): bool {.inline.} =
  s.len == 1 and s[0].isNamedRegisterName

proc isNumberRegisterName*(n: int): bool {.inline.} =
  n >= 0 and n <= 9

proc isNumberRegisterName*(c: char): bool {.inline.} =
  c.int >= '0'.int and c.int <= '9'.int

proc isNumberRegisterName*(s: string): bool {.inline.} =
  s.len == 1 and s[0].isNumberRegisterName

proc isSmallDeleteRegisterName*(c: char): bool {.inline.} =
  c == '-'

proc isSmallDeleteRegisterName*(s: string): bool {.inline.} =
  s.len == 1 and s[0].isSmallDeleteRegisterName

proc isClipBoardRegisterName*(c: char): bool {.inline.} =
  c in ['*', '+', '~']

proc isClipBoardRegisterName*(s: string): bool {.inline.} =
  s.len == 1 and s[0].isClipBoardRegisterName

proc set(r: var Register, buffer: Runes) {.inline.} =
  ## Set runes to the register.

  r.isLine = false
  r.buffer = @[buffer]
  r.timestamp = now()

proc set(r: var Register, buffer: seq[Runes]) {.inline.} =
  ## Set lines to the register.

  r.isLine = true
  r.buffer = buffer
  r.timestamp = now()

proc setNoNamedRegister*(
  r: var Registers,
  buffer: Runes | seq[Runes]) {.inline.} =
    ## set the no named register and OS clipboard.

    r.noNamed.set(buffer)

    if r.clipboardTool.isSome:
      buffer.sendToClipboard(r.clipboardTool.get)

proc set(
  r: var NumberRegisters,
  buffer: Runes | seq[Runes],
  registerNumber: int,
  isShift: bool) =
    ## set the number register.
    ## If `isShift` is true, moving previous registers to next numbers.
    ##
    ## '0': Yanked lines.
    ## '1' ~ '9': Deleted lines.

    doAssert(
      registerNumber >= 0 and registerNumber <= 9,
      fmt"Number register: Invalid number: {registerNumber}")

    if isShift and registerNumber > 0 and registerNumber < 9:
      # Latest deleted register.
      for i in countdown(8, registerNumber):
        # Shift previous registers.
        r[i + 1] = r[i]

    r[registerNumber].set(buffer)

proc set(
  r: var NamedRegisters,
  buffer: Runes | seq[Runes],
  registerName: char) =
    ## set the named register.
    ## Register names: 'A' ~ 'Z', 'a' ~ 'z'.

    doAssert(
      registerName in Letters,
      fmt"Named register: Invalid name: {registerName}")

    r[registerName].set(buffer)

proc setSmallDeleteRegister*(
  r: var Registers,
  buffer: Runes) {.inline.} =
    ## set the small delete register, no named register and OS clipboard.

    r.smallDelete.set(buffer)
    r.setNoNamedRegister(buffer)

proc setNumberRegister(
  r: var Registers,
  buffer: Runes | seq[Runes],
  registerNumber: int,
  isShift: bool = false) {.inline.} =
    ## set the number register, no named register and OS clipboard.
    ## If `isShift` is true, moving previous registers to next numbers.
    ##
    ## '0': Yanked lines.
    ## '1' ~ '9': Delete lines.

    r.number.set(buffer, registerNumber, isShift)
    r.setNoNamedRegister(buffer)

proc setYankedRegister*(
  r: var Registers,
  buffer: Runes | seq[Runes]) =
    ## set the number register for yank ('0'), no named register and OS
    ## clipboard.

    const RegisterNumber = 0
    r.setNumberRegister(buffer,  RegisterNumber)
    r.setNoNamedRegister(buffer)

proc setDeletedRegister*(
  r: var Registers,
  buffer: Runes) {.inline.} =
    ## set the small delete register, no named register and OS clipboard.

    r.setSmallDeleteRegister(buffer)
    r.setNoNamedRegister(buffer)

proc setDeletedRegister*(
  r: var Registers,
  buffer: seq[Runes]) =
    ## set the number register for deleted lines (Register '1'), no named
    ## register and OS clipboard.
    ## And move previous registers to next numbers.

    const
      IsShift = true
      RegisterNumber = 1
    r.setNumberRegister(buffer, RegisterNumber, IsShift)
    r.setNoNamedRegister(buffer)

proc setDeletedRegister*(
  r: var Registers,
  buffer: seq[Runes],
  registerNumber: int) =
    ## set the number register for deleted lines (Register '1'), no named
    ## register and OS clipboard.

    r.setNumberRegister(buffer, registerNumber)
    r.setNoNamedRegister(buffer)

proc setNamedRegister*(
  r: var Registers,
  buffer: Runes | seq[Runes],
  registerName: char) {.inline.} =
    ## set the named register, no named register and OS clipboard.
    ## Register numbers: 'A' ~ 'Z', 'a' ~ 'z'.

    r.named.set(buffer, registerName)
    r.setNoNamedRegister(buffer)

proc setNamedRegister*(
  r: var Registers,
  buffer: Runes | seq[Runes],
  registerName: Rune) =
    ## set the named register, no named register and OS clipboard.
    ## Register numbers: 'A' ~ 'Z', 'a' ~ 'z'.

    doAssert(
      r.canConvertToChar,
      fmt"Named register: Invalid register name: {registerName}")

    r.named.set(buffer, registerName.toChar)
    r.setNoNamedRegister(buffer)

proc setClipBoardRegister(r: var Registers, buffer: Runes | seq[Runes]) =
  ## Set the buffer to clipboard and no named registers.

  r.clipboard.set(buffer)
  r.noNamed.set(buffer)

proc isUpdateClipBoardRegister(
  r: Registers,
  clipboardBuffer: seq[Runes]): bool {.inline.} =

    clipboardBuffer.len > 0 and r.clipboard.buffer != clipboardBuffer

proc trySetClipBoardRegister(r: var Registers): bool =
  if r.clipboardTool.isSome:
    # Check the OS clipboard and update clipboard and no named registers.

    let buf = getBufferFromClipboard(r.clipboardTool.get)
    if buf.isOk and buf.get.len > 0:
      let lines = buf.get.splitLines
      if r.isUpdateClipBoardRegister(lines):
        if buf.get.find(ru'\n') > 0:
          r.setClipBoardRegister(lines)
        else:
          r.setClipBoardRegister(buf.get)

        return true

proc getNoNamedRegister*(r: var Registers): Register =
  ## Return the no named register.
  ## If r.clipboard is Some, check and update clipboard and no named registers.

  discard r.trySetClipBoardRegister

  return r.noNamed

proc getNamedRegister*(r: Registers, registerName: char): Register =
  doAssert(
    registerName.isNamedRegisterName,
    fmt"Named register: Invalid register name: {registerName}")

  return r.named[registerName]

proc getNamedRegister*(r: Registers, registerName: string): Register =
  doAssert(
    registerName.isNamedRegisterName,
    fmt"Named register: Invalid register name: {registerName}")

  return r.named[registerName[0]]

proc getSmallDeleteRegister*(r: Registers): Register {.inline.} = r.smallDelete

proc getNumberRegister*(r: Registers, num: int): Register {.inline.} =
  r.number[num]

proc getNumberRegister*(r: Registers, registerNumChar: char): Register =
  doAssert(
    registerNumChar.isNumberRegisterName,
    fmt"Number register: Invalid register name: {registerNumChar}")

  const AsciiZero = 48
  return r.number[registerNumChar.int - AsciiZero]

proc getNumberRegister*(r: Registers, registerNumStr: string): Register =
  doAssert(
    registerNumStr.isNumberRegisterName,
    fmt"Number register: Invalid register name: {registerNumStr}")

  return r.getNumberRegister(registerNumStr[0])

proc getClipBoardRegister*(r: var Registers): Register =
  discard r.trySetClipBoardRegister
  return r.clipboard

proc addNormalModeOperation*(
  r: var Registers,
  command: Runes) {.inline.} =
    ## Add an operation to normalModeOperationsRegister.

    r.normalModeOperations.commands.add command

proc getNormalModeOperations*(
  r: Registers): NormalModeOperationsRegister {.inline.} =
    ## Return all operations from normalModeOperationsRegister.

    r.normalModeOperations

proc getLatestNormalModeOperation*(r: Registers): Option[Runes] =
  if r.normalModeOperations.commands.len > 0:
    return some(r.normalModeOperations.commands[^1])

proc isOperationRegisterName*(name: Rune): bool {.inline.} =
  ## Return true if valid operation register name.

  char(name) >= '0' and char(name) <= '9' or
  char(name) >= 'A' and char(name) <= 'Z' or
  char(name) >= 'a' and char(name) <= 'z'

proc clearOperations*(
  r: var Registers,
  name: Rune): Result[(), string] =
    ## Clear the operationRegister.

    if isOperationRegisterName(name):
      r.operations[char(name)] = OperationRegister()
      return Result[(), string].ok ()
    else:
      return Result[(), string].err "Invalid register name"

proc addOperation*(
  r: var Registers,
  name: Rune,
  operation: Runes): Result[(), string] =
    ## Add an editor operation to the operationRegister.

    if not isOperationRegisterName(name):
      return Result[(), string].err "Invalid register name"
    elif operation.len == 0:
      return Result[(), string].err "Invalid operation"
    else:
      r.operations[char(name)].commands.add operation
      return Result[(), string].ok ()

proc getOperations*(
  r: Registers,
  name: Rune): Result[OperationRegister, string] =
    ## Return editor operations from the operationRegister.

    if isOperationRegisterName(name):
      return Result[OperationRegister, string].ok r.operations[char(name)]
    else:
      return Result[OperationRegister, string].err "Invalid register name"
