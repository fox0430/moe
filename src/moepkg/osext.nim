#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

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

proc splitPathExt*(path: Runes): tuple[head, tail: Runes] =
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

proc isPath*(runes: Runes): bool =
  if runes.len > 0:
    if runes.startsWith("/".ru) or
       runes.startsWith("./".ru) or
       runes.startsWith("../".ru) or
       runes.startsWith("~/".ru): return true
