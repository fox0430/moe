# Parallel test runner.
# Usage: nim r tools/paralleltest.nim [jobs]
# Ex: nim r tools/paralleltest.nim 8

import std/[osproc, os, strutils, sequtils]

const
  DefaultJobs = 4
  DefaultTimeoutSec = 120

proc main() =
  let jobs =
    if paramCount() >= 1:
      parseInt(paramStr(1))
    elif getEnv("MOE_TEST_JOBS").len > 0:
      parseInt(getEnv("MOE_TEST_JOBS"))
    else:
      DefaultJobs

  # Per-file timeout (compile + run) to protect CI from hanging tests.
  # Set MOE_TEST_TIMEOUT=0 to disable. Requires GNU coreutils `timeout`.
  let timeoutSec =
    if getEnv("MOE_TEST_TIMEOUT").len > 0:
      parseInt(getEnv("MOE_TEST_TIMEOUT"))
    else:
      DefaultTimeoutSec

  let testFiles = toSeq(walkDir("tests", relative = true))
    .filterIt(
      it.kind == pcFile and it.path.startsWith("t") and it.path.endsWith(".nim")
    )
    .mapIt(it.path)

  if timeoutSec > 0:
    echo "Running ",
      testFiles.len, " tests with ", jobs, " parallel jobs (timeout: ", timeoutSec,
      "s per file)..."
  else:
    echo "Running ", testFiles.len, " tests with ", jobs, " parallel jobs..."

  let commands = testFiles.mapIt(
    if timeoutSec > 0:
      "timeout --foreground --kill-after=5 " & $timeoutSec & " nim c -r tests/" & it
    else:
      "nim c -r tests/" & it
  )

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
      let suffix =
        if code == 124:
          " (TIMEOUT)"
        elif code == 137:
          " (TIMEOUT/KILLED)"
        else:
          ""
      echo "  FAIL: tests/", name, " (exit code: ", code, ")", suffix
    echo '\n'
  else:
    echo "\nAll tests passed."

  quit(exitCode)

main()
