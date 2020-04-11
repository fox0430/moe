import os, osproc, strformat, packages/docutils/highlite
import unicodeext

type BuildOnSaveSettings* = object
  buildOnSave*: bool
  workspaceRoot*: seq[Rune]
  command*: seq[Rune]

proc build*(filename, workspaceRoot, command: seq[Rune], language: SourceLanguage): tuple[output: TaintedString, exitCode: int] =
  if language == SourceLanguage.langNim:
    let
      currentDir = getCurrentDir()
      workspaceRoot = workspaceRoot
      cmd = if command.len > 0: $command elif ($workspaceRoot).existsDir: fmt"cd {workspaceRoot} && nimble build" else: fmt"nim c {filename}"

    result = cmd.execCmdEx

    currentDir.setCurrentDir

  elif command.len > 0:
    let currentDir = getCurrentDir()

    result = ($command).execCmdEx

    if getCurrentDir() != currentDir: currentDir.setCurrentDir
