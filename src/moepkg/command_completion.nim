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

## Command mode auto-completion system
##
## This module provides command completion functionality for command mode.
## It collects available commands and presents them in a popup menu for selection.

import std/[algorithm, strutils, unicode, tables, os]

import pkg/celina

import
  command_line, command_line_commands, fuzzy_match, help_description, setting_options,
  popup_render, color

import types/command_completion_types
export command_completion_types

const
  DefaultMaxVisible* = 10
  MinPopupWidth* = 20
  MaxPopupWidth* = 60
  PopupPadding* = 2
  DescriptionGap* = 2 # Gap between command and description

# Command descriptions — derived from the canonical `CommandLineCommandTable`
# in `command_line_commands.nim` so the completion popup, the help text, and
# the parser dispatch all share one source of truth. Specs with an empty
# completionDescription (long forms used only by TOML config) are excluded.
const CommandDescriptions*: Table[string, string] = block:
  var t: Table[string, string]
  for spec in CommandLineCommandTable:
    if spec.completionDescription.len > 0:
      t[spec.name] = spec.completionDescription
  t

# Commands that take file path arguments. Derived from the canonical
# `CommandLineCommandTable` filtered on `takesFilePath` so the list of
# names eligible for file-path completion lives in exactly one place.
const FilePathCommands*: seq[string] = block:
  var s: seq[string]
  for spec in CommandLineCommandTable:
    if spec.takesFilePath:
      s.add(spec.name)
  s

# Set options — derived from the canonical SetOptionTable so the completion
# popup, the help text, and the :set parser all share the same source of
# truth. Bool toggles map both positive and negative names to the same
# combined description ("Show/hide line numbers"); value options append the
# inline example (e.g., "tabstop=4") so users see the value syntax.
#
# `spec.description` is a structured `Description` (text + inline-code
# segments). The completion popup paints descriptions to the terminal
# verbatim, so render via `toPlainText` to drop the code-span markers
# that `help_markdown.nim` uses for the howtouse.md tables.
const SetOptions*: Table[string, string] = block:
  var t: Table[string, string]
  for spec in SetOptionTable:
    let desc = toPlainText(spec.description)
    case spec.kind
    of sokBool:
      t[spec.longName] = desc
      t["no" & spec.longName] = desc
    of sokInt:
      t[spec.longName] =
        desc & " (e.g., " & spec.longName & "=" & $spec.intExample & ")"
    of sokFloat:
      t[spec.longName] =
        desc & " (e.g., " & spec.longName & "=" & $spec.floatExample & ")"
  t

# Command collection

proc collectCommands*(parser: CommandLineParser): seq[CommandCompletionEntry] =
  ## Collect all available commands from the parser's aliases
  result = @[]
  var seenCommands: seq[string] = @[]

  for alias in parser.aliases.keys:
    if alias notin seenCommands:
      seenCommands.add(alias)
      let desc =
        if alias in parser.aliasDescriptions:
          parser.aliasDescriptions[alias]
        elif alias in CommandDescriptions:
          CommandDescriptions[alias]
        else:
          "User alias"
      result.add(
        CommandCompletionEntry(command: alias, description: desc, matchScore: 0)
      )

  # Add shell commands
  for name, entry in parser.shellCommands.pairs:
    if name notin seenCommands:
      seenCommands.add(name)
      let desc =
        if entry.description.len > 0:
          entry.description
        else:
          "Shell: " & entry.command
      result.add(
        CommandCompletionEntry(command: name, description: desc, matchScore: 0)
      )

  # Sort alphabetically
  result.sort do(a, b: CommandCompletionEntry) -> int:
    cmp(a.command, b.command)

proc extractCommandPrefix*(commandText: string): string =
  ## Extract the command prefix from commandText (after ":")
  ## Example: ":wq" -> "wq", ":set num" -> "set"
  if commandText.len <= 1:
    return ""

  # Remove the leading ":"
  result = commandText[1 ..^ 1]

  # If there's a space, return only the command part
  let spacePos = result.find(' ')
  if spacePos >= 0:
    result = result[0 ..< spacePos]

proc parseCommandLine*(commandText: string): tuple[cmd: string, arg: string] =
  ## Parse command text into command and argument parts
  ## Example: ":e foo" -> ("e", "foo"), ":set number" -> ("set", "number")
  if commandText.len <= 1:
    return ("", "")

  let text = commandText[1 ..^ 1] # Remove ":"
  let spacePos = text.find(' ')
  if spacePos < 0:
    return (text, "")

  let cmd = text[0 ..< spacePos]
  let arg = text[spacePos + 1 ..^ 1].strip()
  return (cmd, arg)

proc collectFilePaths*(basePath: string, prefix: string): seq[CommandCompletionEntry] =
  ## Collect file and directory paths for completion
  result = @[]

  # Determine the directory to list and the filter prefix
  var searchDir: string
  var filterPrefix: string

  if prefix.len == 0:
    searchDir =
      if basePath.len > 0:
        basePath
      else:
        getCurrentDir()
    filterPrefix = ""
  elif prefix.startsWith("/") or prefix.startsWith("~"):
    # Absolute path or home-relative path
    let expandedPrefix =
      if prefix.startsWith("~"):
        expandTilde(prefix)
      else:
        prefix
    # Only enter directory if prefix ends with /
    if prefix.endsWith("/") and dirExists(expandedPrefix):
      searchDir = expandedPrefix
      filterPrefix = ""
    else:
      searchDir = parentDir(expandedPrefix)
      filterPrefix = extractFilename(expandedPrefix)
  else:
    # Relative path
    let base =
      if basePath.len > 0:
        basePath
      else:
        getCurrentDir()
    let fullPath = base / prefix
    # Only enter directory if prefix ends with /
    if prefix.endsWith("/") and dirExists(fullPath):
      searchDir = fullPath
      filterPrefix = ""
    else:
      # Derive the directory to search from the prefix itself, not from
      # `parentDir(base / prefix)`: `base / "."` normalizes to `base`, so the
      # latter would ascend above `base` for dot prefixes (e.g. "."). Joining
      # `parentDir(prefix)` onto `base` keeps the search inside `base`.
      searchDir = base / parentDir(prefix)
      filterPrefix = extractFilename(prefix)

  if not dirExists(searchDir):
    return @[]

  try:
    for kind, path in walkDir(searchDir):
      let filename = extractFilename(path)
      # Skip hidden files unless prefix starts with .
      if filename.startsWith(".") and not filterPrefix.startsWith("."):
        continue

      if filterPrefix.len == 0 or
          filename.toLowerAscii.startsWith(filterPrefix.toLowerAscii):
        let displayName =
          if kind == pcDir:
            filename & "/"
          else:
            filename
        let desc = if kind == pcDir: "Directory" else: "File"
        result.add(
          CommandCompletionEntry(
            command: displayName,
            description: desc,
            matchScore: if kind == pcDir: 100 else: 50, # Prefer directories
          )
        )

    # Sort: directories first, then alphabetically
    result.sort do(a, b: CommandCompletionEntry) -> int:
      if a.command.endsWith("/") and not b.command.endsWith("/"):
        -1
      elif not a.command.endsWith("/") and b.command.endsWith("/"):
        1
      else:
        cmp(a.command.toLowerAscii, b.command.toLowerAscii)
  except OSError:
    discard

proc collectSetOptions*(prefix: string): seq[CommandCompletionEntry] =
  ## Collect :set options for completion
  result = @[]

  for option, desc in SetOptions:
    if prefix.len == 0 or fuzzyMatch(prefix, option):
      let score =
        if prefix.len > 0:
          matchScore(prefix, option)
        else:
          0
      result.add(
        CommandCompletionEntry(command: option, description: desc, matchScore: score)
      )

  # Sort by score (descending) then alphabetically
  result.sort do(a, b: CommandCompletionEntry) -> int:
    if a.matchScore != b.matchScore:
      b.matchScore - a.matchScore
    else:
      cmp(a.command, b.command)

# Completion menu operations

proc newCommandCompletionManager*(): CommandCompletionManager =
  ## Create a new command completion manager
  CommandCompletionManager(
    state: ccsIdle,
    mode: cmCommand,
    menu: CommandCompletionMenu(
      entries: @[],
      selectedIndex: -1, # -1 = no selection
      scrollOffset: 0,
      maxVisible: DefaultMaxVisible,
      prefix: "",
    ),
    allCommands: @[],
    baseCommand: "",
  )

proc filterAndSortEntries*(
    mgr: CommandCompletionManager, prefix: string
): seq[CommandCompletionEntry] =
  ## Filter commands by prefix and sort by match score
  result = @[]

  if prefix.len == 0:
    # Show all commands sorted alphabetically
    return mgr.allCommands

  # Filter and score
  for entry in mgr.allCommands:
    let score = matchScore(prefix, entry.command)
    if score > 0:
      var newEntry = entry
      newEntry.matchScore = score
      result.add(newEntry)

  # Sort by score (descending)
  result.sort do(a, b: CommandCompletionEntry) -> int:
    b.matchScore - a.matchScore

proc updateFilter*(mgr: CommandCompletionManager, prefix: string) =
  ## Update the completion filter with new prefix
  mgr.menu.prefix = prefix
  mgr.menu.entries = mgr.filterAndSortEntries(prefix)
  mgr.menu.selectedIndex = -1 # Reset to no selection
  mgr.menu.scrollOffset = 0
  # Cancel completion if no matches
  if mgr.menu.entries.len == 0:
    mgr.state = ccsIdle

proc triggerCompletion*(
    mgr: CommandCompletionManager, parser: CommandLineParser, commandText: string
) =
  ## Trigger completion for command mode (command names only)
  let prefix = extractCommandPrefix(commandText)

  # Collect commands if not already done
  if mgr.allCommands.len == 0:
    mgr.allCommands = collectCommands(parser)

  mgr.mode = cmCommand
  mgr.baseCommand = ""
  mgr.argStartX = 0 # Command completion popup starts at column 0

  # Filter entries
  mgr.updateFilter(prefix)

  # Only show if we have entries
  if mgr.menu.entries.len > 0:
    mgr.state = ccsActive
  else:
    mgr.state = ccsIdle

proc triggerArgumentCompletion*(
    mgr: CommandCompletionManager, commandText: string, basePath: string = ""
) =
  ## Trigger completion for command arguments (files, options, etc.)
  let (cmd, arg) = parseCommandLine(commandText)

  mgr.baseCommand = cmd

  # Base position: 1 for ":" + command length + 1 for space
  let baseArgX = 1 + cmd.runeLen + 1

  # Determine completion mode based on command
  if cmd in ["set", "se"]:
    mgr.mode = cmSetOption
    mgr.menu.entries = collectSetOptions(arg)
    mgr.argStartX = baseArgX
    mgr.originalDirPrefix = ""
  elif cmd in FilePathCommands:
    mgr.mode = cmFilePath
    mgr.menu.entries = collectFilePaths(basePath, arg)
    # For file paths, popup appears after directory prefix
    # Save original directory prefix for use in applyCompletion
    mgr.originalDirPrefix =
      if arg.contains("/"):
        arg[0 .. arg.rfind("/")] # Include the /
      else:
        ""
    mgr.argStartX = baseArgX + mgr.originalDirPrefix.runeLen
  else:
    # Unknown command, no argument completion
    mgr.state = ccsIdle
    return

  mgr.menu.prefix = arg
  mgr.menu.selectedIndex = -1 # No selection initially
  mgr.menu.scrollOffset = 0

  if mgr.menu.entries.len > 0:
    mgr.state = ccsActive
  else:
    mgr.state = ccsIdle

proc cancelCompletion*(mgr: CommandCompletionManager) =
  ## Cancel/close the completion popup
  mgr.state = ccsIdle
  mgr.mode = cmCommand
  mgr.menu.entries = @[]
  mgr.menu.selectedIndex = -1
  mgr.menu.scrollOffset = 0
  mgr.menu.prefix = ""
  mgr.baseCommand = ""
  mgr.originalDirPrefix = ""

proc selectNext*(mgr: CommandCompletionManager) =
  ## Select the next completion item
  ## Cycles: -1 → 0 → 1 → ... → n-1 → -1
  if mgr.menu.entries.len == 0:
    return

  if mgr.menu.selectedIndex < 0:
    # No selection → first item
    mgr.menu.selectedIndex = 0
  elif mgr.menu.selectedIndex >= mgr.menu.entries.len - 1:
    # Last item → no selection
    mgr.menu.selectedIndex = -1
  else:
    inc mgr.menu.selectedIndex

  # Adjust scroll offset if needed
  if mgr.menu.selectedIndex >= 0:
    if mgr.menu.selectedIndex >= mgr.menu.scrollOffset + mgr.menu.maxVisible:
      mgr.menu.scrollOffset = mgr.menu.selectedIndex - mgr.menu.maxVisible + 1
    elif mgr.menu.selectedIndex < mgr.menu.scrollOffset:
      mgr.menu.scrollOffset = mgr.menu.selectedIndex

proc selectPrevious*(mgr: CommandCompletionManager) =
  ## Select the previous completion item
  ## Cycles: -1 → n-1 → n-2 → ... → 0 → -1
  if mgr.menu.entries.len == 0:
    return

  if mgr.menu.selectedIndex < 0:
    # No selection → last item
    mgr.menu.selectedIndex = mgr.menu.entries.len - 1
  elif mgr.menu.selectedIndex == 0:
    # First item → no selection
    mgr.menu.selectedIndex = -1
  else:
    dec mgr.menu.selectedIndex

  # Adjust scroll offset if needed
  if mgr.menu.selectedIndex >= 0:
    if mgr.menu.selectedIndex < mgr.menu.scrollOffset:
      mgr.menu.scrollOffset = mgr.menu.selectedIndex
    elif mgr.menu.selectedIndex >= mgr.menu.scrollOffset + mgr.menu.maxVisible:
      mgr.menu.scrollOffset = mgr.menu.selectedIndex - mgr.menu.maxVisible + 1

proc getSelectedCommand*(mgr: CommandCompletionManager): string =
  ## Get the currently selected command
  if mgr.menu.entries.len == 0 or mgr.menu.selectedIndex < 0 or
      mgr.menu.selectedIndex >= mgr.menu.entries.len:
    return ""
  return mgr.menu.entries[mgr.menu.selectedIndex].command

proc isActive*(mgr: CommandCompletionManager): bool =
  ## Check if completion popup is active
  mgr.state == ccsActive

# Popup rendering

type CommandPopupPosition* = object
  x*, y*: int
  width*, height*: int

# Styles are derived from the current theme on each call so that theme changes
# (and the theme being loaded after this module is initialized) are reflected.
proc cmdPopupNormalStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindow)

proc cmdPopupSelectedStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWinCurrentLine)

proc cmdPopupBorderStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindowBorder)

proc cmdPopupDescNormalStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindowDetail)

proc cmdPopupDescSelectedStyle*(): Style =
  ## Description text on the selected row: detail foreground over the
  ## current-line background.
  Style(
    fg: getThemeStyle(EditorColorPairIndex.popupWindowDetail).fg,
    bg: getThemeStyle(EditorColorPairIndex.popupWinCurrentLine).bg,
    modifiers: {},
  )

proc calculateMaxCommandWidth*(entries: seq[CommandCompletionEntry]): int =
  ## Calculate the maximum command width in the entries
  result = 0
  for entry in entries:
    let width = entry.command.runeLen
    if width > result:
      result = width

proc calculateMaxDescriptionWidth*(entries: seq[CommandCompletionEntry]): int =
  ## Calculate the maximum description width in the entries
  result = 0
  for entry in entries:
    let width = entry.description.runeLen
    if width > result:
      result = width

proc calculateCommandPopupPosition*(
    commandCursor: int,
    termWidth, termHeight: int,
    entries: seq[CommandCompletionEntry],
    maxVisible: int = DefaultMaxVisible,
    argStartPos: int = 0,
    bottomAreaRows: int = 1,
): CommandPopupPosition =
  ## Calculate popup position and size for command completion
  ## Popup appears above the whole reserved bottom area
  ## argStartPos: position where argument starts (for argument completion)
  ## bottomAreaRows: total rows reserved at the bottom — the (possibly
  ## wrapped) command-line rows plus the status line pushed above them
  ## when the area is grown
  let visibleItems = min(entries.len, maxVisible)
  let popupHeight = visibleItems + 2 # +2 for border

  # Calculate width based on longest command + description
  let maxCmdWidth = calculateMaxCommandWidth(entries)
  let maxDescWidth = calculateMaxDescriptionWidth(entries)

  # Content width: command + gap + description (if descriptions exist)
  let contentWidth =
    if maxDescWidth > 0:
      let fullWidth = maxCmdWidth + DescriptionGap + maxDescWidth + PopupPadding
      max(MinPopupWidth, min(fullWidth, MaxPopupWidth))
    else:
      max(MinPopupWidth, min(maxCmdWidth + PopupPadding, MaxPopupWidth))
  let popupWidth = contentWidth + 2 # +2 for border

  # Position: above the reserved bottom area (its top row is at
  # termHeight - bottomAreaRows)
  let y = termHeight - bottomAreaRows - popupHeight

  # X position: start from argument position for argument completion, or 0 for command
  var x = argStartPos

  # Adjust X if popup would extend past right edge
  if x + popupWidth > termWidth:
    x = max(0, termWidth - popupWidth)

  CommandPopupPosition(x: x, y: max(0, y), width: popupWidth, height: popupHeight)

proc renderCommandCompletionPopup*(
    termBuffer: var Buffer,
    menu: CommandCompletionMenu,
    pos: CommandPopupPosition,
    showBorder: bool = true,
) =
  ## Render command completion popup to terminal buffer
  if menu.entries.len == 0:
    return

  let visibleItems = min(menu.entries.len, menu.maxVisible)

  # Calculate content area (inside border)
  let contentX =
    if showBorder:
      pos.x + 1
    else:
      pos.x
  let contentY =
    if showBorder:
      pos.y + 1
    else:
      pos.y
  let contentWidth =
    if showBorder:
      pos.width - 2
    else:
      pos.width
  let contentHeight = visibleItems

  # Draw border if enabled
  if showBorder:
    drawBorder(termBuffer, pos.x, pos.y, pos.width, pos.height, cmdPopupBorderStyle())

  # Content (command + aligned description columns)
  let maxCmdWidth = calculateMaxCommandWidth(menu.entries)
  let contentLimit = contentX + contentWidth
  for i in 0 ..< contentHeight:
    let y = contentY + i
    if y >= 0 and y < termBuffer.area.height:
      let entryIdx = menu.scrollOffset + i
      if entryIdx < menu.entries.len:
        let entry = menu.entries[entryIdx]
        let isSelected = entryIdx == menu.selectedIndex
        let cmdStyle =
          if isSelected:
            cmdPopupSelectedStyle()
          else:
            cmdPopupNormalStyle()
        let descStyle =
          if isSelected:
            cmdPopupDescSelectedStyle()
          else:
            cmdPopupDescNormalStyle()

        # Truncate command if needed
        var displayCmd = entry.command
        let cmdDisplayWidth = min(maxCmdWidth, contentWidth - DescriptionGap - 1)
        if displayCmd.runeLen > cmdDisplayWidth:
          displayCmd = $displayCmd.toRunes[0 ..< cmdDisplayWidth - 1] & "…"

        # Draw command
        var x =
          drawClippedRunes(termBuffer, contentX, y, contentLimit, displayCmd, cmdStyle)

        # Pad command to max width for alignment
        let cmdEndX = contentX + min(maxCmdWidth, cmdDisplayWidth) + DescriptionGap
        x = fillCells(termBuffer, x, y, min(cmdEndX, contentLimit), cmdStyle)

        # Draw description if available
        if entry.description.len > 0:
          let remainingWidth = contentLimit - x
          var displayDesc = entry.description
          if displayDesc.runeLen > remainingWidth:
            displayDesc = $displayDesc.toRunes[0 ..< remainingWidth - 1] & "…"

          x = drawClippedRunes(termBuffer, x, y, contentLimit, displayDesc, descStyle)

        # Fill remaining space with background
        x = fillCells(termBuffer, x, y, contentLimit, cmdStyle)
