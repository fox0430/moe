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

import std/[unittest, options, os, strutils]

import pkg/chronos

import ../src/moepkg/syntax_checker {.all.}
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/buffer
import ../src/moepkg/background_process

suite "SyntaxChecker - syntaxCheckCommand":
  test "Nim language returns nim check command":
    let r = syntaxCheckCommand("/path/to/file.nim", SourceLanguage.langNim)
    check r.isOk
    let cmd = r.get
    check cmd.cmd == "nim"
    check cmd.args == @["check", "/path/to/file.nim"]
    check cmd.workingDir == ""

  test "Nim language with relative path":
    let r = syntaxCheckCommand("src/main.nim", SourceLanguage.langNim)
    check r.isOk
    let cmd = r.get
    check cmd.cmd == "nim"
    check cmd.args == @["check", "src/main.nim"]

  test "Unsupported language returns error":
    let r = syntaxCheckCommand("/path/to/file.py", SourceLanguage.langPython)
    check r.isErr
    check "not supported" in r.error

  test "langNone returns error":
    let r = syntaxCheckCommand("/path/to/file.txt", SourceLanguage.langNone)
    check r.isErr

  test "Rust returns error (not yet supported)":
    let r = syntaxCheckCommand("/path/to/file.rs", SourceLanguage.langRust)
    check r.isErr

  test "All non-Nim languages return isErr":
    for lang in SourceLanguage:
      let r = syntaxCheckCommand("test", lang)
      if lang == SourceLanguage.langNim:
        check r.isOk
      else:
        check r.isErr

suite "SyntaxChecker - parseNimCheckResult":
  test "Parse single error":
    let output = @["/path/to/file.nim(5, 10) Error: undeclared identifier: 'foo'"]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 1
    check errors[0].position.line == 4 # 0-based
    check errors[0].position.column == 10
    check errors[0].messageType == SyntaxCheckMessageType.error
    check errors[0].message == "undeclared identifier: 'foo'"

  test "Parse single warning":
    let output =
      @["/path/to/file.nim(10, 3) Warning: unused variable 'x' [XDeclaredButNotUsed]"]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 1
    check errors[0].position.line == 9
    check errors[0].position.column == 3
    check errors[0].messageType == SyntaxCheckMessageType.warning
    check errors[0].message == "unused variable 'x' [XDeclaredButNotUsed]"

  test "Parse hint":
    let output = @[
      "/path/to/file.nim(1, 0) Hint: 'x' is declared but not used [XDeclaredButNotUsed]"
    ]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 1
    check errors[0].messageType == SyntaxCheckMessageType.hint

  test "Parse multiple errors and warnings":
    let output = @[
      "/path/to/file.nim(1, 5) Error: undeclared identifier",
      "/path/to/file.nim(3, 0) Warning: imported but not used",
      "/path/to/file.nim(7, 2) Error: type mismatch",
    ]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 3
    check errors[0].messageType == SyntaxCheckMessageType.error
    check errors[0].position.line == 0
    check errors[1].messageType == SyntaxCheckMessageType.warning
    check errors[1].position.line == 2
    check errors[2].messageType == SyntaxCheckMessageType.error
    check errors[2].position.line == 6

  test "Empty output returns empty seq":
    let output: seq[string] = @[]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 0

  test "Output with no matching path is ignored":
    let output = @["/other/file.nim(1, 5) Error: undeclared identifier"]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 0

  test "Lines without position pattern are ignored":
    let output = @["/path/to/file.nim some random text", "Hint: some global hint", ""]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 0

  test "Lines without known message type are ignored":
    let output = @["/path/to/file.nim(1, 0) Note: something"]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 0

  test "Parse info message type":
    let output = @["/path/to/file.nim(2, 0) Info: some information"]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 1
    check errors[0].messageType == SyntaxCheckMessageType.info
    check errors[0].message == "some information"

  test "Errors from imported module with different absolute path are ignored":
    let output = @[
      "/home/user/.nimble/pkgs/somelib/utils.nim(10, 5) Error: type mismatch",
      "/home/user/project/file.nim(3, 1) Error: undeclared identifier",
    ]
    let errors = parseNimCheckResult("/home/user/project/file.nim", output)
    check errors.len == 1
    check errors[0].position.line == 2
    check errors[0].message == "undeclared identifier"

  test "Same filename in different directory is ignored with absolute path":
    # e.g. checking /home/user/project/utils.nim should not pick up
    # errors from /home/user/.nimble/pkgs/somelib/utils.nim
    let output = @[
      "/home/user/.nimble/pkgs/somelib/utils.nim(5, 0) Error: from dependency",
      "/home/user/project/utils.nim(1, 0) Error: from project",
    ]
    let errors = parseNimCheckResult("/home/user/project/utils.nim", output)
    check errors.len == 1
    check errors[0].message == "from project"

  test "Template instantiation lines are ignored":
    let output = @[
      "/path/to/file.nim(5, 3) template/generic instantiation of `foo` from here",
      "/path/to/file.nim(10, 1) Error: type mismatch",
    ]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 1
    check errors[0].position.line == 9
    check errors[0].messageType == SyntaxCheckMessageType.error

  test "Path mentioned in error message body does not cause false match":
    # The path string appears in the message but not as the source location
    let output = @["/other/main.nim(1, 0) Error: cannot open '/path/to/file.nim'"]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 0

  test "Mixed output with hints, warnings, and errors for same file":
    let output = @[
      "/path/to/file.nim(1, 0) Hint: used config file [Conf]",
      "/path/to/file.nim(3, 6) Warning: imported and not used: 'os' [UnusedImport]",
      "/path/to/file.nim(5, 4) Error: undeclared identifier: 'x'",
      "/path/to/file.nim(5, 8) Error: expression 'x' has no type",
    ]
    let errors = parseNimCheckResult("/path/to/file.nim", output)
    check errors.len == 4
    check errors[0].messageType == SyntaxCheckMessageType.hint
    check errors[1].messageType == SyntaxCheckMessageType.warning
    check errors[2].messageType == SyntaxCheckMessageType.error
    check errors[3].messageType == SyntaxCheckMessageType.error
    # Two errors on the same line
    check errors[2].position.line == errors[3].position.line

suite "SyntaxChecker - applySyntaxCheckToBuffer":
  test "Apply errors to buffer sets line markers":
    let buf = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 1, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "test error",
      ),
      SyntaxCheckError(
        position: BufferPosition(line: 3, column: 0),
        messageType: SyntaxCheckMessageType.warning,
        message: "test warning",
      ),
    ]
    applySyntaxCheckToBuffer(buf, errors)
    check buf.getLineMarker(0) == none(LineMarkerKind)
    check buf.getLineMarker(1) == some(LineMarkerKind.SyntaxError)
    check buf.getLineMarker(2) == none(LineMarkerKind)
    check buf.getLineMarker(3) == some(LineMarkerKind.SyntaxWarning)
    check buf.getLineMarker(4) == none(LineMarkerKind)

  test "Apply clears previous syntax markers":
    let buf = newTextBuffer("line1\nline2\nline3")
    buf.setLineMarker(0, LineMarkerKind.SyntaxError)
    buf.setLineMarker(2, LineMarkerKind.SyntaxWarning)
    # Apply with empty errors should clear syntax markers
    applySyntaxCheckToBuffer(buf, @[])
    check buf.getLineMarker(0) == none(LineMarkerKind)
    check buf.getLineMarker(2) == none(LineMarkerKind)

  test "Apply preserves git markers":
    let buf = newTextBuffer("line1\nline2\nline3")
    buf.setLineMarker(0, LineMarkerKind.GitAdded)
    buf.setLineMarker(1, LineMarkerKind.SyntaxError)
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 2, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "error",
      )
    ]
    applySyntaxCheckToBuffer(buf, errors)
    # Git marker should be preserved
    check buf.getLineMarker(0) == some(LineMarkerKind.GitAdded)
    # Old syntax marker cleared
    check buf.getLineMarker(1) == none(LineMarkerKind)
    # New syntax marker set
    check buf.getLineMarker(2) == some(LineMarkerKind.SyntaxError)

  test "Hints and info are not shown in sidebar":
    let buf = newTextBuffer("line1\nline2\nline3")
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 0, column: 0),
        messageType: SyntaxCheckMessageType.hint,
        message: "a hint",
      ),
      SyntaxCheckError(
        position: BufferPosition(line: 1, column: 0),
        messageType: SyntaxCheckMessageType.info,
        message: "some info",
      ),
    ]
    applySyntaxCheckToBuffer(buf, errors)
    check buf.getLineMarker(0) == none(LineMarkerKind)
    check buf.getLineMarker(1) == none(LineMarkerKind)

  test "Errors on out-of-range lines are ignored":
    let buf = newTextBuffer("line1\nline2")
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 10, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "out of range",
      )
    ]
    applySyntaxCheckToBuffer(buf, errors)
    check buf.getLineMarker(0) == none(LineMarkerKind)
    check buf.getLineMarker(1) == none(LineMarkerKind)

suite "SyntaxChecker - clearSyntaxMarkers":
  test "Clears syntax error and warning markers":
    let buf = newTextBuffer("line1\nline2\nline3")
    buf.setLineMarker(0, LineMarkerKind.SyntaxError)
    buf.setLineMarker(1, LineMarkerKind.SyntaxWarning)
    buf.setLineMarker(2, LineMarkerKind.GitAdded)
    clearSyntaxMarkers(buf)
    check buf.getLineMarker(0) == none(LineMarkerKind)
    check buf.getLineMarker(1) == none(LineMarkerKind)
    check buf.getLineMarker(2) == some(LineMarkerKind.GitAdded)

  test "Clears nothing when no syntax markers exist":
    let buf = newTextBuffer("line1\nline2")
    buf.setLineMarker(0, LineMarkerKind.GitChanged)
    clearSyntaxMarkers(buf)
    check buf.getLineMarker(0) == some(LineMarkerKind.GitChanged)

suite "SyntaxChecker - formattedMessage":
  test "Returns error message for matching line":
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 3, column: 5),
        messageType: SyntaxCheckMessageType.error,
        message: "undeclared identifier",
      )
    ]
    let msg = formattedMessage(errors, 3)
    check msg.isSome
    check msg.get == "Error: undeclared identifier"

  test "Returns warning message for matching line":
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 5, column: 0),
        messageType: SyntaxCheckMessageType.warning,
        message: "unused variable",
      )
    ]
    let msg = formattedMessage(errors, 5)
    check msg.isSome
    check msg.get == "Warning: unused variable"

  test "Returns hint message for matching line":
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 0, column: 0),
        messageType: SyntaxCheckMessageType.hint,
        message: "use const",
      )
    ]
    let msg = formattedMessage(errors, 0)
    check msg.isSome
    check msg.get == "Hint: use const"

  test "Returns info message for matching line":
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 1, column: 0),
        messageType: SyntaxCheckMessageType.info,
        message: "some info",
      )
    ]
    let msg = formattedMessage(errors, 1)
    check msg.isSome
    check msg.get == "Info: some info"

  test "Returns none for non-matching line":
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 3, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "error on line 3",
      )
    ]
    let msg = formattedMessage(errors, 5)
    check msg.isNone

  test "Returns first matching error when multiple on same line":
    let errors = @[
      SyntaxCheckError(
        position: BufferPosition(line: 2, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "first error",
      ),
      SyntaxCheckError(
        position: BufferPosition(line: 2, column: 5),
        messageType: SyntaxCheckMessageType.warning,
        message: "second issue",
      ),
    ]
    let msg = formattedMessage(errors, 2)
    check msg.isSome
    check msg.get == "Error: first error"

  test "Empty errors returns none":
    let errors: seq[SyntaxCheckError] = @[]
    let msg = formattedMessage(errors, 0)
    check msg.isNone

suite "SyntaxChecker - startBackgroundSyntaxCheck":
  test "Unsupported language returns error":
    proc runTest(): Future[bool] {.async.} =
      let r =
        await startBackgroundSyntaxCheck("/path/to/file.py", SourceLanguage.langPython)
      return r.isErr

    check waitFor(runTest())

  test "langNone returns error":
    proc runTest(): Future[bool] {.async.} =
      let r =
        await startBackgroundSyntaxCheck("/path/to/file.txt", SourceLanguage.langNone)
      return r.isErr

    check waitFor(runTest())

  test "Nim language starts process successfully":
    proc runTest(): Future[tuple[isOk: bool, cmd: string]] {.async.} =
      let r =
        await startBackgroundSyntaxCheck("/tmp/nonexistent.nim", SourceLanguage.langNim)
      if r.isOk:
        let checkProc = r.get
        checkProc.process.kill()
        await checkProc.process.closeAsync()
        return (true, checkProc.command.cmd)
      else:
        return (false, r.error)

    let r = waitFor runTest()
    check r.isOk
    check r.cmd == "nim"

  test "SyntaxCheckProcess stores filePath":
    proc runTest(): Future[string] {.async.} =
      let r =
        await startBackgroundSyntaxCheck("/tmp/test_file.nim", SourceLanguage.langNim)
      if r.isOk:
        let checkProc = r.get
        let path = checkProc.filePath
        checkProc.process.kill()
        await checkProc.process.closeAsync()
        return path
      else:
        return ""

    let path = waitFor runTest()
    check path == "/tmp/test_file.nim"

suite "SyntaxChecker - waitForAsync":
  test "Wait for syntax check process and get output":
    proc runTest(): Future[tuple[output: seq[string], processIsNil: bool]] {.async.} =
      # Use echo to simulate nim check output
      let cmd = BackgroundProcessCommand(
        cmd: "echo",
        args: @["test.nim(1, 0) Error: test error"],
        workingDir: getCurrentDir(),
      )
      let bp = await startBackgroundProcess(cmd)
      if bp.isOk:
        let checkProc =
          SyntaxCheckProcess(command: cmd, filePath: "test.nim", process: bp.get)
        let output = (await checkProc.waitForAsync(60.seconds)).get
        return (output, checkProc.process.process.isNil)
      else:
        return (@[], false)

    let r = waitFor runTest()
    check r.output.len >= 1
    check "Error" in r.output[0]
    check r.processIsNil
