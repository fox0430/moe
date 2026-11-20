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

## TOML loader and serializer for `[Filetype]`: the user's file type detection,
## as Neovim's `vim.filetype.add`. Only `[Filetype.extension]` exists so far.

import std/[algorithm, options, sequtils, strutils, tables]

import pkg/parsetoml

import ../file_command
import ../syntax/tokenizer

import base, save_base

const FiletypeSectionName* = "Filetype"

# The sub-tables of [Filetype].
const FiletypeSubSectionNames* = ["extension"]

proc canonicalFiletype(name: string): string =
  ## The `${filetype}` spelling of `name`, `none` for plain text, or "" when
  ## `name` is no file type.
  if cmpIgnoreStyle(name, NoFiletype) == 0:
    return NoFiletype
  let language = filetypeLanguage(name)
  if language.isSome:
    return filetypeName(language.get)
  ""

proc loadFiletypeConfig*(
    table: TomlTableRef, extensions: var Table[string, string], vr: var ValidationResult
) =
  ## Load `[Filetype.extension]`. Value format: `foo = "java"`; the key is the
  ## extension without the dot, matched case-sensitively.
  checkUnknownKeys(table, FiletypeSubSectionNames, FiletypeSectionName, vr)
  const section = FiletypeSectionName & ".extension"
  if not expectTable(table, "extension", vr, FiletypeSectionName):
    return
  for ext, value in table["extension"].getTable():
    let key = fullKey(section, ext)
    if ext.len == 0 or ext.contains({'\0' .. ' ', '.', '/', '\\', '\x7F'}):
      vr.addError(key, ext, "file extension without the dot")
      continue
    if value.kind != TomlValueKind.String:
      vr.addError(key, $value.kind, "string")
      continue
    let name = canonicalFiletype(value.getStr())
    if name.len == 0:
      vr.addError(key, value.getStr(), "filetype name or \"none\"")
      continue
    extensions[ext] = name

proc appendFiletypeToml*(lines: var seq[string], extensions: Table[string, string]) =
  if extensions.len > 0:
    lines.add "[Filetype.extension]"
    for ext in toSeq(extensions.keys).sorted:
      lines.add toTomlKey(ext) & " = " & toTomlString(extensions[ext])
    lines.add ""
