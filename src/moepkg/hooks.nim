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

## User hooks: commands attached to editor events.
##
## Pure matching and argv expansion; running them belongs to `editor_hooks`.
## Commands never reach a shell: the line is tokenized first and each token
## expanded separately, so a path with spaces stays one argument.

import std/[options, os, sequtils, strutils]

import pkg/regex

import command_string
import syntax/tokenizer
import types/background_process_types
import types/config_types

export HookConfig, HookEntry, HookEvent, ValidHookEvents, DefaultHookTimeout

type HookCommand* = object
  ## One entry resolved against one file, ready to exec: tokenized, expanded,
  ## with an absolute path.
  event*: HookEvent
  path*: string ## Absolute path the hook fired for.
  command*: string ## The command line as written, to label its output.
  cmd*: string
  args*: seq[string]
  workingDir*: string
  timeout*: int
  showOutput*: bool

proc `==`*(a, b: HookEntry): bool =
  ## Compare user-written fields; `filterRegex` is derived and `Regex2` lacks `==`.
  a.event == b.event and a.filetype == b.filetype and a.filter == b.filter and
    a.command == b.command and a.workingDir == b.workingDir and a.timeout == b.timeout and
    a.showOutput == b.showOutput

proc parseHookEvent*(s: string): HookEvent =
  ## Parse `s` as `HookEvent`. Called by name from `config_macros`' enum
  ## loader once `s` is in `ValidHookEvents`, so the fallback to the first
  ## event is never reached from a config file.
  for event in HookEvent:
    if $event == s:
      return event
  HookEvent.low

proc filetypeName*(language: SourceLanguage): string =
  ## The `${filetype}` spelling of a language.
  sourceLanguageToFiletype[language]

proc filetypeLanguage*(name: string): Option[SourceLanguage] =
  ## Resolve a `filetype` entry to its language, or `none`.
  ## Accepts display names, abbreviations, and `${filetype}` spellings.
  for language in SourceLanguage:
    if language != langNone and cmpIgnoreStyle(name, filetypeName(language)) == 0:
      return some(language)
  let language = getSourceLanguage(name)
  # `getSourceLanguage` reports an unknown name as `langNone`.
  if language != langNone:
    return some(language)
  none(SourceLanguage)

proc isValidFiletype*(name: string): bool =
  filetypeLanguage(name).isSome

proc compileFilter*(entry: var HookEntry): string =
  ## Compile `filter` once at load time; return the error or "" on success.
  entry.filterRegex = none(Regex2)
  if entry.filter.len == 0:
    return ""
  try:
    entry.filterRegex = some(re2(entry.filter))
    return ""
  except RegexError as e:
    return e.msg

proc matches*(
    entry: HookEntry, event: HookEvent, path: string, language: SourceLanguage
): bool =
  ## True when `entry` applies to this event and file.
  ## An unparsable `filter` matches nothing.
  if entry.event != event:
    return false
  if entry.filetype.len > 0:
    var matched = false
    for name in entry.filetype:
      let wanted = filetypeLanguage(name)
      if wanted.isSome and wanted.get == language:
        matched = true
        break
    if not matched:
      return false
  if entry.filter.len > 0:
    if entry.filterRegex.isSome:
      if not path.contains(entry.filterRegex.get):
        return false
    else:
      # Uncompiled filter: entry built in code, not loaded.
      var copied = entry
      discard copied.compileFilter()
      if copied.filterRegex.isNone or not path.contains(copied.filterRegex.get):
        return false
  true

proc expandPlaceholders*(
    token: string, path: string, language: SourceLanguage
): string =
  ## Replace `${...}` placeholders in one argv token.
  ## Unknown ones are left verbatim for the command itself.
  if not token.contains("${"):
    return token

  let (dir, name, ext) = splitFile(path)
  result = token
  result = result.multiReplace(
    ("${file}", path),
    ("${dir}", dir),
    ("${filename}", name & ext),
    ("${basename}", name),
    (
      "${ext}",
      if ext.len > 0:
        ext[1 ..^ 1]
      else:
        "",
    ),
    ("${filetype}", filetypeName(language)),
  )

proc expandToken(token: string, path: string, language: SourceLanguage): string =
  ## Expand a leading `~` the user wrote (no shell expands it), then the
  ## placeholders: a file name that starts with `~` stays a name.
  expandPlaceholders(expandTilde(token), path, language)

proc toCommand*(
    entry: HookEntry, path: string, language: SourceLanguage
): BackgroundProcessCommand =
  ## Build the argv for `entry` against absolute `path`.
  ## Empty `cmd` means the command line held no tokens.
  let parsed = parseCommandString(entry.command)
  # Only the configured directory is expanded; the default must stay verbatim.
  # A relative one is taken from the file's directory, not moe's cwd.
  let workingDir =
    if entry.workingDir.len > 0:
      let dir = expandToken(entry.workingDir, path, language)
      if dir.isAbsolute:
        dir
      else:
        normalizedPath(parentDir(path) / dir)
    else:
      parentDir(path)
  BackgroundProcessCommand(
    cmd: expandToken(parsed.cmd, path, language),
    args: parsed.args.mapIt(expandToken(it, path, language)),
    workingDir: workingDir,
  )

proc hooksFor*(
    config: HookConfig, event: HookEvent, path: string, language: SourceLanguage
): seq[HookEntry] =
  ## Every enabled entry that applies, in config order.
  if not config.enable or path.len == 0:
    return @[]
  for entry in config.entries:
    if entry.matches(event, path, language):
      result.add entry
