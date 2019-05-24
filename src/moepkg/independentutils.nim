import strutils, math, terminal

proc numberOfDigits*(x: int): int = x.intToStr.len

proc calcTabWidth*(numOfBuffer: int): int = int(ceil(terminalWidth() / numOfBuffer))
