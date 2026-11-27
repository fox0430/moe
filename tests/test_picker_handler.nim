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

import std/[options, os, sequtils, strutils, unittest]

import pkg/results

import ../src/moepkg/celina_backend
import
  ../src/moepkg/[
    editor, types, config, keybind_config, registers, editor_frame, color, handler,
    frontend_input, key_bindings, theme,
  ]
import ../src/moepkg/command_handlers/[result_processor, handler_result]
from vim_like_test_helper import keysOf

let dir = getTempDir() / "moe_test_picker_handler"
let files = [dir / "alpha.txt", dir / "beta.txt", dir / "gamma_alpha.txt"]

proc newPickerEditor(): Editor =
  ## An editor with the files open, the first one shown.
  createDir(dir)
  for f in files:
    writeFile(f, f.extractFilename & "\n")
  let config = newEditorConfig()
  config.theme.kind = tkDefault
  result = newEditor(config)
  for i in countdown(files.high, 0):
    check result.executeCommandOverlay(":e " & files[i]) == roContinue
  check result.activeBuffer.filePath == some(files[0])

proc typeKeys(e: Editor, spec: string) =
  ## Type `spec` with no frame between the keys, `<Name>` as one key.
  for k in keysOf(spec):
    check e.handleKeyCombo(k)

proc replay(e: Editor, spec: string): HandlerResult =
  ## Run `spec` as a register would.
  e.playbackKeyCombos(keysOf(spec))

proc resumeNow(e: Editor): bool =
  ## Run `:picker resume`'s result whatever is open.
  e.processResult(
    HandlerResult(kind: hrPickerEnter, pickerSpec: PickerSpec(resume: true)),
    e.activeBuffer,
  )

proc shownFile(e: Editor): string =
  e.activeBuffer.filePath.get("").extractFilename

proc keys(s: PickerSession): seq[string] =
  for item in s.items:
    result.add item.key

suite "picker: opening and closing":
  teardown:
    removeDir(dir)

  test ":picker buffers lists the buffers":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>")
    check e.state.isPickerOverlay
    check e.state.picker.title == "Buffers"
    for f in files:
      check f in e.state.picker.keys
    check e.state.input.line.text == ""

  test "A typed Esc closes it and leaves the window as it was":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>bet<Esc>")
    check not e.state.isPickerOverlay
    check e.state.picker.isNil
    check e.shownFile == "alpha.txt"
    check e.state.lastPicker.query == "bet"
    check e.activeWindow.mode == EditorMode.Normal

  test "Ctrl-C closes it":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter><C-c>")
    check not e.state.isPickerOverlay
    check e.shownFile == "alpha.txt"

  test "Erasing on an empty query leaves it open":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter><Backspace>")
    check e.state.isPickerOverlay

  test "An unknown source is an error, with no picker":
    let e = newPickerEditor()
    e.typeKeys(":picker filez<Enter>")
    check not e.state.isPickerOverlay
    check e.state.statusMessage == "Unknown picker source: filez"

  test "The query after `--` is the one it starts with":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers -- beta<Enter>")
    check e.state.input.line.text == "beta"
    e.typeKeys("<Enter>")
    check e.shownFile == "beta.txt"

  test "A bang run into the source still opens it with its query":
    let e = newPickerEditor()
    e.typeKeys(":picker!buffers -- beta<Enter>")
    check e.state.picker.title == "Buffers"
    check e.state.input.line.text == "beta"

  test "Closed, it lets the window go":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter><Esc>")
    check e.state.lastPicker.origin.isNil

  test "A mapping opens it with its arguments, out of the : history":
    let e = newPickerEditor()
    check e.keyBindingRegistry.addRuntimeMappingExpanded(
      EditorMode.Normal, "Space f", "picker", args = @["buffers", "--", "gamma"]
    ).len == 0
    # The history the editor loaded may hold `picker` lines already.
    let history = e.state.input.commandState.history
    e.typeKeys("<Space>f")
    check e.state.isPickerOverlay
    check e.state.input.line.text == "gamma"
    check e.state.input.commandState.history == history
    e.typeKeys("<Enter>")
    check e.shownFile == "gamma_alpha.txt"

  test "A mapping to an unknown source is refused when it is read":
    let e = newPickerEditor()
    check e.keyBindingRegistry.addRuntimeMappingExpanded(
      EditorMode.Normal, "Space f", "picker filez"
    ).len > 0

  test ":picker with no source lists the sources, which open their picker":
    let e = newPickerEditor()
    e.typeKeys(":picker<Enter>")
    check e.state.picker.title == "Pickers"
    check e.state.picker.keys == @["buffers", "oldfiles"]
    e.typeKeys("buf<Enter>")
    check e.state.isPickerOverlay
    check e.state.picker.title == "Buffers"

  test "A split of a source beeps and stays open":
    let e = newPickerEditor()
    e.typeKeys(":picker<Enter>buf")
    let beeps = e.state.beepCount
    e.typeKeys("<C-v>")
    check e.state.isPickerOverlay
    check e.state.picker.title == "Pickers"
    check e.state.beepCount > beeps
    check e.windowManager.windows.len == 1

  test "A source a host takes the picker of does not beep":
    let e = newPickerEditor()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrPickerEnter and r.pickerSpec.source == some(psBuffers)
    e.typeKeys(":picker<Enter>buf")
    require e.state.picker.title == "Pickers"
    let beeps = e.state.beepCount
    e.typeKeys("<Enter>")
    check e.state.beepCount == beeps
    let taken = e.takeHostResultRequest()
    require taken.isSome
    check taken.get.kind == hrPickerEnter
    check taken.get.pickerSpec.source == some(psBuffers)
    e.hostResultFilter = nil

suite "picker: opening an item":
  teardown:
    removeDir(dir)

  test "Keys typed ahead of the frame open the best match of what was typed":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta<Enter>")
    check not e.state.isPickerOverlay
    check e.shownFile == "beta.txt"

  test "A move typed ahead of the frame moves on the list of what was typed":
    let e = newPickerEditor()
    # alpha.txt ranks first for `alpha`, gamma_alpha.txt second.
    e.typeKeys(":picker buffers<Enter>alpha<C-n><Enter>")
    check e.shownFile == "gamma_alpha.txt"

  test "Up and Down move through the list":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>alpha<Down><Down><Up><Down><Enter>")
    check e.shownFile == "gamma_alpha.txt"

  test "Enter with nothing matched beeps and stays open":
    let e = newPickerEditor()
    let beeps = e.state.beepCount
    e.typeKeys(":picker buffers<Enter>zzzz<Enter>")
    check e.state.isPickerOverlay
    check e.state.beepCount > beeps

  test "A register stops where nothing matched":
    let e = newPickerEditor()
    check e.replay(":picker buffers<Enter>zzzz<Enter>").kind == hrError
    check e.state.isPickerOverlay

  test "A register opens the best match, as typed keys do":
    let e = newPickerEditor()
    check e.replay(":picker buffers<Enter>beta<Enter>").kind == hrHandled
    check e.shownFile == "beta.txt"

  test "An Esc a register puts in opens the selected item":
    let e = newPickerEditor()
    check e.replay(":picker buffers<Enter>beta<Esc>").kind == hrHandled
    check not e.state.isPickerOverlay
    check e.shownFile == "beta.txt"

  test "Ctrl-V opens it in a vertical split, Ctrl-X in a split":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta<C-v>")
    check e.windowManager.windows.len == 2
    check e.shownFile == "beta.txt"
    e.typeKeys(":picker buffers<Enter>gamma<C-x>")
    check e.windowManager.windows.len == 3
    check e.shownFile == "gamma_alpha.txt"

  test "Another buffer is a jump, the one shown is not":
    let e = newPickerEditor()
    let jumps = e.state.jumpList.list.len
    e.typeKeys(":picker buffers<Enter>alpha.txt<Enter>")
    check e.shownFile == "alpha.txt"
    check e.state.jumpList.list.len == jumps
    e.typeKeys(":picker buffers<Enter>beta<Enter>")
    check e.state.jumpList.list.len == jumps + 1

  test "Opened from Insert's Ctrl-O, it goes back to Insert in what it opened":
    let e = newPickerEditor()
    e.typeKeys("i<C-o>:picker buffers<Enter>beta<Enter>")
    check not e.state.isPickerOverlay
    check e.shownFile == "beta.txt"
    check e.activeWindow.mode == EditorMode.Insert

  test "Closed from Insert's Ctrl-O, it goes back to Insert":
    let e = newPickerEditor()
    e.typeKeys("i<C-o>:picker buffers<Enter><Esc>")
    check not e.state.isPickerOverlay
    check e.shownFile == "alpha.txt"
    check e.activeWindow.mode == EditorMode.Insert

  test "The buffer opened joins the window's tabs":
    let e = newPickerEditor()
    e.typeKeys(":vnew<Enter>")
    let fresh = e.activeWindow
    e.typeKeys(":picker buffers<Enter>beta<Enter>")
    check e.activeWindow == fresh
    check e.activeBuffer.id in fresh.bufferIds

suite "picker: the query":
  teardown:
    removeDir(dir)

  test "Ctrl-Q puts the next key in, even one the picker takes":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>a<C-q><C-v>")
    check e.state.isPickerOverlay
    check e.state.input.line.text == "a\x16"
    check e.windowManager.windows.len == 1

  test "Ctrl-R puts a register in":
    let e = newPickerEditor()
    check e.state.registers.setRegister('a', "beta", isLine = false).isOk
    e.typeKeys(":picker buffers<Enter><C-r>a<Enter>")
    check e.shownFile == "beta.txt"

  test "What a register puts in after a key that runs is not a split":
    # The keys after the Ctrl-N go on as keys, a line's end and a Ctrl-X
    # covered by the picker's Ctrl-Q, as a Ctrl-V covers them at the `:` line.
    let e = newPickerEditor()
    check e.state.registers.setRegister('a', "\x0e\x18b\nc", isLine = false).isOk
    e.typeKeys(":picker buffers<Enter><C-r>a")
    check e.state.isPickerOverlay
    check e.state.input.line.text == "\x18b\rc"
    check e.windowManager.windows.len == 1

  test "A paste goes into the query":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>")
    check e.handlePaste("gamma")
    check e.state.input.line.text == "gamma"
    e.typeKeys("<Enter>")
    check e.shownFile == "gamma_alpha.txt"

  test "A typed query goes into the history, opened or not":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta<Enter>")
    e.typeKeys(":picker buffers<Enter>gam<Esc>")
    e.typeKeys(":picker buffers<Enter>alp<C-c>")
    check e.state.input.pickerHistory == @["alp", "gam", "beta"]

  test "An empty query does not go into the history":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter><Esc>")
    e.typeKeys(":picker buffers<Enter>x<Backspace><Enter>")
    check e.state.input.pickerHistory.len == 0

  test "A query only a register typed does not go into the history":
    let e = newPickerEditor()
    discard e.replay(":picker buffers<Enter>beta<Enter>")
    check e.state.input.pickerHistory.len == 0

  test "Enter typed after a mapping's query puts it in the history":
    let e = newPickerEditor()
    check e.keyBindingRegistry.addRuntimeMappingExpanded(
      EditorMode.Normal, "Space f", "picker buffers -- beta"
    ).len == 0
    e.typeKeys("<Space>f<Enter>")
    check e.state.input.pickerHistory == @["beta"]

  test "A mapping's query goes in even if a mapped key opens it":
    # `cnoremap <C-x> <CR>`, then a typed Ctrl-x: the picker waited for a
    # key, as the `:` line does, for input() reads it as getcmdline does.
    let e = newPickerEditor()
    check e.keyBindingRegistry.addRuntimeMappingExpanded(
      EditorMode.Normal, "Space f", "picker buffers -- beta"
    ).len == 0
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Command, "C-x", "Enter", true
    ).len == 0
    e.typeKeys("<Space>f<C-x>")
    check e.shownFile == "beta.txt"
    check e.state.input.pickerHistory == @["beta"]

  test "A query opened while a mapping holds keys does not go in":
    # `nmap V :picker buffers -- beta<CR>s` and `cnoremap sx <CR>`, then a
    # typed `x`: the picker never waited, as `s` was still to be read.
    let e = newPickerEditor()
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Normal, "V", ":picker Space buffers Space - - Space beta Enter s",
      false,
    ).len == 0
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Command, "s x", "Enter", true
    ).len == 0
    e.typeKeys("Vx")
    check e.shownFile == "beta.txt"
    check e.state.input.pickerHistory.len == 0

  test "Ctrl-Up recalls a query from the history":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta<Esc>")
    e.typeKeys(":picker buffers<Enter><C-Up>")
    check e.state.input.line.text == "beta"

suite "picker: resume":
  teardown:
    removeDir(dir)

  test "It goes back to the query and the selection as they were left":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>alpha<C-n><Esc>")
    e.typeKeys(":picker resume<Enter>")
    check e.state.isPickerOverlay
    check e.state.input.line.text == "alpha"
    e.typeKeys("<Enter>")
    check e.shownFile == "gamma_alpha.txt"

  test "It opens in the window it was resumed in":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta<Esc>")
    e.typeKeys(":vnew<Enter>")
    let fresh = e.activeWindow
    e.typeKeys(":picker resume<Enter><Enter>")
    check e.activeWindow == fresh
    check e.shownFile == "beta.txt"

  # No key reaches `:picker resume` with a picker open (the picker's mappings
  # run only keys, which must close it before a `:`), so these run it as a
  # command line would.
  test "Run on the one open, it keeps what was typed and its window":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>alp<Esc>")
    e.typeKeys(":picker resume<Enter>ha")
    check e.resumeNow()
    check e.state.isPickerOverlay
    check e.state.input.line.text == "alpha"
    check e.state.picker.origin == e.activeWindow
    e.typeKeys("<Enter>")
    check e.shownFile == "alpha.txt"

  test "Run on another, it takes that one back, closed first":
    let e = newPickerEditor()
    e.typeKeys(":picker<Enter><Esc>")
    e.typeKeys(":picker buffers<Enter>beta")
    let open = e.state.picker
    check e.resumeNow()
    check e.state.picker == open
    check e.state.lastPicker == open
    check e.state.input.line.text == "beta"

  test "With no picker to go back to, it beeps":
    let e = newPickerEditor()
    let beeps = e.state.beepCount
    e.typeKeys(":picker resume<Enter>")
    check not e.state.isPickerOverlay
    check e.state.statusMessage == "No picker to resume"
    check e.state.beepCount > beeps

suite "picker: oldfiles":
  teardown:
    removeDir(dir)

  test "The files the cursor positions were saved for, in the file's order":
    let e = newPickerEditor()
    let cache = dir / "cache"
    let hadCacheHome = existsEnv("XDG_CACHE_HOME")
    let cacheHome = getEnv("XDG_CACHE_HOME")
    putEnv("XDG_CACHE_HOME", cache)
    defer:
      if hadCacheHome:
        putEnv("XDG_CACHE_HOME", cacheHome)
      else:
        delEnv("XDG_CACHE_HOME")
    createDir(cache / "moe")
    writeFile(
      cache / "moe" / "cursor_positions.json",
      "{\"" & files[2] & "\": {\"line\": 0, \"column\": 0}, \"" & files[1] &
        "\": {\"line\": 0, \"column\": 0}}",
    )
    e.typeKeys(":picker oldfiles<Enter>")
    check e.state.picker.items.len == 2
    check e.state.picker.items[0].target.path == files[2]
    check e.state.picker.items[1].target.path == files[1]
    e.typeKeys("<C-n><Enter>")
    check e.shownFile == "beta.txt"

  test "None when the positions are not saved":
    let e = newPickerEditor()
    e.config.persist.cursorPosition = false
    e.typeKeys(":picker oldfiles<Enter>")
    check e.state.picker.items.len == 0
    check e.state.picker.message.len > 0

suite "picker: the screen":
  teardown:
    removeDir(dir)

  test "A box with the title, the query, the count and the matches marked":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta")
    var frame = newBuffer(80, 24)
    e.render(frame)
    var rows: seq[string]
    for y in 0 ..< 24:
      var row = ""
      for x in 0 ..< 80:
        row.add frame[x, y].symbol
      rows.add row
    let top = rows.find(rows.filterIt(" Buffers " in it)[0])
    check "> beta" in rows[top + 1]
    check "1/4" in rows[top + 1]
    check "├" in rows[top + 2]
    check "beta.txt" in rows[top + 3]
    check ".txt" notin rows[top + 4]
    # The cursor is at the end of the query.
    let row = e.state.screenCursor.y
    var line = ""
    for x in 0 ..< e.state.screenCursor.x:
      line.add frame[x, row].symbol
    check line.endsWith("> beta")
    # The `b` of the selected row is marked as a match.
    var marked = false
    for y in 0 ..< 24:
      for x in 0 ..< 80:
        if frame[x, y].style == getThemeStyle(EditorColorPairIndex.pickerMatchSel):
          marked = true
    check marked

  test "A match takes only the foreground, on the row's background":
    # After the editor, which sets the theme up.
    let e = newPickerEditor()
    let saved = themeColors
    var colors = saved
    colors[EditorColorPairIndex.pickerMatch].background =
      ThemeColor(rgb: Rgb(red: 255, green: 0, blue: 255))
    colors[EditorColorPairIndex.pickerMatchSel].background =
      ThemeColor(rgb: Rgb(red: 0, green: 255, blue: 255))
    setThemeColors(colors)
    defer:
      setThemeColors(saved)
    # `a` matches every buffer, the selected one too.
    e.typeKeys(":picker buffers<Enter>a")
    var frame = newBuffer(80, 24)
    e.render(frame)
    let
      match = getThemeStyle(EditorColorPairIndex.pickerMatch)
      matchSel = getThemeStyle(EditorColorPairIndex.pickerMatchSel)
      normal = getThemeStyle(EditorColorPairIndex.picker)
      current = getThemeStyle(EditorColorPairIndex.pickerSelection)
    var onRow, onSelected, matchBg = false
    for y in 0 ..< 24:
      for x in 0 ..< 80:
        let style = frame[x, y].style
        if style.bg == match.bg or style.bg == matchSel.bg:
          matchBg = true
        if style.fg == match.fg and style.bg == normal.bg:
          onRow = true
        if style.fg == matchSel.fg and style.bg == current.bg:
          onSelected = true
    check onRow
    check onSelected
    check not matchBg

  test "The box is drawn in the picker's own entries, not the popup's":
    # After the editor, which sets the theme up.
    let e = newPickerEditor()
    let saved = themeColors
    var colors = saved
    # Apart even in 256 colors, which the test terminal uses.
    const
      Fgs = [
        "#ff0000", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff", "#ff8700",
        "#87ff00",
      ]
      Bgs = [
        "#5f0000", "#005f00", "#00005f", "#5f5f00", "#5f005f", "#005f5f", "#875f00",
        "#5f8700",
      ]
    for i, (picker, _) in PickerColorFallbacks:
      colors[picker] = ColorPair(
        foreground: ThemeColor(rgb: color.rgb(Fgs[i])),
        background: ThemeColor(rgb: color.rgb(Bgs[i])),
      )
    setThemeColors(colors)
    defer:
      setThemeColors(saved)
    e.typeKeys(":picker buffers<Enter>a")
    var frame = newBuffer(80, 24)
    e.render(frame)
    const OnSurface = {
      EditorColorPairIndex.pickerBorder, EditorColorPairIndex.pickerTitle,
      EditorColorPairIndex.pickerDetail,
    }
    let surface = getThemeStyle(EditorColorPairIndex.picker).bg
    var
      seen: set[EditorColorPairIndex]
      corner = (x: -1, y: -1)
    for y in 0 ..< 24:
      for x in 0 ..< 80:
        let cell = frame[x, y]
        for (picker, popup) in PickerColorFallbacks:
          # The preview's entry falls back to the picker's own.
          if picker != EditorColorPairIndex.pickerPreview:
            check cell.style != getThemeStyle(popup)
          if cell.style.fg == getThemeStyle(picker).fg:
            seen.incl picker
            # Drawn on the picker's background, not the entry's own.
            if picker in OnSurface:
              check cell.style.bg == surface
        if cell.symbol == "┌" and corner.x < 0:
          corner = (x: x, y: y)
    check corner.x >= 0
    check frame[corner.x, corner.y].style.fg ==
      getThemeStyle(EditorColorPairIndex.pickerBorder).fg
    # The prompt mark, inside the box on its first row.
    let mark = frame[corner.x + 1, corner.y + 1]
    check mark.symbol == ">"
    check mark.style.fg == getThemeStyle(EditorColorPairIndex.pickerDetail).fg
    check seen >= {
      EditorColorPairIndex.picker, EditorColorPairIndex.pickerBorder,
      EditorColorPairIndex.pickerTitle, EditorColorPairIndex.pickerSelection,
      EditorColorPairIndex.pickerDetail,
    }

  test "A match takes the match entry's modifiers on the row's background":
    # After the editor, which sets the theme up.
    let e = newPickerEditor()
    let saved = themeColors
    var colors = saved
    colors[EditorColorPairIndex.pickerMatch].italic = true
    colors[EditorColorPairIndex.pickerMatchSel].italic = true
    setThemeColors(colors)
    defer:
      setThemeColors(saved)
    # `a` matches every buffer, the selected one too.
    e.typeKeys(":picker buffers<Enter>a")
    var frame = newBuffer(80, 24)
    e.render(frame)
    let
      match = getThemeStyle(EditorColorPairIndex.pickerMatch)
      matchSel = getThemeStyle(EditorColorPairIndex.pickerMatchSel)
      normal = getThemeStyle(EditorColorPairIndex.picker)
      current = getThemeStyle(EditorColorPairIndex.pickerSelection)
    var onRow, onSelected = false
    for y in 0 ..< 24:
      for x in 0 ..< 80:
        let style = frame[x, y].style
        if StyleModifier.Italic in style.modifiers:
          if style.fg == match.fg and style.bg == normal.bg:
            onRow = true
          if style.fg == matchSel.fg and style.bg == current.bg:
            onSelected = true
    check onRow
    check onSelected

  test "With no room for the box, none of it shows, nor the cursor":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta")
    var frame = newBuffer(80, 4)
    e.render(frame)
    for y in 0 ..< 4:
      var row = ""
      for x in 0 ..< 80:
        row.add frame[x, y].symbol
      check "Buffers" notin row
      check "> beta" notin row
    check not e.state.cursorVisible
    check e.state.isPickerOverlay

  test "The status line says PICKER":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>")
    var frame = newBuffer(80, 24)
    e.render(frame)
    var screen = ""
    for y in 0 ..< 24:
      for x in 0 ..< 80:
        screen.add frame[x, y].symbol
    check "PICKER" in screen

  test "A click under the picker moves nothing":
    let e = newPickerEditor()
    e.typeKeys("<C-w>v")
    let before = e.activeWindow
    e.typeKeys(":picker buffers<Enter>")
    var frame = newBuffer(80, 24)
    e.render(frame)
    check not e.handlePointerInput(initPointerInput(5, 70))
    check e.activeWindow == before
    check e.state.isPickerOverlay

  test "A viewer it opened over stays when it closes":
    let e = newPickerEditor()
    check e.executeCommandOverlay(":log") == roContinue
    require e.activeWindow.mode == EditorMode.LogViewer
    e.typeKeys(":picker buffers<Enter><Esc>")
    check e.activeWindow.mode == EditorMode.LogViewer

  test "A buffer gone since the list was made leaves the viewer as it was":
    let e = newPickerEditor()
    e.typeKeys(":picker buffers<Enter>beta<Esc>")
    var beta = BufferId(0)
    for b in e.buffers:
      if b.filePath == some(files[1]):
        beta = b.id
    check e.closeBuffer(beta).isOk
    check e.executeCommandOverlay(":log") == roContinue
    require e.activeWindow.mode == EditorMode.LogViewer
    let beeps = e.state.beepCount
    e.typeKeys(":picker resume<Enter><Enter>")
    check not e.state.isPickerOverlay
    check e.activeWindow.mode == EditorMode.LogViewer
    check e.state.statusMessage == "Buffer no longer available"
    check e.state.beepCount > beeps

  test "Opening an item from over a viewer leaves the viewer":
    let e = newPickerEditor()
    check e.executeCommandOverlay(":log") == roContinue
    e.typeKeys(":picker buffers<Enter>beta<Enter>")
    check e.activeWindow.mode == EditorMode.Normal
    check e.shownFile == "beta.txt"
