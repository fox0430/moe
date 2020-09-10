import parseopt, pegs, os

type ComdParsedList* = seq[tuple[filename: string]]

proc staticReadVersionFromNimble: string {.compileTime.} =
  let peg = """@ "version" \s* "=" \s* \" {[0-9.]+} \" @ $""".peg
  var captures: seq[string] = @[""]
  let nimbleSpec = staticRead(currentSourcePath.parentDir() / "../../moe.nimble")
  assert nimbleSpec.match(peg, captures)
  assert captures.len == 1
  return captures[0]

proc checkReleaseBuild: string {.compileTime.} =
  if defined(release): return "Release"
  else: return "Debug"

proc writeVersion() =
  echo "moe v" & staticReadVersionFromNimble()
  echo "Build type: " & checkReleaseBuild()
  quit()

proc writeHelp() =
  echo """
  moe [file]    edit file

  -v    Print version
  --version    Print version
  """
  quit()

proc parseCommandLineOption*(line: seq[string]): ComdParsedList  =
  var parsedLine = initOptParser(line)
  var index = 0
  for kind, key, val in parsedLine.getopt():
    case kind:
      of cmdArgument:
        result.add((filename: key))
      of cmdShortOption, cmdLongOption:
        case key:
          of "v", "version": writeVersion()
          of "help": writeHelp()
      of cmdEnd:
        assert(false)

    inc(index)
