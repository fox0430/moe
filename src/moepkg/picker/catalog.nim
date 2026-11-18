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

## The sources `:picker` knows and how it reads its arguments. Free of the
## editor, so the command line and the key mappings check them alike.

import std/[options, strutils]

import pkg/results

type
  PickerSourceKind* = enum
    ## The sources `:picker` takes, by the name it takes them by.
    psBuffers = "buffers"
    psOldfiles = "oldfiles"

  PickerSpec* = object ## What `:picker` asks for.
    source*: Option[PickerSourceKind] ## None for the list of sources
    query*: Option[string] ## What follows `--`, the query it starts with
    resume*: bool ## `:picker resume`: the last picker, as it was left

const
  PickerSourceDescriptions*: array[PickerSourceKind, string] = [
    psBuffers: "Buffers, as :ls lists them",
    psOldfiles: "Files edited before, the last one first",
  ]
  PickerResume* = "resume"
  PickerResumeDescription* = "Go back to the last picker as it was left"

proc pickerSource*(name: string): Option[PickerSourceKind] =
  for source in PickerSourceKind:
    if $source == name:
      return some(source)
  none(PickerSourceKind)

proc ownWords(argText: string): seq[tuple[text: string, last: int]] =
  ## The words of `argText`, each with the byte after it.
  var i = 0
  while true:
    while i < argText.len and argText[i] in Whitespace:
      inc i
    if i >= argText.len:
      break
    let start = i
    while i < argText.len and argText[i] notin Whitespace:
      inc i
    result.add (argText[start ..< i], i)

proc parsePickerCommand*(
    argText: string, args: seq[string]
): Result[PickerSpec, string] =
  ## `:picker [source] [-- query]`. `args` are the line's words and
  ## then those a mapping passes, each whole; `argText` the line's as typed.
  ## Everything after `--` is the query: as typed, blanks and all, on the line,
  ## and joined with a space from a mapping's words.
  let own = ownWords(argText)
  var words: seq[string]
  for w in own:
    words.add w.text
  if args.len > own.len:
    words.add args[own.len ..^ 1]
  let dashes = words.find("--")
  var spec = PickerSpec()
  if dashes >= 0:
    var query = ""
    if dashes < own.len:
      var i = own[dashes].last
      while i < argText.len and argText[i] in Whitespace:
        inc i
      query = argText[i ..^ 1]
      if words.len > own.len:
        if query.len > 0:
          query.add ' '
        query.add words[own.len ..^ 1].join(" ")
    else:
      query = words[dashes + 1 ..^ 1].join(" ")
    spec.query = some(query)
    words.setLen dashes
  if words.len == 0:
    return ok(spec)
  if words[0] == PickerResume:
    spec.resume = true
  elif words[0].pickerSource.isSome:
    spec.source = words[0].pickerSource
  else:
    return err("Unknown picker source: " & words[0])
  let rest = words[1 ..^ 1]
  if rest.len > 0 or (spec.resume and spec.query.isSome):
    let trailing =
      if spec.query.isSome:
        (rest & @["--", spec.query.get]).join(" ")
      else:
        rest.join(" ")
    return err("E488: Trailing characters: " & trailing.strip)
  ok(spec)
