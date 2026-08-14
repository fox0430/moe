## Shared test helpers for clipboard-related tests.

import std/[os, strutils, tempfiles]

const fakeClipboardContent* = "fake system clipboard content"

proc clipboardFilePath*(fakeDir: string): string =
  ## Path of the fake CLIPBOARD selection content file.
  fakeDir / "clipboard.txt"

proc primaryFilePath*(fakeDir: string): string =
  ## Path of the fake PRIMARY selection content file.
  fakeDir / "primary.txt"

proc installFakeClipboardTool*(content: string): string =
  ## Install a fake `xclip` at the front of PATH that records and serves
  ## CLIPBOARD/PRIMARY content in files under its directory. Tests rewrite
  ## the files to simulate external selection changes and read them back to
  ## observe writes. Returns the directory to pass to
  ## `removeFakeClipboardTool`, or "" where a fake executable cannot be
  ## installed.
  when defined(posix):
    let fakeDir = createTempDir("moe-registers-test-", "")
    writeFile(fakeDir / "clipboard.txt", content)
    writeFile(fakeDir / "primary.txt", content)
    let fakeTool = fakeDir / "xclip"
    writeFile(
      fakeTool,
      "#!/bin/sh\n" & "case \"$*\" in\n" & "  *\"-selection primary -i\"*) cat >\"" &
        fakeDir & "/primary.txt\" ;;\n" & "  *\"-selection primary\"*) cat \"" & fakeDir &
        "/primary.txt\" ;;\n" & "  *\"-i\") cat >\"" & fakeDir & "/clipboard.txt\" ;;\n" &
        "  *) cat \"" & fakeDir & "/clipboard.txt\" ;;\n" & "esac\n",
    )
    setFilePermissions(fakeTool, {fpUserRead, fpUserWrite, fpUserExec})
    putEnv("PATH", fakeDir & ":" & getEnv("PATH"))
    return fakeDir
  else:
    return ""

proc removeFakeClipboardTool*(fakeDir: string) =
  ## Restore PATH and delete the fake tool installed by
  ## `installFakeClipboardTool`.
  let prefix = fakeDir & ":"
  let currentPath = getEnv("PATH")
  if currentPath.startsWith(prefix):
    putEnv("PATH", currentPath[prefix.len .. ^1])
  removeDir(fakeDir)

proc installFakeWlClipboardTool*(content: string, stayRunning = false): string =
  ## Install fake `wl-copy`/`wl-paste` executables at the front of PATH.
  ## With `stayRunning` the fake wl-copy keeps running after the write (a
  ## non-forking wl-copy): the write is unconfirmed, the claim window stays
  ## open, and the first read returns the pre-write content. Without it the
  ## fake exits right away (wl-clipboard 2.x), confirming the write.
  ## Returns the directory to pass to `removeFakeClipboardTool`, or ""
  ## where a fake executable cannot be installed.
  when defined(posix):
    let fakeDir = createTempDir("moe-registers-test-", "")
    writeFile(fakeDir / "clipboard.txt", content)
    writeFile(fakeDir / "primary.txt", content)
    let fakeWlCopy = fakeDir / "wl-copy"
    # A stale snapshot of the previous selection is served only while the
    # fake wl-copy keeps running; a wl-copy that exits right away has
    # handed the selection over, so later reads see the current content.
    let staleSnapshot =
      if stayRunning: "cp \"$base.txt\" \"$base.stale.txt\" 2>/dev/null\n" else: ""
    let keepRunning = if stayRunning: "\nsleep 2\n" else: ""
    writeFile(
      fakeWlCopy,
      "#!/bin/sh\n" & "if [ \"$1\" = \"--primary\" ]; then base=\"" & fakeDir &
        "/primary\"; " & "else base=\"" & fakeDir & "/clipboard\"; fi\n" & staleSnapshot &
        "cat > \"$base.txt\"\n" & keepRunning,
    )
    setFilePermissions(fakeWlCopy, {fpUserRead, fpUserWrite, fpUserExec})
    let fakeWlPaste = fakeDir / "wl-paste"
    writeFile(
      fakeWlPaste,
      "#!/bin/sh\n" & "if [ \"$2\" = \"--primary\" ]; then base=\"" & fakeDir &
        "/primary\"; " & "else base=\"" & fakeDir & "/clipboard\"; fi\n" &
        "if [ -f \"$base.stale.txt\" ]; then cat \"$base.stale.txt\"; " &
        "rm -f \"$base.stale.txt\"; else cat \"$base.txt\"; fi\n",
    )
    setFilePermissions(fakeWlPaste, {fpUserRead, fpUserWrite, fpUserExec})
    putEnv("PATH", fakeDir & ":" & getEnv("PATH"))
    return fakeDir
  else:
    return ""

proc waitForClipboardWrite*(fakeDir: string, expected: string) =
  ## Poll until the fake `wl-copy` write has landed in the CLIPBOARD file;
  ## fails loudly on timeout so a late write cannot skew later assertions.
  var tries = 0
  var landed = false
  while tries < 50:
    if readFile(clipboardFilePath(fakeDir)) == expected:
      landed = true
      break
    sleep(10)
    inc tries
  doAssert landed, "fake wl-copy write did not land within 500ms: " & expected
