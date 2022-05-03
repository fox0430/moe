import std/[parseopt, pegs, os, strformat]
import logger

type CmdParsedList* = object
  path*: seq[string]
  isReadonly*: bool

proc staticReadVersionFromNimble: string {.compileTime.} =
  let peg = """@ "version" \s* "=" \s* \" {[0-9.]+} \" @ $""".peg
  var captures: seq[string] = @[""]
  let
    nimblePath = currentSourcePath.parentDir() / "../../moe.nimble"
    nimbleSpec = staticRead(nimblePath)

  assert nimbleSpec.match(peg, captures)
  assert captures.len == 1
  return captures[0]

proc checkReleaseBuild: string {.compileTime.} =
  if defined(release): return "Release"
  else: return "Debug"

proc generateVersionInfoMessage(): string =
  const
    versionInfo = "moe v" & staticReadVersionFromNimble()
    buildType = "Build type: " & checkReleaseBuild()

  result = versionInfo & "\n" & buildType

proc writeVersion() =
  echo generateVersionInfoMessage()
  quit()

proc generateHelpMessage(): string =
  const helpMessage = """
Usage:
  moe [file]       Edit file

Arguments:
  -R               Readonly mode
  --log            Start logger
  -h, --help       Print this help
  -v, --version    Print version
"""

  result = generateVersionInfoMessage() & "\n\n" & helpMessage

proc writeHelp() =
  echo generateHelpMessage()
  quit()

proc writeCmdLineError(kind: CmdLineKind, arg: string) =
  # Short option or long option
  let optionStr = if kind == cmdShortOption: "-" else: "--"

  echo fmt"Unknown option argument: {optionStr}{arg}"
  echo """Pelase check "moe -h""""
  quit()

proc parseCommandLineOption*(line: seq[string]): CmdParsedList =
  var
    parsedLine = initOptParser(line)
    index = 0
  for kind, key, val in parsedLine.getopt():
    case kind:
      of cmdArgument:
        result.path.add(key)
      of cmdShortOption:
        case key:
          of "v": writeVersion()
          of "h": writeHelp()
          of "R": result.isReadonly = true
          else: writeCmdLineError(kind, key)
      of cmdLongOption:
        case key:
          of "log": initLogger()
          of "version": writeVersion()
          of "help": writeHelp()
          else: writeCmdLineError(kind, key)
      of cmdEnd:
        assert(false)

    inc(index)
