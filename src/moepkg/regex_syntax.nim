#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## Reading the syntax of a regex as nim-regex reads it.

import std/strutils

import pkg/regex/[parser, types, common]

import char_case

proc skipClass*(s: string, start: int): int =
  ## The index of the `]` closing the `[...]` class whose items start at
  ## `start`, `s.len` without one, as the regex reads it: a `]` first is an
  ## item, a backslash escapes the char after it and `[:name:]` is one item.
  var i = start
  if i < s.len and s[i] == '^':
    i.inc
  if i < s.len and s[i] == ']':
    i.inc
  while i < s.len and s[i] != ']':
    if s[i] == '\\':
      i += 2
    elif s.continuesWith("[:", i):
      let colon = s.find(':', i + 2)
      i =
        if colon >= 0 and s.continuesWith(":]", colon):
          colon + 2
        else:
          i + 1
    else:
      i.inc
  min(i, s.len)

proc hasUpperLiteral*(pattern: string): bool =
  ## Whether regex `pattern` has an upper case letter it matches as it is, by
  ## its parse: a literal, a class item or a class range end (`[!-~]` has
  ## none). An escape that parses to a letter counts (`\Q`, `\x41`); one that
  ## parses to a class or a property (`\S`, `\p{Lu}`) does not, nor do group
  ## flags and names or `(?x)` comments. False when `pattern` does not parse,
  ## as then it matches nothing.
  let exp =
    try:
      parse(pattern)
    except RegexError:
      return false
  for n in exp.s:
    case n.kind
    of reChar:
      if n.cp.utfIsUpper:
        return true
    of reInSet, reNotSet:
      for r in n.cps:
        if r.utfIsUpper:
          return true
      for range in n.ranges:
        if range.a.utfIsUpper or range.b.utfIsUpper:
          return true
    else:
      discard
  false
