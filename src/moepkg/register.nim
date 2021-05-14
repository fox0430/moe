import options
import unicodeext

type Register* = object
  buffer*: seq[seq[Rune]]
  isLine*: bool
  name: string

proc addRegister*(registers: var seq[Register], buffer: seq[Rune]) =
  if registers.len == 0 or registers[^1].buffer != @[buffer]:
    registers.add Register(buffer: @[buffer], isLine: false)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[Rune],
                  isLine: bool) =

  if registers.len == 0 or registers[^1].buffer != @[buffer]:
    registers.add Register(buffer: @[buffer], isLine: isLine)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[Rune],
                  name: string) =

  if registers.len == 0 or registers[^1].buffer != @[buffer]:
    # Overwrite the register if exist the same name.
    for i, r in registers:
      if r.name == name:
        registers[i] = Register(buffer: @[buffer], isLine: false, name: name)
        return

    registers.add Register(buffer: @[buffer], isLine: false, name: name)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[Rune],
                  isLine: bool,
                  name: string) =

  if registers.len == 0 or registers[^1].buffer != @[buffer]:
    # Overwrite the register if exist the same name.
    for i, r in registers:
      if r.name == name:
        registers[i] = Register(buffer: @[buffer], isLine: isLine, name: name)
        return

    registers.add Register(buffer: @[buffer], isLine: isLine, name: name)

proc addRegister*(registers: var seq[Register], buffer: seq[seq[Rune]]) =
  if registers.len == 0 or registers[^1].buffer != buffer:
    registers.add Register(buffer: buffer, isLine: true)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[seq[Rune]],
                  isLine: bool) =

  if registers.len == 0 or registers[^1].buffer != buffer:
    registers.add Register(buffer: buffer, isLine: isLine)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[seq[Rune]],
                  name: string) =

  if registers.len == 0 or registers[^1].buffer != buffer:
    # Overwrite the register if exist the same name.
    for i, r in registers:
      if r.name == name:
        registers[i] = Register(buffer: buffer, isLine: true, name: name)
        return

    registers.add Register(buffer: buffer, isLine: true, name: name)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[seq[Rune]],
                  isLine: bool,
                  name: string) =

  if registers.len == 0 or registers[^1].buffer != buffer:
    # Overwrite the register if exist the same name.
    for i, r in registers:
      if r.name == name:
        registers[i] = Register(buffer: buffer, isLine: isLine, name: name)
        return

    registers.add Register(buffer: buffer, isLine: isLine, name: name)

proc searchByName*(registers: seq[Register], name: string): Option[Register] =
  for r in registers:
    if r.name == name:
      return some(r)
