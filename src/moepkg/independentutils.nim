import strutils, math

proc numberOfDigits*(x: int): int {.inline.} = x.intToStr.len

proc calcTabWidth*(numOfBuffer, windowSize: int): int {.inline.} = int(ceil(windowSize / numOfBuffer))

proc normalizeHex*(s: string): string =
  var count = 0
  for ch in s:
    if ch == '0':
      count.inc
    else:
      break

  result = s[count .. ^1]
