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

## Commands the config attaches to files: `[[Hook.entries]]` and
## `[[QuickRun.entries]]`.
##
## Pure matching and argv expansion. Commands never reach a shell: the line is
## tokenized first and each token expanded separately, so a path with spaces
## stays one argument.

import std/[options, os, sequtils, strutils]

import pkg/[regex, results]

import command_string
import encoding
import syntax/tokenizer
import types/background_process_types
import types/config_types

type FileCommandEntry* = HookEntry | QuickRunEntry
  ## An entry with `command`, `filetype`, `filter`, `filterRegex` and
  ## `workingDir`.

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

proc compileFilter*(entry: var FileCommandEntry): string =
  ## Compile `filter` once at load time; return the error or "" on success.
  entry.filterRegex = CompiledFilter()
  if entry.filter.len == 0:
    return ""
  try:
    entry.filterRegex = CompiledFilter(regex: some(re2(entry.filter)))
    return ""
  except RegexError as e:
    return e.msg

proc matchesFile*(
    entry: FileCommandEntry, path: string, language: SourceLanguage
): bool =
  ## True when `entry`'s `filetype` and `filter` let it apply to this file.
  ## An unparsable `filter` matches nothing, nor does any `filter` match the
  ## empty `path` of a buffer with no file name.
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
    if path.len == 0:
      return false
    # `regex` asserts on invalid UTF-8 input, and its behaviour there is
    # undefined in release. A file name is bytes, not text, so match the
    # spelling the path would be displayed in: each undecodable byte becomes
    # one U+FFFD, and a filter over the rest of the path still applies. A
    # filter cannot name such a byte anyway.
    let pathText = path.sanitizeInvalidUtf8()
    if entry.filterRegex.regex.isSome:
      if not pathText.contains(entry.filterRegex.regex.get):
        return false
    else:
      # Uncompiled filter: entry built in code, not loaded.
      var copied = entry
      discard copied.compileFilter()
      let regex = copied.filterRegex.regex
      if regex.isNone or not pathText.contains(regex.get):
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
    entry: FileCommandEntry, path: string, language: SourceLanguage, inMoeCwd = false
): BackgroundProcessCommand =
  ## Build the argv for `entry` against absolute `path`. The default and a
  ## relative `workingDir` are taken from the file's directory, or with
  ## `inMoeCwd` from moe's cwd, for a file whose directory means nothing.
  ## Empty `cmd` means the command line held no tokens or left a quote open.
  let parsed = parseCommandString(entry.command).valueOr:
    (cmd: "", args: newSeq[string]())
  # Only the configured directory is expanded; the default must stay verbatim.
  let workingDir =
    if entry.workingDir.len > 0:
      let dir = expandToken(entry.workingDir, path, language)
      if dir.isAbsolute or inMoeCwd:
        # A relative one left as is: the child's chdir takes it from moe's cwd.
        dir
      else:
        normalizedPath(parentDir(path) / dir)
    elif inMoeCwd:
      "" # The process starter's moe's cwd.
    else:
      parentDir(path)
  BackgroundProcessCommand(
    cmd: expandToken(parsed.cmd, path, language),
    args: parsed.args.mapIt(expandToken(it, path, language)),
    workingDir: workingDir,
  )
