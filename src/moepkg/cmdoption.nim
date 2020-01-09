import parseopt

type ComdParsedList* = tuple[filename: string]

proc writeVersion() =
  echo "v0.1.5"
  quit()

proc writeHelp() =
  echo """
  moe [file]    edit file
 
  -v    Print version
  --version    Print version
  """
  quit()

proc parseCommandLineOption*(line: seq[string]): ComdParsedList  =
  result.filename = ""
  var parsedLine = initOptParser(line)
  for kind, key, val in parsedLine.getopt():
    case kind:
      of cmdArgument:
        result.filename = key
      of cmdShortOption, cmdLongOption:
        case key:
          of "v", "version": writeVersion()
          of "help": writeHelp()
      of cmdEnd:
        assert(false)
