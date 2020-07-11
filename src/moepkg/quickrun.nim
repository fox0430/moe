import osproc, packages/docutils/highlite
import unicodeext, settings

proc runQuickRun*(filename: seq[Rune],
                  language: SourceLanguage,
                  settings: EditorSettings): seq[seq[Rune]] =

  if (language != SourceLanguage.langNim and
      language != SourceLanguage.langC) and
     settings.quickRunCommand.len == 0: return @[ru""]
    
  let
    command = if settings.quickRunCommand.len > 0:
                settings.quickRunCommand
              elif language == SourceLanguage.langNim:
                "nim c -r " & $filename
              elif language == SourceLanguage.langC:
                "gcc " & $filename &  " && ./a.out"
              else: ""
  if command == "": return @[ru""]

  let   cmdResult = execCmdEx(command)

  result = @[ru""]
  for i in 0 ..< cmdResult.output.len:
    if cmdResult.output[i] == '\n': result.add(@[ru""])
    else: result[^1].add(toRunes($cmdResult.output[i])[0])
