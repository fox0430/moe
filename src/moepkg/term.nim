import std/strutils

type
  # TODO: Move
  # Hex color code
  ColorCode* = array[6, char]

  # TODO: Move
  ColorPair* = tuple[fg, bg: ColorCode]

# TODO: Move
proc initColorCode*(str: string): ColorCode =
  assert(str.len == 6)

  var code: ColorCode
  for i, c in str:
    code[i] = c

  return code

# TODO: Move
proc initColorPair*(fgColorStr, bgColorStr: string): ColorPair {.inline.} =
  result = (
    fg: initColorCode(fgColorStr),
    bg: initColorCode(bgColorStr))

# TODO: Move
proc hexStrToIntStr(hexStr: string): string =
  result = $(fromHex[int](hexStr))
