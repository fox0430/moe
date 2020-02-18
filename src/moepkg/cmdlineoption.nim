import parseopt

type ComdParsedList* = seq[tuple[filename: string]]

proc writeVersion() =
  echo "v0.1.6"
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
