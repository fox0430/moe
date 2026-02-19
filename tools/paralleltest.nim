# Parallel test runner.
# Usage: nim r tools/paralleltest.nim [jobs]
# Ex: nim r tools/paralleltest.nim 8

import std/[osproc, os, strutils, sequtils]

const DefaultJobs = 4

proc main() =
  let jobs =
    if paramCount() >= 1:
      parseInt(paramStr(1))
    else:
      DefaultJobs

  let testFiles = toSeq(walkDir("tests", relative = true))
    .filterIt(
      it.kind == pcFile and it.path.startsWith("t") and it.path.endsWith(".nim")
    )
    .mapIt(it.path)

  echo "Running ", testFiles.len, " tests with ", jobs, " parallel jobs..."

  let commands = testFiles.mapIt("nim c -r tests/" & it)

  let exitCode =
    execProcesses(commands, n = jobs, options = {poParentStreams, poUsePath})

  echo "\nFinished " & $testFiles.len & " files"
  echo "Exit code: ", exitCode

  quit(exitCode)

main()
