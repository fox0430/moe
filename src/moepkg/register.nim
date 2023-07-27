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

import std/[options, strutils]
import independentutils, clipboard, settings, unicodeext

type Register* = object
  buffer*: seq[Runes]
  isLine*: bool
  name*: string

type Registers* = object
  noNameRegister*: Register
  smallDeleteRegister*: Register
  numberRegister*: array[10, Register]
  namedRegister*: seq[Register]

# Add/Overwrite the number register
proc addRegister(
  registers: var Registers,
  r: Register,
  isDelete: bool,
  settings: EditorSettings) =

    if isDelete:
      # If the buffer is deleted line, write to the register 1.
      # Previous registers are stored 2 ~ 9.
      if r.isLine:
        for i in countdown(8, 1):
          registers.numberRegister[i + 1] = registers.numberRegister[i]
        registers.numberRegister[1] = r
      else:
        registers.smallDeleteRegister = r
    else:
      # If the buffer is yanked line, overwrite the register 0.
      registers.numberRegister[0] = r

    registers.noNameRegister = r

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
      for i, r in registers.namedRegister:
        if r.name == name:
          registers.namedRegister[i] = register
        isOverwrite = true

      if not isOverwrite:
        registers.namedRegister.add register

      registers.noNameRegister = register

      if settings.clipboard.enable:
        register.buffer.sendToClipboard(settings.clipboard.toolOnLinux)

proc addRegister*(
  registers: var Registers,
  buffer: Runes,
  name: string,
  settings: EditorSettings) =
    ## Add/Overwrite the named register

    if name.len > 0:
      let register = Register(buffer: @[buffer], isLine: false, name: name)
      registers.addRegister(register, settings)

proc addRegister*(
  registers: var Registers,
  buffer: Runes,
  isLine: bool,
  name: string,
  settings: EditorSettings) =

    if name.len > 0:
      let register = Register(buffer: @[buffer], isLine: isLine, name: name)
      registers.addRegister(register, settings)

proc addRegister*(
  registers: var Registers,
  buffer: seq[Runes],
  name: string,
  settings: EditorSettings) =

    if name.len > 0:
      let register = Register(buffer: buffer, isLine: true, name: name)
      registers.addRegister(register, settings)

proc addRegister*(
  registers: var Registers,
  buffer: seq[Runes],
  isLine: bool,
  name: string,
  settings: EditorSettings) =

    if name.len > 0:
      let register = Register(buffer: buffer, isLine: isLine, name: name)
      registers.addRegister(register, settings)

proc searchByName*(registers: Registers, name: string): Option[Register] =
  ## Search a register by the string

  if name == "-":
    let r = registers.smallDeleteRegister
    if r.buffer.len > 0:
      return some(r)
  elif isInt(name):
    # Search a register in the number register
    let
      number = name.parseInt
      r = registers.numberRegister[number]
    if r.buffer.len > 0:
      return some(r)
  else:
    # Search a register in the named register
    for r in registers.namedRegister:
      if r.name == name:
        return some(r)
