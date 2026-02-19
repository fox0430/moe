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

  var failedTests: seq[tuple[name: string, exitCode: int]]

  proc afterTest(idx: int, p: Process) =
    let code = p.peekExitCode()
    if code != 0:
      failedTests.add((testFiles[idx], code))

  let exitCode = execProcesses(
    commands,
    n = jobs,
    options = {poParentStreams, poUsePath},
    afterRunEvent = afterTest,
  )

  echo "\nFinished ", testFiles.len, " files"

  if failedTests.len > 0:
    echo "\nFailed (", failedTests.len, "/", testFiles.len, "):"
    for (name, code) in failedTests:
      echo "  FAIL: ", name, " (exit code: ", code, ")"
    echo '\n'
  else:
    echo "\nAll tests passed."

  quit(exitCode)

main()
