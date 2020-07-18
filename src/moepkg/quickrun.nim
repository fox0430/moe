import osproc, packages/docutils/highlite
import unicodeext, settings, bufferstatus, gapbuffer, messages, ui

type Language = enum
  None = 0
  Nim = 1
  C = 2
  Cpp = 3
  Shell = 4

proc generateCommand(bufStatus: BufferStatus, language: Language): string =
  let filename = $bufStatus.filename

  if language == Language.Nim:
    result = "nim c -r " & filename
  elif language == Language.C:
    result = "gcc " & filename & " && ./a.out"
  elif language == Language.Cpp:
    result = "g++ " & filename & " && ./a.out"
  elif language == Language.Shell:
    if bufStatus.buffer[0] == ru"#!/bin/bash":
      result = "bash " & filename
    else:
      result = "sh " & filename
  else:
    result = ""

proc runQuickRun*(bufStatus: BufferStatus,
                  cmdWin: var Window,
                  settings: EditorSettings): seq[seq[Rune]] =

  let
    filename = bufStatus.filename
    sourceLang = bufStatus.language
    language = if sourceLang == SourceLanguage.langNim: Language.Nim
               elif sourceLang == SourceLanguage.langC: Language.C
               elif sourceLang == SourceLanguage.langCpp: Language.Cpp
               elif filename.len > 3 and
                    filename[filename.len - 3 .. filename.high] == ru".sh":
                      Language.Shell
               else: Language.None

  let
    command = bufStatus.generateCommand(language)
  if command == "": return @[ru""]

  cmdWin.writeRunQuickRunMessage
  let cmdResult = execCmdEx(command)
  cmdWin.erase

  result = @[ru""]
  for i in 0 ..< cmdResult.output.len:
    if cmdResult.output[i] == '\n': result.add(@[ru""])
    else: result[^1].add(toRunes($cmdResult.output[i])[0])

