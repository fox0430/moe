import options, strutils
import unicodeext, independentutils, ui

type Register* = object
  buffer*: seq[seq[Rune]]
  isLine*: bool
  name*: string

type Registers* = object
  noNameRegister*: Register
  numberRegister*: array[10, Register]
  namedRegister*: seq[Register]

# Add/Overwrite the number register
proc addRegister*(registers: var Registers, buffer: seq[Rune], number: int) =
  # the number should 0 ~ 9
  if number > -1 or number < 10:
    let register = Register(buffer: @[buffer], isLine: false)

    registers.numberRegister[number] = register
    registers.noNameRegister = register

# Add/Overwrite the number register
proc addRegister*(registers: var Registers,
                  buffer: seq[Rune],
                  isLine: bool,
                  number: int) =

  # the number should 0 ~ 9
  if number > -1 or number < 10:
    let register = Register(buffer: @[buffer], isLine: isLine)

    registers.numberRegister[number] = register
    registers.noNameRegister = register

# Add/Overwrite the number register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  number: int) =

  # the number should 0 ~ 9
  if number > -1 or number < 10:
    let register = Register(buffer: buffer, isLine: true)

    registers.numberRegister[number] = register
    registers.noNameRegister = register

# Add/Overwrite the number register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  isLine: bool,
                  number: int) =

  # the number should 0 ~ 9
  if number > -1 or number < 10:
    let register = Register(buffer: buffer, isLine: isLine)

    registers.numberRegister[number] = register
    registers.noNameRegister = register

proc addRegister(registers: var Registers, r: Register, number: int) =
  # the number should 0 ~ 9
  if number > -1 or number < 10:
    registers.numberRegister[number] = r
    registers.noNameRegister = r

# Overwrite the no name register
proc addRegister*(registers: var Registers, buffer: seq[Rune]) =
  registers.noNameRegister = Register(buffer: @[buffer], isLine: false)

# Overwrite the no name register
proc addRegister*(registers: var Registers,
                  buffer: seq[Rune],
                  isLine: bool) =

  registers.noNameRegister = Register(buffer: @[buffer], isLine: isLine)

# Overwrite the no name register
proc addRegister*(registers: var Registers, buffer: seq[seq[Rune]]) =
  registers.noNameRegister = Register(buffer: buffer, isLine: true)

# Overwrite the no name register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  isLine: bool) =

  registers.noNameRegister = Register(buffer: buffer, isLine: isLine)

# Add/Overwrite the named register or the number register
proc addRegister*(registers: var Registers,
                  buffer: seq[Rune],
                  name: string) =

  if name.len > 0:
    const isLine = false
    let register = Register(buffer: @[buffer], isLine: isLine, name: name)

    if isInt(name):
      # Overwrite the number register
      let index = name.parseInt
      registers.addRegister(register, index)
    else:
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

# Add/Overwrite the named register
proc addRegister*(registers: var Registers,
                  buffer: seq[Rune],
                  isLine: bool,
                  name: string) =

  if name.len > 0:
    let register = Register(buffer: @[buffer], isLine: isLine, name: name)

    if isInt(name):
      # Overwrite the number register
      let index = name.parseInt
      registers.addRegister(register, index)
    else:
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

# Add/Overwrite the named register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  name: string) =

  if name.len > 0:
    let register = Register(buffer: buffer, isLine: true, name: name)

    if isInt(name):
      # Overwrite the number register
      let index = name.parseInt
      registers.addRegister(register, index)
    else:
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

# Add/Overwrite the named register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  isLine: bool,
                  name: string) =

  if name.len > 0:
    let register = Register(buffer: buffer, isLine: isLine, name: name)

    if isInt(name):
      # Overwrite the number register
      let index = name.parseInt
      registers.addRegister(register, index)
    else:
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

# Search a register by the string
proc searchByName*(registers: Registers, name: string): Option[Register] =
  if isInt(name):
    # Search a register in the number register
    let number = name.parseInt
    return some(registers.numberRegister[number])
  else:
    # Search a register in the named register
    for r in registers.namedRegister:
      if r.name == name:
        return some(r)
