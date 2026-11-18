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

import std/[options, strutils, unittest]

import pkg/results

import ../src/moepkg/picker/catalog

proc typed(line: string): Result[PickerSpec, string] =
  ## `line` as typed after `:`, its arguments those after the name.
  let argText =
    if ' ' in line:
      line[line.find(' ') + 1 ..^ 1]
    else:
      ""
  parsePickerCommand(argText, line.splitWhitespace[1 ..^ 1])

suite "picker: :picker's arguments":
  test "A source, with nothing after it":
    let spec = typed("picker buffers")
    check spec.isOk
    check spec.get.source == some(psBuffers)
    check spec.get.query.isNone
    check not spec.get.resume

  test "No source lists the sources":
    let spec = typed("picker")
    check spec.isOk
    check spec.get.source.isNone

  test "The query after `--` is what was typed, blanks and dashes included":
    check typed("picker buffers -- -foo bar").get.query == some("-foo bar")
    check typed("picker buffers -- foo  bar").get.query == some("foo  bar")
    check typed("picker buffers --\tfoo\tbar").get.query == some("foo\tbar")
    check typed("picker buffers -- foo -- bar").get.query == some("foo -- bar")

  test "`--` with nothing after it starts with an empty query":
    check typed("picker buffers --").get.query == some("")

  test "A query with no source":
    let spec = typed("picker -- foo")
    check spec.get.source.isNone
    check spec.get.query == some("foo")

  test "A mapping's words each stay whole after `--`":
    let spec = parsePickerCommand("", @["oldfiles", "--", "foo  bar", "baz"])
    check spec.get.source == some(psOldfiles)
    check spec.get.query == some("foo  bar baz")

  test "A mapping's words follow the query typed on the line":
    let spec = parsePickerCommand("buffers -- a  b", @["buffers", "--", "a", "b", "c"])
    check spec.get.query == some("a  b c")

  test "Words a mapping gives with no line, as a configuration is checked":
    let spec = parsePickerCommand("", @["buffers", "--", "x"])
    check spec.get.source == some(psBuffers)
    check spec.get.query == some("x")

  test "resume":
    let spec = typed("picker resume")
    check spec.get.resume
    check spec.get.source.isNone

  test "An unknown source":
    let spec = typed("picker filez")
    check spec.isErr
    check spec.error == "Unknown picker source: filez"

  test "Words after the source are trailing characters":
    check typed("picker buffers foo").error == "E488: Trailing characters: foo"
    check typed("picker resume -- foo").error == "E488: Trailing characters: -- foo"
