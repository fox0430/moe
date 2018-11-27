proc parseCommandLineOption*(line: seq[string]) =
  
  for i in 0 ..< line.len:
    case line[i]:
      of "-v", "--version":
        echo "v0.0.35"
        quit()
