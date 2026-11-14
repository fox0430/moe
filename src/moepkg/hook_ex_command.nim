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

## The moe Ex command a `BufWritePre` entry runs instead of a program.
##
## One reading for both ends: the loader checks `exCommand` with it and the
## write runs what it returns.

import std/strutils

import pkg/results

import command_config
import command_line
import buffer/search

type
  HookExKind* = enum
    ## The moe Ex commands a `BufWritePre` entry may run.
    hekSubstitute
    hekStripWhitespace

  HookExCommand* = object ## An `exCommand` as read.
    case kind*: HookExKind
    of hekSubstitute:
      range*: ExLineRange
      pattern*: string
      replacement*: string
      flags*: string ## As typed; the case is decided per run, as for a typed :s.
    of hekStripWhitespace:
      discard

const
  HookSubstituteFlags = {'g', 'i', 'I', 'e'}
    ## The :s flags a hook may use; the others hang on the state of the editor
    ## or mean nothing in a hook.
  ExCommandExpected* = "`%s/pattern/replacement/flags` or `stripwhitespace`"

var builtinParser {.threadvar.}: CommandLineParser
  ## Built once: reading a command line does not change it.

proc builtinCommands(): CommandLineParser =
  if builtinParser.isNil:
    builtinParser = newBuiltinCommandLineParser()
  builtinParser

proc exCommandText*(exCommand: string): string =
  ## `exCommand` without the colons and blanks in front of it, which Vim skips
  ## (skip_colon_white). Blanks after it stay: a :s with no closing delimiter
  ## ends its pattern or replacement with them.
  exCommand.strip(trailing = false, chars = Whitespace + {':'})

proc usesCurrentLine(range: ExLineRange): bool =
  ## Whether `range` hangs on where the cursor is.
  case range.kind
  of erkCurrent:
    true
  of erkAll:
    false
  of erkAddresses:
    range.first.base == eabCurrent or range.last.base == eabCurrent

proc outsideEveryBuffer(a: ExAddress): bool =
  ## Whether `a` names a line of no buffer: above line 0, or below `$`.
  case a.base
  of eabLine:
    a.addressLine(0, 0) < -1
  of eabLast:
    a.offset > 0
  of eabCurrent:
    false

proc isBackwards(range: ExLineRange): bool =
  ## Whether `range` ends above its start in every buffer: two line numbers, or
  ## two `$`, the second above the first, judged before line 0 becomes line 1
  ## as a write judges it.
  if range.kind != erkAddresses or range.first.base != range.last.base:
    return false
  case range.first.base
  of eabLine:
    range.first.addressLine(0, 0) > range.last.addressLine(0, 0)
  of eabLast:
    range.first.offset > range.last.offset
  of eabCurrent:
    false

proc refusedFlag(flags: string): string =
  ## The first flag of a hook's :s that is refused, empty when none is. The
  ## command line refused what is not a flag, up to a blank or a comment.
  for c in flags:
    if c in Whitespace or c == '"':
      break
    if c notin HookSubstituteFlags:
      return $c
  ""

proc refusedReplacement(replacement: string): string =
  ## What in the replacement of a hook's :s is refused, empty when none is:
  ## Vim reads `~` as the previous replacement and a leading `\=` as an
  ## expression, which moe would read as text.
  let parsed = parseReplacement(replacement)
  if parsed.expression:
    "a leading `\\=` in the replacement"
  elif parsed.previous:
    "`~` in the replacement (write `\\~`)"
  else:
    ""

proc parseHookExCommand*(exCommand: string): Result[HookExCommand, string] =
  ## Read `exCommand`, or say what was expected instead. Only built-in command
  ## names count, so `[CommandAliases]` cannot change what a hook runs.
  let parser = builtinCommands()
  let parsed = parser.parseCommandLine(exCommand.exCommandText)
  let executed = parser.execute(parsed)
  case executed.kind
  of claStripWhitespace:
    # The parser refuses a range in front of it.
    if parsed.args.len > 0 or parsed.flags.len > 0:
      return err("`stripwhitespace` with no argument or `!`")
    ok HookExCommand(kind: hekStripWhitespace)
  of claSubstitute:
    let range = executed.substituteRange
    if range.usesCurrentLine:
      return err("a :s range of `%`, line numbers or `$`, which the cursor does not move")
    if range.kind == erkAddresses and
        (range.first.outsideEveryBuffer or range.last.outsideEveryBuffer):
      return err("a :s range whose lines a file can have (not above line 0 or below `$`)")
    if range.isBackwards:
      return err("a :s range that does not end above its start")
    let flag = refusedFlag(executed.substituteFlagsText)
    if flag.len > 0:
      return err("a :s without the `" & flag & "` flag (only g, i, I and e)")
    let replacement = refusedReplacement(executed.replacement)
    if replacement.len > 0:
      return err("a :s without " & replacement)
    # Whether it compiles does not hang on the case.
    let invalid = invalidRegex(executed.pattern, false, executed.match)
    if invalid.len > 0:
      return err("a :s pattern that compiles: " & invalid)
    ok HookExCommand(
      kind: hekSubstitute,
      range: range,
      pattern: executed.pattern,
      replacement: executed.replacement,
      flags: executed.substituteFlagsText,
    )
  of claUnknown:
    if executed.errorMessage.len > 0:
      err(ExCommandExpected & " (" & executed.errorMessage & ")")
    else:
      err(ExCommandExpected)
  else:
    err(ExCommandExpected)
