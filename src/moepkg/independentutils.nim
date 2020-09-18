import strutils, math

proc numberOfDigits*(x: int): int {.inline.} = x.intToStr.len

proc calcTabWidth*(numOfBuffer, windowSize: int): int {.inline.} = int(ceil(windowSize / numOfBuffer))
