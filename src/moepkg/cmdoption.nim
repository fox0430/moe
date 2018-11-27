import parseopt, unicode

type
  ComdParsedList* = tuple[
    filename: string 
  ]

proc parseCommandLineOption*(line: seq[string]): ComdParsedList  =
  result.filename = ""
  var parsedLine = initOptParser(line)
  for kind, key, val in parsedLine.getopt():
    case kind:
      of cmdArgument:
        result.filename = key

      of cmdShortOption:
        case key:
          of "v":
            echo "v0.0.35"
            quit()
      of cmdLongOption:
        case key:
          of "version":
            echo "v0.0.35"
            quit()

      of cmdEnd:
        assert(false)
