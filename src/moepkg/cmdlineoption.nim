import parseopt, pegs, os, strformat

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
  const helpMessage = """
Usage:
  moe [file]       Edit file

Arguments:
  -h, --help       Print this help
  -v, --version    Print version
"""

  echo helpMessage
  quit()

proc writeCmdLineError(kind: CmdLineKind, arg: string) =
  # Short option or long option
  let optionStr = if kind == cmdShortOption: "-" else: "--"

  echo fmt"Unknown option argument: {optionStr}{arg}"
  echo """Pelase check "moe -h""""
  quit()

proc parseCommandLineOption*(line: seq[string]): ComdParsedList  =
  var parsedLine = initOptParser(line)
  var index = 0
  for kind, key, val in parsedLine.getopt():
    case kind:
      of cmdArgument:
        result.add((filename: key))
      of cmdShortOption:
        case key:
          of "v": writeVersion()
          of "h": writeHelp()
          else: writeCmdLineError(kind, key)
      of cmdLongOption:
        case key:
          of "version": writeVersion()
          of "help": writeHelp()
          else: writeCmdLineError(kind, key)
      of cmdEnd:
        assert(false)

    inc(index)
