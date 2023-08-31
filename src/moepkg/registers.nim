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

import std/[options, strutils, sequtils, tables]
import pkg/results
import independentutils, clipboard, settings, unicodeext

type
  Register* = object
    ## A register for buffers.
    name*: string
    buffer*: seq[Runes]
    isLine*: bool

  Registers* = object
    noNameRegisters*: Register
    smallDeleteRegisters*: Register
    numberRegisters*: array[10, Register]
    namedRegisters*: seq[Register]

var
  ## A retister for normal mode operations (commands).
  ## Records all normal mode operations.
  normalModeOperationsRegister: seq[Runes]

  ## Registers named '0' ~ '9', 'A' ~ 'Z' 'a' ~ 'z' for recoding
  ## the editor operations.
  ##
  ## key: Rgister name
  ## value: Operations (editor commands)
  operationRegisters: OrderedTable[char, seq[Runes]]

proc initOperationRegisters*() =
  operationRegisters = concat(
    toSeq('0'..'9'),
    toSeq('A'..'Z'),
    toSeq('a'..'z'),
  )
  .mapIt((it, newSeq[Runes]()))
  .toOrderedTable

proc addRegister(
  registers: var Registers,
  r: Register,
  isDelete: bool,
  settings: EditorSettings) =
    ## Add/Overwrite the number register

    if isDelete:
      # If the buffer is deleted line, write to the register 1.
      # Previous registers are stored 2 ~ 9.
      if r.isLine:
        for i in countdown(8, 1):
          registers.numberRegisters[i + 1] = registers.numberRegisters[i]
        registers.numberRegisters[1] = r
      else:
        registers.smallDeleteRegisters = r
    else:
      # If the buffer is yanked line, overwrite the register 0.
      registers.numberRegisters[0] = r

    registers.noNameRegisters = r

    if settings.clipboard.enable:
      r.buffer.sendToClipboard(settings.clipboard.toolOnLinux)

proc addRegister*(
  registers: var Registers,
  buffer: Runes,
  settings: EditorSettings) =

    let r = Register(buffer: @[buffer], isLine: false)
    const IsDelete = false
    registers.addRegister(r, IsDelete, settings)

proc addRegister*(
  registers: var Registers,
  buffer: Runes,
  isLine: bool,
  settings: EditorSettings) =

    let r = Register(buffer: @[buffer], isLine: isLine)
    const IsDelete = false
    registers.addRegister(r, IsDelete, settings)

proc addRegister*(
  registers: var Registers,
  buffer: seq[Runes],
  settings: EditorSettings) =

    let r = Register(buffer: buffer, isLine: true)
    const IsDelete = false
    registers.addRegister(r, IsDelete, settings)

proc addRegister*(
  registers: var Registers,
  buffer: seq[Runes],
  isLine: bool,
  settings: EditorSettings) =

    let r = Register(buffer: buffer, isLine: isLine)
    const IsDelete = false
    registers.addRegister(r, IsDelete, settings)

proc addRegister*(
  registers: var Registers,
  buffer: Runes,
  isLine, isDelete: bool,
  settings: EditorSettings) =

    let r = Register(buffer: @[buffer], isLine: isLine)
    registers.addRegister(r, isDelete, settings)

proc addRegister*(
  registers: var Registers,
  buffer: seq[Runes],
  isLine, isDelete: bool,
  settings: EditorSettings) =

    let r = Register(buffer: buffer, isLine: isLine)
    registers.addRegister(r, isDelete, settings)

proc addRegister(
  registers: var Registers,
  register: Register,
  settings: EditorSettings) =

    let name = register.name

    if name != "_":
      # Add/Overwrite the named register
      var isOverwrite = false

      # Overwrite the register if exist the same name.
      for i, r in registers.namedRegisters:
        if r.name == name:
          registers.namedRegisters[i] = register
        isOverwrite = true

      if not isOverwrite:
        registers.namedRegisters.add register

      registers.noNameRegisters = register

      if settings.clipboard.enable:
        register.buffer.sendToClipboard(settings.clipboard.toolOnLinux)

proc addRegister*(
  registers: var Registers,
  buffer: Runes,
  name: string,
  settings: EditorSettings) =
    ## Add/Overwrite the named register

    if name.len > 0:
      let register = Register(
        buffer: @[buffer],
        isLine: false,
        name: name)
      registers.addRegister(register, settings)

proc addRegister*(
  registers: var Registers,
  buffer: Runes,
  isLine: bool,
  name: string,
  settings: EditorSettings) =

    if name.len > 0:
      let register = Register(
        buffer: @[buffer],
        isLine: isLine,
        name: name)
      registers.addRegister(register, settings)

proc addRegister*(
  registers: var Registers,
  buffer: seq[Runes],
  name: string,
  settings: EditorSettings) =

    if name.len > 0:
      let register = Register(
        buffer: buffer,
        isLine: true,
        name: name)
      registers.addRegister(register, settings)

proc addRegister*(
  registers: var Registers,
  buffer: seq[Runes],
  isLine: bool,
  name: string,
  settings: EditorSettings) =

    if name.len > 0:
      let register = Register(
        buffer: buffer,
        isLine: isLine,
        name: name)
      registers.addRegister(register, settings)

proc searchByName*(registers: Registers, name: string): Option[Register] =
  ## Search a register by the string

  if name == "-":
    let r = registers.smallDeleteRegisters
    if r.buffer.len > 0:
      return some(r)
  elif isInt(name):
    # Search a register in the number register
    let
      number = name.parseInt
      r = registers.numberRegisters[number]
    if r.buffer.len > 0:
      return some(r)
  else:
    # Search a register in the named register
    for r in registers.namedRegisters:
      if r.name == name:
        return some(r)

proc addOperationToNormalModeOperationsRegister*(command: Runes) {.inline.} =
  ## Add an operation to normalModeOperationsRegister.

  normalModeOperationsRegister.add command

proc getOperationsFromNormalModeOperationsRegister*(): seq[Runes] {.inline.} =
  ## Return all operations from normalModeOperationsRegister.

  normalModeOperationsRegister

proc getLatestNormalModeOperation*(): Option[Runes] =
  if normalModeOperationsRegister.len > 0:
    return some(normalModeOperationsRegister[^1])

proc isOperationRegisterName*(name: Rune): bool {.inline.} =
  ## Return true if valid operation register name.

  char(name) >= '0' and char(name) <= '9' or
  char(name) >= 'A' and char(name) <= 'Z' or
  char(name) >= 'a' and char(name) <= 'z' or
  char(name) == '^'

proc clearOperationToRegister*(name: Rune): Result[(), string] =
  ## Clear the operationRegister.

  if isOperationRegisterName(name):
    operationRegisters[char(name)] = @[]
    return Result[(), string].ok ()
  else:
    return Result[(), string].err "Invalid register name"

proc addOperationToRegister*(
  name: Rune,
  operation: Runes): Result[(), string] =
    ## Add an editor operation to the operationRegister.

    if not isOperationRegisterName(name):
      return Result[(), string].err "Invalid register name"
    elif operation.len == 0:
      return Result[(), string].err "Invalid operation"
    else:
      operationRegisters[char(name)].add operation
      return Result[(), string].ok ()

proc getOperationsFromRegister*(name: Rune): Result[seq[Runes], string] =
    ## Return editor operations from the operationRegister.

    if isOperationRegisterName(name):
      return Result[seq[Runes], string].ok operationRegisters[char(name)]
    else:
      return Result[seq[Runes], string].err "Invalid register name"
