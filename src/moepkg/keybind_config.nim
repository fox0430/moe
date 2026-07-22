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

## Runtime key-mapping resolution shared by the moerc.toml `[KeyMapping]` loader
## (editor_init.applyKeyMappings) and the runtime `:nmap`/`:noremap` commands.
## It turns an RHS string (plus optional args / force-key-sequence flag) into a
## registered command binding or a key-sequence remap on the registry.

import std/[strutils, tables, options]

import key_bindings, modes

proc parseModes(s: string): seq[EditorMode] =
  ## Parse a mode string to a seq of EditorMode enums.
  ## Supports all editor modes plus meta modes:
  ## - "all": all modes except CommandLine
  ## - "visualall": Visual, VisualLine, VisualBlock
  ## Returns empty seq for unknown modes.
  case s.toLowerAscii
  of "normal":
    @[EditorMode.Normal]
  of "insert":
    @[EditorMode.Insert]
  of "visual":
    @[EditorMode.Visual]
  of "visualline":
    @[EditorMode.VisualLine]
  of "visualblock":
    @[EditorMode.VisualBlock]
  of "replace":
    @[EditorMode.Replace]
  of "command":
    @[EditorMode.Command]
  of "filer":
    @[EditorMode.Filer]
  of "quickrun":
    @[EditorMode.QuickRun]
  of "logviewer":
    @[EditorMode.LogViewer]
  of "help":
    @[EditorMode.Help]
  of "buffermanager":
    @[EditorMode.BufferManager]
  of "bookmarkmanager":
    @[EditorMode.BookmarkManager]
  of "backupmanager":
    @[EditorMode.BackupManager]
  of "diffviewer":
    @[EditorMode.DiffViewer]
  of "recentfile":
    @[EditorMode.RecentFile]
  of "debug":
    @[EditorMode.Debug]
  of "config":
    @[EditorMode.Config]
  of "references":
    @[EditorMode.References]
  of "documentsymbol":
    @[EditorMode.DocumentSymbol]
  of "callhierarchy":
    @[EditorMode.CallHierarchy]
  of "terminal":
    @[EditorMode.Terminal]
  of "filetree":
    @[EditorMode.FileTree]
  of "all":
    var modes: seq[EditorMode] = @[]
    for m in EditorMode:
      if m != EditorMode.Command:
        modes.add(m)
    modes
  of "visualall":
    @[EditorMode.Visual, EditorMode.VisualLine, EditorMode.VisualBlock]
  else:
    @[]

proc parseOverlay(s: string): Option[OverlayKind] =
  ## Parse overlay string to OverlayKind enum
  case s.toLowerAscii
  of "command":
    some(okCommand)
  of "search":
    some(okSearch)
  of "rename":
    some(okRename)
  else:
    none(OverlayKind)

proc addKeySequenceMapping*(
    registry: KeyBindingRegistry,
    mode: EditorMode,
    keyStr: string,
    targetKeyStr: string,
    noremap = true,
) =
  ## Add a key→key_sequence mapping to the registry (runtimeMappings only).
  ## Unlike a command binding, this does NOT register in bindings/sequences
  ## tables. The mapping is replayed via playbackMacro at runtime. `noremap`
  ## defaults to true (verbatim replay); pass false to expand the target
  ## recursively through other user mappings (Vim's `:map` vs `:noremap`).
  let triggerKeys = parseKeyString(keyStr)
  if triggerKeys.len == 0:
    return

  let targetKeys = parseKeyString(targetKeyStr)
  if targetKeys.len == 0:
    return

  if not registry.runtimeMappings.hasKey(mode):
    registry.runtimeMappings[mode] = @[]

  registry.runtimeMappings[mode].add(
    RuntimeKeyMapping(
      kind: rmkKeySequence,
      triggerKeys: triggerKeys,
      triggerStr: keyStr,
      targetStr: targetKeyStr,
      noremap: noremap,
      targetKeys: targetKeys,
    )
  )

proc buildModeSwitchCommand*(
    modeStr: string
): tuple[cmd: Option[Command], err: string] =
  ## Build a synthetic `mode_switch` Command from a target-mode string. Shared
  ## by the [KeyMapping] loader and the runtime mapping resolver so the two
  ## cannot drift.
  let targetModes = parseModes(modeStr)
  if targetModes.len == 0:
    return (none(Command), "invalid target mode: " & modeStr)
  (
    some(
      Command(
        kind: ctModeSwitch,
        name: "mode_switch",
        description: "Switch to " & modeStr,
        targetMode: targetModes[0],
      )
    ),
    "",
  )

proc buildOverlaySwitchCommand*(
    overlayStr: string
): tuple[cmd: Option[Command], err: string] =
  ## Build a synthetic `overlay_switch` Command from an overlay string.
  let overlay = parseOverlay(overlayStr)
  if overlay.isNone:
    return (none(Command), "invalid overlay (command|search|rename): " & overlayStr)
  (
    some(
      Command(
        kind: ctOverlaySwitch,
        name: "overlay_switch",
        description: "Switch to " & overlayStr & " overlay",
        targetOverlay: overlay.get,
      )
    ),
    "",
  )

proc attachArgs(
    base: Command, args: seq[string]
): tuple[cmd: Option[Command], err: string] =
  ## Clone `base` with `args` attached. Only command kinds that carry an args
  ## field accept arguments.
  if base.kind notin {ctAction, ctTextObject, ctOperator, ctCustom}:
    return (none(Command), "command '" & base.name & "' does not take arguments")
  var c = base
  c.args = args
  (some(c), "")

proc resolveRuntimeCommandTarget(
    registry: KeyBindingRegistry, rhsStr: string
): tuple[cmd: Option[Command], err: string] =
  ## Resolve a runtime mapping RHS to a complex Command target. Returns:
  ##   (some cmd, "") -> resolved; caller records it as an rmkCommand mapping
  ##   (none, err)    -> a complex form was attempted but is invalid
  ##   (none, "")     -> not a complex form; caller falls back to the plain
  ##                     addRuntimeMapping (bare command name / key sequence)
  let tokens = rhsStr.splitWhitespace()
  if tokens.len == 0:
    return (none(Command), "")
  case tokens[0]
  of "mode_switch":
    if tokens.len < 2:
      return (none(Command), "mode_switch requires a target mode")
    return buildModeSwitchCommand(tokens[1])
  of "overlay_switch":
    if tokens.len < 2:
      return (none(Command), "overlay_switch requires a target overlay")
    return buildOverlaySwitchCommand(tokens[1])
  else:
    # command-with-args: a registered command name followed by arguments.
    if tokens.len >= 2 and registry.commandRegistry.hasKey(tokens[0]):
      return attachArgs(registry.commandRegistry[tokens[0]], tokens[1 ..^ 1])
    return (none(Command), "")

proc addRuntimeMappingExpanded*(
    registry: KeyBindingRegistry,
    mode: EditorMode,
    lhsStr: string,
    rhsStr: string,
    noremap = true,
    args: seq[string] = @[],
    forceKeySeq = false,
): string =
  ## Runtime `:nmap` / `[KeyMapping]` entry point. Understands complex RHS forms
  ## (`mode_switch <mode>`, `overlay_switch <overlay>`, `<command> <args...>`) in
  ## addition to the bare command name / key sequence handled by
  ## addRuntimeMapping. `forceKeySeq` binds `rhsStr` as a verbatim key sequence
  ## (skipping command resolution); explicit `args` attaches arguments to a
  ## registered command without whitespace-splitting (so args may contain
  ## spaces). Returns "" on success, an error message otherwise.
  if forceKeySeq:
    registry.addKeySequenceMapping(mode, lhsStr, rhsStr, noremap)
    return ""

  if args.len > 0:
    if not registry.commandRegistry.hasKey(rhsStr):
      return "unknown command '" & rhsStr & "'"
    let (cmd, err) = attachArgs(registry.commandRegistry[rhsStr], args)
    if err.len > 0:
      return err
    return registry.setRuntimeCommandMapping(mode, lhsStr, rhsStr, cmd.get, noremap)

  let (cmd, err) = resolveRuntimeCommandTarget(registry, rhsStr)
  if err.len > 0:
    return err
  if cmd.isSome:
    return registry.setRuntimeCommandMapping(mode, lhsStr, rhsStr, cmd.get, noremap)
  return registry.addRuntimeMapping(mode, lhsStr, rhsStr, noremap)

proc looksLikeUnknownCommand*(registry: KeyBindingRegistry, rhsStr: string): bool =
  ## Heuristic for catching a command-name typo in a bare [KeyMapping] RHS. An
  ## identifier-like token (3+ word chars) that is not a registered command and
  ## tokenizes into one single-char combo per character (a Vim-concat key
  ## sequence) almost always means a typo'd command rather than an intentional
  ## key sequence. The RHS is still applied as a key sequence; the caller only
  ## surfaces a warning. Special keys like "Escape" parse to a single combo, so
  ## the length check below excludes them.
  if rhsStr.len < 3 or registry.commandRegistry.hasKey(rhsStr):
    return false
  if not rhsStr.allCharsInSet({'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
    return false
  parseKeyString(rhsStr).len == rhsStr.len
