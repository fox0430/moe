import std/[os, strutils]
import unicodeext

export os

# The difference with `std/os.splitPath` is that it does not delete '/'.
# Exmaple:
#   os.splitPath("../dir") == (head: "..", tail: "dir")
#   osext.splitPathExt("../dir") == (head: "../", tail: "dir")
# Exmaple 2:
#   os.splitPath("/dir/a") == (head: "/dir", tail: "a")
#   osext.splitPathExt("/dir/a") == (head: "/dir/", tail: "a")
proc splitPathExt*(path: string): tuple[head, tail: string] =
  let
    r = splitPath(path)
    head =
      if path.count('/') > 1: r.head & "/"
      elif path.startsWith("./"): "./"
      elif path.startsWith("../"): "../"
      elif path.startsWith("~/"): "~/"
      else: r.head
  return (head: head, tail: r.tail)

proc splitPathExt*(path: seq[Rune]): tuple[head, tail: seq[Rune]] =
  let
    r = splitPath($path)
    head =
      if path.count('/'.ru) > 1: r.head.ru & "/".ru
      elif path.startsWith("./".ru): "./".ru
      elif path.startsWith("../".ru): "../".ru
      elif path.startsWith("~/".ru): "~/".ru
      else: r.head.ru
  return (head: head, tail: r.tail.ru)

proc getPathTail*(path: string): string {.inline.} =
  let (_, tail) = path.splitPath
  return tail

proc isPath*(runes: seq[Rune]): bool =
  if runes.len > 0:
    if runes.startsWith("/".ru) or
       runes.startsWith("./".ru) or
       runes.startsWith("../".ru) or
       runes.startsWith("~/".ru): return true
