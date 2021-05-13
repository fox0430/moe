import unicodeext, ui

type Register* = object
  buffer*: seq[seq[Rune]]
  isLine*: bool

proc addRegister*(registers: var seq[Register],buffer: seq[Rune]) =
  if registers.len == 0 or registers[^1].buffer != @[buffer]:
    registers.add Register(buffer: @[buffer], isLine: false)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[Rune],
                  isLine: bool) =

  if registers.len == 0 or registers[^1].buffer != @[buffer]:
    registers.add Register(buffer: @[buffer], isLine: isLine)

proc addRegister*(registers: var seq[Register], buffer: seq[seq[Rune]]) =
  if registers.len == 0 or registers[^1].buffer != buffer:
    registers.add Register(buffer: buffer, isLine: true)

proc addRegister*(registers: var seq[Register],
                  buffer: seq[seq[Rune]],
                  isLine: bool) =

  if registers.len == 0 or registers[^1].buffer != buffer:
    registers.add Register(buffer: buffer, isLine: isLine)
