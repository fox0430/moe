import std/[strutils, math, random, osproc]

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

proc isInt*(str: string): bool =
  try:
    discard str.parseInt
    return true
  except:
    discard

proc genDelimiterStr*(buffer: string): string =
  while true:
    for _ in 0 .. 10: add(result, char(rand(int('A') .. int('Z'))))
    if buffer != result: break

proc execCmdExNoOutput*(cmd: string): int {.inline.} =
  (execCmdEx(cmd)).exitCode
