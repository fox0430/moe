import std/[unittest, macros]
import moepkg/[osext, unicodeext]

suite "osext: isPath":
  # Generate test code
  # Check return values of suggestionwindow.isPath
  macro isPathTest(testIndex: int, expectVal: bool, line: seq[Rune]): untyped =
    quote do:
      let testTitle = "Case " & $`testIndex` & ": " & $`line`

      # Generate test code
      test testTitle:
        check `expectVal` == isPath(`line`)

  const testCases: seq[tuple[expectVal: bool, line: seq[Rune]]] = @[
    (expectVal: true, line: "/".ru),
    (expectVal: true, line: "/h".ru),
    (expectVal: true, line: "/home/".ru),
    (expectVal: true, line: "/home/user".ru),
    (expectVal: true, line: "./".ru),
    (expectVal: true, line: "./Downloads".ru),
    (expectVal: true, line: "./Downloads/Images/".ru),
    (expectVal: false, line: "test /home/".ru),
    (expectVal: false, line: "test".ru),
    (expectVal: false, line: "te/st".ru)]

  # Generate test code by macro
  for i, c in testCases:
    isPathTest(i, c.expectVal, c.line)

suite "osext: splitPathExt":
  # Generate test code
  # Check return values of suggestionwindow.splitPathExtTest
  macro splitPathExtTest(
    testIndex: int,
    expectVal: tuple[head, tail: seq[Rune]],
    path: seq[Rune]): untyped =

    quote do:
      let testTitle = "Case " & $`testIndex` & ": " & $`path`

      # Generate test code
      test testTitle:
        check `expectVal` == splitPathExt(`path`)

  const
    testCases: seq[tuple[expectVal: tuple[head, tail: seq[Rune]], path: seq[Rune]]] = @[
      (expectVal: (head: "/".ru, tail: "".ru), path: "/".ru),
      (expectVal: (head: "./".ru, tail: "".ru), path: "./".ru),
      (expectVal: (head: "../".ru, tail: "".ru), path: "../".ru),
      (expectVal: (head: "/".ru, tail: "home".ru), path: "/home".ru),
      (expectVal: (head: "/home/".ru, tail: "".ru), path: "/home/".ru),
      (expectVal: (head: "/home/".ru, tail: "dir".ru), path: "/home/dir".ru),
      (expectVal: (head: "../".ru, tail: "home".ru), path: "../home".ru),
      (expectVal: (head: "../home/".ru, tail: "dir".ru), path: "../home/dir".ru)]

  # Generate test code by macro
  for i, c in testCases:
    splitPathExtTest(i, c.expectVal, c.path)
