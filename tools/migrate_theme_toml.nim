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

## Migrate a moe theme TOML file from the legacy `key`/`keyBg` pair format
## to the new inline-table format (`key = { fg = "...", bg = "..." }`).
##
## Usage:
##   nim r tools/migrate_theme_toml.nim path/to/theme.toml       # prints to stdout
##   nim r tools/migrate_theme_toml.nim --in-place theme.toml    # rewrites in place (+ .bak)
##   nim r tools/migrate_theme_toml.nim --check theme.toml       # exit 0 if already new-format
##
## Migration rules (see commit 516b0196):
##   - Top-level `foreground` / `background` stay as plain strings.
##   - `key` (+ optional `keyBg`) -> `key = { fg = "...", bg = "..." }`
##     (bg omitted when the legacy file had no `keyBg`).
##   - `currentLineBg`   -> `currentLine    = { bg = "..." }`   (bg-only entity)
##   - `currentColumnBg` -> `currentColumn  = { bg = "..." }`   (bg-only entity)
##   - `configModePopupBg` (fg) + `configModePopupBgBg` (bg)
##                       -> `configModePopup = { fg = "...", bg = "..." }`
##
## Files already in the new inline-table format are detected and returned
## unchanged so the tool is safe to run repeatedly.
##
## Caveats:
##   - Comments (header and inline) are not preserved; the output is
##     rebuilt from the parsed TOML AST.
##   - Only the `[Colors]` section is emitted; any other top-level
##     sections in the input are dropped.
##   - `--in-place` overwrites an existing `<file>.bak` without warning.

import std/[os, strutils, tables]

import pkg/parsetoml

type
  MigrationError* = object of CatchableError

  Entry = object ## A single new-format line to emit.
    newKey: string
    fg: string # empty means "no fg"
    bg: string # empty means "no bg"

const
  ColorsSection = "Colors"
  BgOnlyRenames =
    {"currentLineBg": "currentLine", "currentColumnBg": "currentColumn"}.toTable
  ## Old fg/bg key pairs whose base name is renamed in the new format.
  ## Old `configModePopupBg`   carries the fg of EditorColorPairIndex.configModePopupBg.
  ## Old `configModePopupBgBg` carries its bg.
  ## New format keys the whole pair as `configModePopup`.
  PairRenames = {"configModePopupBg": "configModePopup"}.toTable

proc tomlString(v: TomlValueRef): string =
  ## Return the string payload, or raise if `v` isn't a string.
  if v.kind != TomlValueKind.String:
    raise newException(MigrationError, "expected string value, got " & $v.kind)
  v.stringVal

proc isAlreadyMigrated(colors: TomlTableRef): bool =
  ## Returns true iff every non-top-level entry is already an inline table.
  ## The presence of *any* legacy flat string outside foreground/background
  ## means the file still needs migration.
  for key, val in colors[].pairs:
    if key == "foreground" or key == "background":
      continue
    if val.kind != TomlValueKind.String:
      continue
    return false
  true

proc collectEntries(colors: TomlTableRef): seq[Entry] =
  ## Walk the legacy [Colors] table and produce the list of new-format
  ## entries in original key insertion order. The first time a base key
  ## is seen (either via the fg variant or via a bg-only orphan) it gets
  ## appended; subsequent matches (e.g. when the `keyBg` line is processed
  ## after `key`) fill in the missing field.
  var
    entries: seq[Entry] = @[]
    indexOf = initTable[string, int]() # newKey -> position in entries

  template upsert(nk, fgVal, bgVal: string) =
    let newKeyExpr = nk
    if newKeyExpr in indexOf:
      let i = indexOf[newKeyExpr]
      if fgVal.len > 0 and entries[i].fg.len == 0:
        entries[i].fg = fgVal
      if bgVal.len > 0 and entries[i].bg.len == 0:
        entries[i].bg = bgVal
    else:
      indexOf[newKeyExpr] = entries.len
      entries.add Entry(newKey: newKeyExpr, fg: fgVal, bg: bgVal)

  for key, val in colors[].pairs:
    if key == "foreground" or key == "background":
      continue

    if val.kind == TomlValueKind.Table:
      # Already-migrated entry passing through. Preserve it as-is.
      let sub = val.tableVal
      var fg, bg: string
      if sub[].hasKey("fg"):
        fg = sub[]["fg"].tomlString
      if sub[].hasKey("bg"):
        bg = sub[]["bg"].tomlString
      upsert(key, fg, bg)
      continue

    if val.kind != TomlValueKind.String:
      raise newException(
        MigrationError, "unexpected value kind for '" & key & "': " & $val.kind
      )

    let value = val.stringVal

    # Bg-only enum: enum name ends in "Bg" and the new key drops the suffix.
    if key in BgOnlyRenames:
      upsert(BgOnlyRenames[key], "", value)
      continue

    # Renamed pair: configModePopupBg (fg) and configModePopupBgBg (bg)
    # collapse to `configModePopup`.
    if key in PairRenames:
      upsert(PairRenames[key], value, "")
      continue
    if key.endsWith("Bg") and key[0 ..< key.len - 2] in PairRenames:
      upsert(PairRenames[key[0 ..< key.len - 2]], "", value)
      continue

    # Plain `keyBg` carries the bg of base key.
    if key.endsWith("Bg"):
      let base = key[0 ..< key.len - 2]
      upsert(base, "", value)
      continue

    # Plain base key carries the fg.
    upsert(key, value, "")

  entries

proc renderInlineTable(key, fg, bg: string): string =
  ## Format `{ fg = "...", bg = "..." }`, omitting whichever side is empty.
  ## At least one of fg/bg must be non-empty; an entry with both sides empty
  ## indicates the source file has an empty color value (e.g. `lineNum = ""`).
  if fg.len == 0 and bg.len == 0:
    raise newException(
      MigrationError, "entry '" & key & "' has no fg or bg value (empty color?)"
    )
  if fg.len > 0 and bg.len > 0:
    "{ fg = \"" & fg & "\", bg = \"" & bg & "\" }"
  elif fg.len > 0:
    "{ fg = \"" & fg & "\" }"
  else:
    "{ bg = \"" & bg & "\" }"

proc migrateThemeToml*(input: string): string =
  ## Pure transformation: legacy TOML text in, new-format TOML text out.
  ## Raises MigrationError on malformed input.
  let root =
    try:
      parsetoml.parseString(input)
    except CatchableError as e:
      raise newException(MigrationError, "failed to parse TOML: " & e.msg)

  if root.kind != TomlValueKind.Table or not root.tableVal[].hasKey(ColorsSection):
    raise newException(MigrationError, "missing [" & ColorsSection & "] section")

  let colorsVal = root.tableVal[][ColorsSection]
  if colorsVal.kind != TomlValueKind.Table:
    raise newException(MigrationError, "[" & ColorsSection & "] is not a table")
  let colors = colorsVal.tableVal

  if isAlreadyMigrated(colors):
    return input

  var lines: seq[string] = @[]
  lines.add "[" & ColorsSection & "]"
  lines.add ""

  if colors[].hasKey("foreground"):
    lines.add "foreground = \"" & colors[]["foreground"].tomlString & "\""
  if colors[].hasKey("background"):
    lines.add "background = \"" & colors[]["background"].tomlString & "\""
  if colors[].hasKey("foreground") or colors[].hasKey("background"):
    lines.add ""

  for entry in collectEntries(colors):
    lines.add entry.newKey & " = " & renderInlineTable(entry.newKey, entry.fg, entry.bg)

  lines.add "" # trailing newline
  lines.join("\n")

proc usage() =
  stderr.writeLine """Usage:
  migrate_theme_toml [--in-place] <theme.toml>
  migrate_theme_toml --check <theme.toml>

Options:
  --in-place   Rewrite the file in place; original is saved as <file>.bak.
               An existing <file>.bak is overwritten without warning.
  --check      Exit 0 if the file is already in the new format, 1 otherwise.
               No output is written.

Notes:
  Comments and any non-[Colors] sections in the input are not preserved;
  the output is rebuilt from the parsed TOML AST."""

proc main() {.used.} =
  var
    inPlace = false
    check = false
    path = ""
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    case arg
    of "--in-place":
      inPlace = true
    of "--check":
      check = true
    of "-h", "--help":
      usage()
      quit(0)
    else:
      if path.len > 0:
        usage()
        quit(2)
      path = arg

  if path.len == 0 or (inPlace and check):
    usage()
    quit(2)

  if not fileExists(path):
    stderr.writeLine "error: file not found: " & path
    quit(1)

  let original = readFile(path)

  if check:
    let migrated = migrateThemeToml(original)
    quit(if migrated == original: 0 else: 1)

  let migrated = migrateThemeToml(original)

  if inPlace:
    if migrated == original:
      stderr.writeLine "already migrated: " & path
      return
    writeFile(path & ".bak", original)
    writeFile(path, migrated)
    stderr.writeLine "migrated: " & path & " (backup at " & path & ".bak)"
  else:
    stdout.write(migrated)

when isMainModule:
  try:
    main()
  except MigrationError as e:
    stderr.writeLine "error: " & e.msg
    quit(1)
