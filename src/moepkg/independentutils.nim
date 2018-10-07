import strutils

proc numberOfDigits*(x: int): int = x.intToStr.len
