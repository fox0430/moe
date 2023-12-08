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

import std/[options, strutils, sequtils, tables, strformat]
import pkg/results
import clipboard, settings, unicodeext

type
  Register* = object
    isLine*: bool
    buffer*: seq[Runes]

  NoNamedRegister* = Register

  SmallDeleteRegister* = Register

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

    normalModeOperations: NormalModeOperationsRegister
      ## A retister for normal mode operations (commands).
      ## Records all normal mode operations.

    operations: OperationRegisters
      ## Register names: '0' ~ '9', 'A' ~ 'Z' 'a' ~ 'z'.
      ## Registers for the editor operations.
      ##
      ## key: Rgister name
      ## value: Operations (editor commands)

proc initOperationRegisters*(): OperationRegisters =
  concat(toSeq('0'..'9'), toSeq('A'..'Z'), toSeq('a'..'z'))
    .mapIt((it, OperationRegister()))
    .toOrderedTable

proc initNamedRegisters*(): NamedRegisters =
  concat(toSeq('A'..'Z'), toSeq('a'..'z'))
    .mapIt((it, Register()))
    .toOrderedTable

proc initRegisters*(): Registers =
  result = Registers()

  result.named = initNamedRegisters()
  result.operations = initOperationRegisters()

proc setClipboardTool*(r: var Registers, tool: ClipboardTool) {.inline.} =
  ## Set the clipboard tool for Linux.

  r.clipboardTool = some(tool)

proc isNamedRegisterName*(s: string): bool {.inline.} =
  s.len == 1 and s[0] in Letters

proc isNamedRegisterName*(c: char): bool {.inline.} =
  c in Letters

proc getNoNamedRegister*(r: Registers): Register {.inline.} = r.noNamed

proc getNamedRegister*(r: Registers, registerName: char): Register =
  doAssert(
    registerName.isNamedRegisterName,
    fmt"Named register: Invalid register name: {registerName}")

  return r.named[registerName]

proc getSmallDeleteRegister*(r: Registers): Register {.inline.} = r.smallDelete

proc getNumberRegister*(r: Registers, num: int): Register {.inline.} =
  r.number[num]

proc update(r: var Register, buffer: Runes) {.inline.} =
  ## Set runes to the register.

  r.isLine = false
  r.buffer = @[buffer]

proc update(r: var Register, buffer: seq[Runes]) {.inline.} =
  ## Set lines to the register.

  r.isLine = true
  r.buffer = buffer

proc updateNoNamedRegister*(
  r: var Registers,
  buffer: Runes | seq[Runes]) {.inline.} =
    ## Update the no named register and OS clipboard.

    r.noNamed.update(buffer)

    if r.clipboardTool.isSome:
      buffer.sendToClipboard(r.clipboardTool.get)

proc update(
  r: var NumberRegisters,
  isShift: bool,
  registerNumber: int,
  buffer: Runes | seq[Runes]) =
    ## Update the number register.
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

    r[registerNumber].update(buffer)

proc update(
  r: var NamedRegisters,
  registerName: char,
  buffer: Runes | seq[Runes]) =
    ## Update the named register.
    ## Register names: 'A' ~ 'Z', 'a' ~ 'z'.

    doAssert(
      registerName in Letters,
      fmt"Named register: Invalid name: {registerName}")

    r[registerName].update(buffer)

proc updateSmallDeleteRegister*(
  r: var Registers,
  buffer: Runes) {.inline.} =
    ## Update the small delete register, no named register and OS clipboard.

    r.smallDelete.update(buffer)
    r.updateNoNamedRegister(buffer)

proc updateNumberRegister(
  r: var Registers,
  isShift: bool,
  registerNumber: int,
  buffer: Runes | seq[Runes]) {.inline.} =
    ## Update the number register, no named register and OS clipboard.
    ## If `isShift` is true, moving previous registers to next numbers.
    ##
    ## '0': Yanked lines.
    ## '1' ~ '9': Delete lines.

    r.number.update(isShift, registerNumber, buffer)
    r.updateNoNamedRegister(buffer)

proc updateYankedRegister*(
  r: var Registers,
  buffer: Runes | seq[Runes]) =
    ## Update the number register for yank ('0'), no named register and OS
    ## clipboard.

    const
      isShift = false
      RegisterNumber = 0
    r.updateNumberRegister(isShift, RegisterNumber, buffer)
    r.updateNoNamedRegister(buffer)

proc updateLatestDeletedRegister*(
  r: var Registers,
  buffer: Runes) {.inline.} =
    ## Update the small delete register, no named register and OS clipboard.

    r.updateSmallDeleteRegister(buffer)
    r.updateNoNamedRegister(buffer)

proc updateLatestDeletedRegister*(
  r: var Registers,
  buffer: seq[Runes]) =
    ## Update the number register for deleted lines (Register '1'), no named
    ## register and OS clipboard.
    ## And move previous registers to next numbers.

    const
      isShift = true
      RegisterNumber = 1
    r.updateNumberRegister(isShift, RegisterNumber, buffer)
    r.updateNoNamedRegister(buffer)

proc updateNamedRegister*(
  r: var Registers,
  registerName: char,
  buffer: Runes | seq[Runes]) {.inline.} =
    ## Update the named register, no named register and OS clipboard.
    ## Register numbers: 'A' ~ 'Z', 'a' ~ 'z'.

    r.named.update(registerName, buffer)
    r.updateNoNamedRegister(buffer)

proc updateNamedRegister*(
  r: var Registers,
  registerName: Rune,
  buffer: Runes | seq[Runes]) =
    ## Update the named register, no named register and OS clipboard.
    ## Register numbers: 'A' ~ 'Z', 'a' ~ 'z'.

    doAssert(
      r.canConvertToChar,
      fmt"Named register: Invalid register name: {registerName}")

    r.named.update(registerName.toChar, buffer)
    r.updateNoNamedRegister(buffer)

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
