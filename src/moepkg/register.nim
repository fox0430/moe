import options
import unicodeext

type Register* = object
  buffer*: seq[seq[Rune]]
  isLine*: bool
  name*: string

type Registers* = object
  noNameRegister*: Register
  numberRegister*: array[10, Register]
  namedRegister*: seq[Register]

# Overwrite the no name register
proc addRegister*(registers: var Registers, buffer: seq[Rune]) =
  registers.noNameRegister = Register(buffer: @[buffer], isLine: false)

# Overwrite the no name register
proc addRegister*(registers: var Registers,
                  buffer: seq[Rune],
                  isLine: bool) =

  registers.noNameRegister = Register(buffer: @[buffer], isLine: isLine)

# Add/Overwrite the named register
proc addRegister*(registers: var Registers,
                  buffer: seq[Rune],
                  name: string) =

  let register = Register(buffer: @[buffer], isLine: false, name: name)

  if name.len > 0:
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

  let register = Register(buffer: @[buffer], isLine: isLine, name: name)

  if name.len > 0:
    var isOverwrite = false
    # Overwrite the register if exist the same name.
    for i, r in registers.namedRegister:
      if r.name == name:
        registers.namedRegister[i] = register
        isOverwrite = true

    if not isOverwrite:
      registers.namedRegister.add register

  registers.noNameRegister = register

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

# Overwrite the no name register
proc addRegister*(registers: var Registers, buffer: seq[seq[Rune]]) =
  registers.noNameRegister = Register(buffer: buffer, isLine: true)

# Overwrite the no name register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  isLine: bool) =

  registers.noNameRegister = Register(buffer: buffer, isLine: isLine)

# Add/Overwrite the named register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  name: string) =

  let register = Register(buffer: buffer, isLine: true, name: name)

  if name.len > 0:
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

  let register = Register(buffer: buffer, isLine: isLine, name: name)

  if name.len > 0:
    var isOverwrite = false

    # Overwrite the register if exist the same name.
    for i, r in registers.namedRegister:
      if r.name == name:
        registers.namedRegister[i] = register
        isOverwrite = true

    if not isOverwrite:
      registers.namedRegister.add register

  registers.noNameRegister = register

# Add/Overwrite the number register
proc addRegister*(registers: var Registers,
                  buffer: seq[seq[Rune]],
                  number: int) =

  # the number should 0 ~ 9
  if number > -1 or number < 10:
    let register = Register( buffer: buffer, isLine: true)

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

proc searchByName*(registers: Registers, name: string): Option[Register] =
  for r in registers.namedRegister:
    if r.name == name:
      return some(r)
