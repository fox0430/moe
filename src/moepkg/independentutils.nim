import strutils, math

proc numberOfDigits*(x: int): int = x.intToStr.len

proc calcTabWidth*(numOfBuffer, windowSize: int): int = int(ceil(windowSize / numOfBuffer))
