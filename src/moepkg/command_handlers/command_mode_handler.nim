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

## Command mode event handler
##
## This module handles the command-line overlay mode (`:` commands).
## Extracted from handler.nim to reduce file size.

import std/[options, strutils]

import pkg/chronos

import
  ../[
    editor, key_bindings, buffer, types, command_line, command_completion,
    unicode_utils, key_router, prompt_line,
  ]
import editor_ops, result_processor
from command_handler import resolveExRange
export editor_ops

type SubstituteMatch* = tuple[line: int, cols: ColumnRange]
  ## A match `:s` would replace: its line and the columns on it.

proc findFirstSubstituteMatch*(
    lines: seq[string] | TextBuffer,
    pattern: string,
    ignoreCase: bool,
    match: SearchMatch,
    firstLine: int = 0,
    lastLine: int = high(int),
): Option[SubstituteMatch] =
  ## The first match `:s` would replace in lines `firstLine .. lastLine`.
  ## A pattern that does not compile has none, and no line is scanned for it.
  if pattern.len == 0 or invalidRegex(pattern, ignoreCase, match).len > 0:
    return none(SubstituteMatch)
  for lineIdx in max(firstLine, 0) .. min(lastLine, lines.len - 1):
    let cols = lines[lineIdx].firstSubstituteMatch(pattern, ignoreCase, match)
    if cols.isSome:
      return some((line: lineIdx, cols: cols.get))
  return none(SubstituteMatch)

proc showSubstituteMatch*(e: Editor, found: Option[SubstituteMatch]) =
  ## Put the cursor on `found`, a match in the pre-preview text, where the
  ## preview took it, and scroll from the pre-preview view (incsearch-like).
  ## With none, restore both.
  template preview(): untyped =
    e.state.ui.substitutePreview

  if found.isSome:
    e.cursor =
      e.inPreview(BufferPosition(line: found.get.line, column: found.get.cols.startCol))
    e.showFromView(e.inPreview(preview.originalView), e.cursor)
  else:
    e.cursor = e.inPreview(preview.originalCursor)
    e.activeWindow.viewport.restoreViewState(e.inPreview(preview.originalView))

proc updateSubstitutePreviewIfNeeded(e: Editor) =
  ## Update or cancel the live substitute preview based on the current command
  ## text. Call after any edit of the line.
  ##
  ## Behavior:
  ## - Pattern only (e.g. ":%s/foo"): jump cursor to first match (incsearch-like)
  ## - Pattern + replacement (e.g. ":%s/foo/bar"): also preview the replacement
  ##   in the buffer when config.highlight.replaceText is enabled.
  e.state.input.line.wordAt = none(BufferPosition)
  let commandText = normalizeSubstituteLongForm(e.state.commandLine)
  if commandText.contains("s/"):
    let parsed = parseSubstituteCommand(commandText)
    let target = e.commandLineParser.typedSubstitutePattern(parsed)
    if target.pattern.len > 0:
      if not e.state.ui.substitutePreview.isActive:
        e.startSubstitutePreview()
        if not e.state.ui.substitutePreview.isActive:
          return
      let flags =
        e.commandLineParser.substituteFlags(target.pattern, parsed.flags, target.match)
      # What would change is all a preview shows, so a :s that changes nothing
      # previews nothing.
      let previews =
        parsed.hasReplacement and e.config.highlight.replaceText and
        flags.refusal.len == 0 and not flags.countOnly
      let key = SubstitutePreviewKey(
        range: parsed.range,
        pattern: target.pattern,
        replacement: parsed.replacement,
        global: flags.global,
        ignoreCase: flags.ignoreCase,
        match: target.match,
      )
      # The closing `/`, or a flag that changes nothing, leaves buffer, cursor
      # and view alone.
      if previews and e.previewShows(key):
        e.state.input.line.wordAt = some(e.state.ui.substitutePreview.originalCursor)
        return
      # Range, first match and cursor go by the pre-preview text, which a
      # broken line would move.
      e.restoreFromPreview()
      # The lines `:s` would run on, from where the cursor was before the
      # preview moved it. A range it would refuse previews nothing.
      let (firstLine, lastLine) = e.activeBuffer
        .resolveExRange(parsed.range, e.state.ui.substitutePreview.originalCursor.line)
        .valueOr((0, -1))
      # Vim's cursor stays put unless 'incsearch' takes it to the end of the
      # match, and comes back once the pattern is followed by more. 'incsearch'
      # goes by the options, as the highlight does: it reads no flags.
      let ignoreCase =
        e.commandLineParser.optionsIgnoreCaseOf(target.pattern, target.match)
      let found =
        if e.state.input.search.incsearch:
          findFirstSubstituteMatch(
            e.activeBuffer, target.pattern, ignoreCase, target.match, firstLine,
            lastLine,
          )
        else:
          none(SubstituteMatch)
      if previews:
        e.updateSubstitutePreview(
          target.pattern, parsed.replacement, flags, target.match, firstLine, lastLine
        )
        e.notePreviewShows(key)
      # Without 'incsearch' or a match, cursor and view stay with their text,
      # moving down with lines broken above.
      e.showSubstituteMatch(found)
      e.state.input.line.wordAt = some(
        if found.isSome and not parsed.hasReplacement:
          BufferPosition(line: found.get.line, column: found.get.cols.endCol)
        else:
          e.state.ui.substitutePreview.originalCursor
      )
    elif e.state.ui.substitutePreview.isActive:
      e.cancelSubstitutePreview()
  elif e.state.ui.substitutePreview.isActive:
    # Ctrl-U and Ctrl-W take the `s/` as well.
    e.cancelSubstitutePreview()

proc insertPastedTextInCommand*(e: Editor, text: string) =
  ## Insert a paste's first line at the cursor of the command line.
  if e.state.input.line.insertPasted(text):
    e.state.commandCompletionManager.cancelCompletion()
    e.updateSubstitutePreviewIfNeeded()

proc cancelCommandLine*(e: Editor) =
  ## Leave the command line without running it. Unlike Vim, the line does not
  ## go into the history, since `@:` runs the newest entry.
  e.state.commandCompletionManager.cancelCompletion()
  # Cancel substitute preview and restore original content
  e.cancelSubstitutePreview()
  # Exit overlay and restore base mode
  e.state.exitOverlay()
  e.setMode(e.state.mode) # Sync window mode

proc updateCompletionAfterEdit(e: Editor) =
  ## Follow an erase in the line with the completion menu and the substitute
  ## preview.
  let mgr = e.state.commandCompletionManager
  if ' ' in e.state.input.line.text:
    # Argument mode
    mgr.triggerArgumentCompletion(e.state.commandLine)
  elif mgr.isActive():
    if e.state.input.line.text.len == 0 or mgr.mode != cmCommand:
      # All of it went, or the argument the completions were for.
      mgr.cancelCompletion()
    else:
      mgr.updateFilter(extractCommandPrefix(e.state.commandLine))
  e.updateSubstitutePreviewIfNeeded()

proc updateCompletionAfterTyping(e: Editor, typed: string) =
  ## Follow a typed character with the completion menu and the substitute
  ## preview.
  let mgr = e.state.commandCompletionManager
  if typed == " ":
    # Space is a delimiter - trigger argument completion if applicable
    mgr.cancelCompletion()
    mgr.triggerArgumentCompletion(e.state.commandLine)
  elif ' ' in e.state.input.line.text:
    # In argument mode - always update argument completion
    mgr.triggerArgumentCompletion(e.state.commandLine)
  elif mgr.isActive():
    mgr.updateFilter(extractCommandPrefix(e.state.commandLine))
  else:
    # Auto-trigger command completion on first character
    mgr.triggerCompletion(e.commandLineParser, e.state.commandLine)
  e.updateSubstitutePreviewIfNeeded()

proc runCommandLine(e: Editor): ReplayOutcome =
  ## Run the command line, or leave it when there is nothing after the `:`.
  if e.state.input.line.text.len > 0:
    # Full-lifecycle dispatch (pre-teardown, side effects, post-teardown)
    # is centralised in executeCommandOverlay so the Command overlay Enter
    # path and hrExecCommand (@:) share a single entry point.
    return e.executeCommandOverlay(e.state.commandLine)
  e.cancelCommandLine()
  roContinue

proc applyCompletion(e: Editor): bool =
  ## Put the selected completion in the line. Returns whether it was a
  ## directory, whose contents complete next.
  let mgr = e.state.commandCompletionManager
  let selected = mgr.getSelectedCommand()
  if selected.len == 0:
    return false
  template line(): untyped =
    e.state.input.line

  case mgr.mode
  of cmCommand:
    line.text = selected
  of cmFilePath:
    # Use original directory prefix (saved when completion started)
    line.text = mgr.baseCommand & " " & mgr.originalDirPrefix & selected
    result = selected.endsWith("/")
  of cmSetOption:
    # Replace only the argument part
    line.text = parseCommandLine(e.state.commandLine).cmd & " " & selected
  line.cursor = line.text.charLen

proc selectCompletion(e: Editor, next: bool) =
  ## Tab or Ctrl-N, Shift-Tab or Ctrl-P: the next or the previous completion,
  ## put in the line. Going round to none puts back what was typed, as Vim's
  ## wildmenu does.
  let mgr = e.state.commandCompletionManager
  template line(): untyped =
    e.state.input.line

  if mgr.menu.selectedIndex < 0:
    mgr.typedLine = (line.text, line.cursor)
  if next:
    mgr.selectNext()
  else:
    mgr.selectPrevious()
  if mgr.menu.selectedIndex >= 0:
    discard e.applyCompletion()
  else:
    (line.text, line.cursor) = mgr.typedLine

proc editCommandLine(e: Editor, keyCombo: KeyCombo) =
  ## Edit the line with `keyCombo`, and have the completions and the
  ## substitute preview follow.
  let mgr = e.state.commandCompletionManager
  case e.state.editPrompt(e.activeBuffer, keyCombo, e.state.input.commandState.history)
  of leNone, leStill:
    discard
  of leBeep:
    e.state.beep()
  of leEmptyErase:
    e.cancelCommandLine()
  of leMoved:
    # Home, End, Ctrl-B and Ctrl-E too with the cursor already there, so the
    # next Enter runs the line.
    mgr.cancelCompletion()
  of leTyped:
    e.updateCompletionAfterTyping(keyCombo.char)
  of leErased:
    e.updateCompletionAfterEdit()
  of leRecalled, lePasted:
    mgr.cancelCompletion()
    e.updateSubstitutePreviewIfNeeded()

proc handleCommandModeKeyCombo*(e: Editor, keyCombo: KeyCombo): ReplayOutcome =
  ## Run `keyCombo` on the command line. Its mappings (`cmap`) have already
  ## had the key: a mapping's keys run here as keys of their own, so the ones
  ## after an Enter that ends the command line reach the mode it returns to.
  let key = e.state.input.line.takeKey(keyCombo, e.state.keyTyped, e.state.interrupted)
  let mgr = e.state.commandCompletionManager
  case key
  of pkLeave:
    e.cancelCommandLine()
    return roContinue
  of pkEnter, pkRun:
    # An Esc a mapping put in runs the line as it stands, the completion Tab
    # put in included. Enter on a selected completion confirms it first.
    if key == pkEnter and mgr.isActive() and mgr.menu.selectedIndex >= 0:
      # Check if selected item is a directory (for file path mode)
      let isDir = mgr.mode == cmFilePath and mgr.getSelectedCommand().endsWith("/")
      let isFile = mgr.mode == cmFilePath and not isDir
      # A directory is all :cd takes, so it runs rather than opens.
      let isWholeArgument = isFile or (isDir and mgr.baseCommand.completesDirectories)
      # Check if it's an action that should execute immediately
      let shouldExecuteNow =
        isWholeArgument or mgr.mode == cmSetOption or (
          mgr.mode == cmCommand and
          e.commandLineParser.isNoArgumentAction(mgr.getSelectedCommand())
        )
      mgr.cancelCompletion()
      # If directory was confirmed, re-trigger completion for its contents
      if isDir and not isWholeArgument:
        mgr.triggerArgumentCompletion(e.state.commandLine)
        return roContinue
      # If not a no-argument command, wait for more input
      if not shouldExecuteNow:
        return roContinue
      # Otherwise, fall through to execute the command immediately
    return e.runCommandLine()
  of pkArgument:
    e.editCommandLine(keyCombo)
    return roContinue
  of pkOther:
    discard

  # Tab completes; Ctrl-N and Ctrl-P go through the completions while they
  # show, as Vim's do through its matches, and through the history otherwise.
  if keyCombo.isSpecial and keyCombo.special in {skTab, skBackTab}:
    let next = kmShift notin keyCombo.modifiers and keyCombo.special == skTab
    if mgr.isActive():
      e.selectCompletion(next)
    elif next:
      if ' ' in e.state.input.line.text:
        mgr.triggerArgumentCompletion(e.state.commandLine)
      else:
        mgr.triggerCompletion(e.commandLineParser, e.state.commandLine)
    return roContinue
  if mgr.isActive() and (keyCombo.isCtrl('n') or keyCombo.isCtrl('p')):
    e.selectCompletion(keyCombo.isCtrl('n'))
    return roContinue
  # PageUp and PageDown page the completions while one is selected, as Vim's
  # wild menu does; with none selected they go through the history.
  if mgr.isActive() and mgr.menu.selectedIndex >= 0 and keyCombo.isSpecial and
      keyCombo.special in {skPageUp, skPageDown}:
    mgr.pageSelection(keyCombo.special == skPageDown)
    discard e.applyCompletion()
    return roContinue

  e.editCommandLine(keyCombo)
  roContinue
