import std/[options, os, tempfiles, unittest]

import ../src/moepkg/frontend
import ../src/moepkg/[editor, key_bindings, keybind_config, types]
import ../src/moepkg/command_handlers/result_processor

proc testEditor(): Editor =
  newEditor(newEditorConfig())

proc key(e: Editor, notation: string): bool =
  e.handleKeyCombo(parseKeyCombo(notation).get)

suite "Host result interception":
  test "an unset hook preserves native splits":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    check e.executeCommandOverlay(":split")
    check e.windowManager.windows.len == 2
    check e.takeHostResultRequest().isNone

  test "accepted results skip effects and retain their payload in order":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    let original = e.activeBuffer()
    var calls = 0
    check e.hostResultRequestCount == 0
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      check host == e
      inc calls
      r.kind in {hrHSplit, hrVSplit, hrConfig}
    check e.executeCommandOverlay(":split first.txt")
    check e.executeCommandOverlay(":vsplit second.txt")
    check e.executeCommandOverlay(":config")
    check calls == 3
    check e.hostResultRequestCount == 3
    check e.windowManager.windows.len == 1
    check e.activeBuffer() == original
    check e.activeWindow.mode == EditorMode.Normal
    check not e.state.isCommandOverlay
    let first = e.takeHostResultRequest()
    let second = e.takeHostResultRequest()
    let third = e.takeHostResultRequest()
    require first.isSome and second.isSome and third.isSome
    check first.get.kind == hrHSplit
    check first.get.hsplitFilename == some("first.txt")
    check second.get.kind == hrVSplit
    check second.get.vsplitFilename == some("second.txt")
    check third.get.kind == hrConfig
    check e.takeHostResultRequest().isNone
    check e.hostResultRequestCount == 3
    e.hostResultFilter = nil

  test "a declining hook runs once and allows the native result":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    var calls = 0
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      inc calls
    check e.executeCommandOverlay(":split")
    check calls == 1
    check e.hostResultRequestCount == 0
    check e.windowManager.windows.len == 2
    check e.takeHostResultRequest().isNone

  test "window keys and new-buffer keys reach the result hook":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    let original = e.activeBuffer()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind in {hrNextWindow, hrNew}
    for (notation, expected) in [("w", hrNextWindow), ("n", hrNew)]:
      require e.key("C-w")
      require e.key(notation)
      let request = e.takeHostResultRequest()
      require request.isSome
      check request.get.kind == expected
      check e.windowManager.windows.len == 1
      check e.activeBuffer() == original
      check e.buffers.len == 1

  test "runtime key remaps reach the same result hook":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrNew
    check e.keyBindingRegistry.addRuntimeMappingExpanded(Normal, "C-y", "C-w n").len == 0
    require e.key("C-y")
    let request = e.takeHostResultRequest()
    require request.isSome
    check request.get.kind == hrNew
    check e.windowManager.windows.len == 1

  test "mode_switch synthesizes a viewer result without entering its native mode":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrConfig
    check e.keyBindingRegistry.addRuntimeMappingExpanded(
      Normal, "C-y", "mode_switch config"
    ).len == 0
    require e.key("C-y")
    let request = e.takeHostResultRequest()
    require request.isSome
    check request.get.kind == hrConfig
    check e.activeWindow.mode == EditorMode.Normal
    check e.activeWindow.modeState.kind == mskNone
    check e.windowManager.windows.len == 1

  test "Filer split-open retains the filename without creating a native window":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrFilerOpenFileVSplit
    check e.processResult(
      HandlerResult(kind: hrFilerOpenFileVSplit, filerFilePath: "chosen.txt"),
      e.activeBuffer(),
    )
    let request = e.takeHostResultRequest()
    require request.isSome
    check request.get.kind == hrFilerOpenFileVSplit
    check request.get.filerFilePath == "chosen.txt"
    check e.windowManager.windows.len == 1

  test "Filer keys dispatch split-open requests before native side effects":
    let root = createTempDir("moe-host-filer-", "")
    let path = root / "chosen.txt"
    writeFile(path, "chosen text")
    defer:
      removeFile(path)
      removeDir(root)
    for (notation, expected) in [
      ("h", hrFilerOpenFileHSplit), ("v", hrFilerOpenFileVSplit)
    ]:
      let e = testEditor()
      defer:
        e.releaseExternalResources()
      e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
        r.kind in {hrFilerOpenFileHSplit, hrFilerOpenFileVSplit}
      require e.processResult(
        HandlerResult(kind: hrEnterFiler, enterFilerPath: some(root)), e.activeBuffer()
      )
      let listing = e.activeBuffer()
      let state = e.activeWindow.modeState.filer
      for index, entry in state.entries:
        if entry.name == "chosen.txt":
          state.selectedIndex = index
      require e.key(notation)
      let request = e.takeHostResultRequest()
      require request.isSome
      check request.get.kind == expected
      check request.get.filerFilePath == path
      check e.activeWindow.mode == EditorMode.Filer
      check e.activeBuffer() == listing
      check e.windowManager.windows.len == 1

  test "host-owned quit results leave the command overlay without quitting":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind in {hrCloseWindow, hrQuit}
    for (command, kind) in [(":q", hrCloseWindow), (":qa", hrQuit)]:
      check e.executeCommandOverlay(command)
      check not e.state.isCommandOverlay
      check e.activeWindow.mode == EditorMode.Normal
      check e.windowManager.windows.len == 1
      let request = e.takeHostResultRequest()
      require request.isSome
      check request.get.kind == kind

  test "command hooks can still handle custom commands before the result hook":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    e.hostCommandFilter = proc(host: Editor, command: ParsedCommand): bool =
      command.action == claUnknown
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrHSplit
    check e.executeCommandOverlay(":host-action arg")
    let command = e.takeHostCommandRequest()
    require command.isSome
    check command.get.rawText == ":host-action arg"
    check e.takeHostResultRequest().isNone
    check e.executeCommandOverlay(":split")
    check e.takeHostResultRequest().isSome

  test "a host-owned replay error still aborts the replay":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrError
    check e.processReplayedResult(
      HandlerResult(kind: hrError, errorMessage: "handled by host"), e.activeBuffer()
    ) == roAbort
    check e.state.statusMessage != "handled by host"
    let request = e.takeHostResultRequest()
    require request.isSome
    check request.get.errorMessage == "handled by host"

  test "a mapping stops after a host-owned error before deleting text":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    require e.key("i")
    require e.handleTextInput("original")
    require e.key("Esc")
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrError
    require e.keyBindingRegistry.addRuntimeMappingExpanded(Normal, "C-y", "n x").len == 0
    require e.key("C-y")
    check e.activeBuffer().getLine(0) == "original"
    let request = e.takeHostResultRequest()
    require request.isSome
    check request.get.kind == hrError

  test "window keys, repeated Ex commands, and typed Ex commands stop mapping replay":
    for rhs in ["C-w n i X Esc", "@ : i X Esc", ": s p l i t Space x Enter i X Esc"]:
      let e = testEditor()
      defer:
        e.releaseExternalResources()
      let original = e.activeBuffer()
      e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
        r.kind in {hrNew, hrHSplit}
      if rhs == "@ : i X Esc":
        require e.executeCommandOverlay(":split x")
        require e.takeHostResultRequest().isSome
      require e.keyBindingRegistry.addRuntimeMappingExpanded(Normal, "C-y", rhs).len == 0
      require e.key("C-y")
      check original.getLine(0) == ""
      check e.activeBuffer() == original
      check e.activeWindow.mode == EditorMode.Normal
      check not e.state.isCommandOverlay
      check e.windowManager.windows.len == 1
      let request = e.takeHostResultRequest()
      require request.isSome
      if rhs == "C-w n i X Esc":
        check request.get.kind == hrNew
      else:
        check request.get.kind == hrHSplit
        check request.get.hsplitFilename == some("x")
      check e.takeHostResultRequest().isNone

  test "a macro stops before editing after a host-owned window command":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    let original = e.activeBuffer()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      r.kind == hrNew
    let outcome = e.playbackMacro(@["<C-w>", "n", "i", "X", "<Esc>"])
    check outcome.kind == hrError
    check original.getLine(0) == ""
    check e.activeBuffer() == original
    check e.activeWindow.mode == EditorMode.Normal
    check e.windowManager.windows.len == 1
    let request = e.takeHostResultRequest()
    require request.isSome
    check request.get.kind == hrNew
    check e.takeHostResultRequest().isNone

  test "taking an earlier request in the filter still stops mapping replay":
    let e = testEditor()
    defer:
      e.releaseExternalResources()
    let original = e.activeBuffer()
    e.hostResultFilter = proc(host: Editor, r: HandlerResult): bool =
      if r.kind == hrNew:
        let previous = host.takeHostResultRequest()
        require previous.isSome
        check previous.get.kind == hrNextWindow
      r.kind in {hrNextWindow, hrNew}
    require e.processResult(HandlerResult(kind: hrNextWindow), original)
    check e.hostResultRequestCount == 1
    require e.keyBindingRegistry.addRuntimeMappingExpanded(
      Normal, "C-y", "C-w n i X Esc"
    ).len == 0
    require e.key("C-y")
    check e.hostResultRequestCount == 2
    check original.getLine(0) == ""
    let request = e.takeHostResultRequest()
    require request.isSome
    check request.get.kind == hrNew
    check e.takeHostResultRequest().isNone
