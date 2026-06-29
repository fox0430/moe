# Parallel test runner.
# Usage: nim r tools/paralleltest.nim [jobs]
# Ex: nim r tools/paralleltest.nim 8

import std/[osproc, os, strutils, sequtils]

const
  # Fallback when the number of CPUs cannot be detected (countProcessors() == 0).
  FallbackJobs = 4
  DefaultTimeoutSec = 120

  # Flaky tests that must be run sequentially after the parallel batch
  # so concurrent file/clipboard/etc. usage cannot perturb them.
  SequentialTests = ["test_registers.nim", "test_terminal_handler.nim"]

proc defaultJobs(): int =
  # Default to the number of logical CPUs (hardware threads) available.
  let cpus = osproc.countProcessors()
  if cpus > 0: cpus else: FallbackJobs

proc main() =
  let jobs =
    if paramCount() >= 1:
      parseInt(paramStr(1))
    elif getEnv("MOE_TEST_JOBS").len > 0:
      parseInt(getEnv("MOE_TEST_JOBS"))
    else:
      defaultJobs()

  # Per-file timeout (compile + run) to protect CI from hanging tests.
  # Set MOE_TEST_TIMEOUT=0 to disable. Requires GNU coreutils `timeout`.
  let timeoutSec =
    if getEnv("MOE_TEST_TIMEOUT").len > 0:
      parseInt(getEnv("MOE_TEST_TIMEOUT"))
    else:
      DefaultTimeoutSec

  let allTestFiles = toSeq(walkDir("tests", relative = true))
    .filterIt(
      it.kind == pcFile and it.path.startsWith("t") and it.path.endsWith(".nim")
    )
    .mapIt(it.path)

  let parallelFiles = allTestFiles.filterIt(it notin SequentialTests)
  let sequentialFiles = allTestFiles.filterIt(it in SequentialTests)
  let totalFiles = parallelFiles.len + sequentialFiles.len

  if timeoutSec > 0:
    echo "Running ",
      parallelFiles.len, " tests with ", jobs, " parallel jobs (timeout: ", timeoutSec,
      "s per file)..."
  else:
    echo "Running ", parallelFiles.len, " tests with ", jobs, " parallel jobs..."

  proc buildCommand(file: string): string =
    if timeoutSec > 0:
      "timeout --foreground --kill-after=5 " & $timeoutSec & " nim c -r tests/" & file
    else:
      "nim c -r tests/" & file

  let commands = parallelFiles.mapIt(buildCommand(it))

  var failedTests: seq[tuple[name: string, exitCode: int]]

  proc afterTest(idx: int, p: Process) =
    let code = p.peekExitCode()
    if code != 0:
      failedTests.add((parallelFiles[idx], code))

  var exitCode = execProcesses(
    commands,
    n = jobs,
    options = {poParentStreams, poUsePath},
    afterRunEvent = afterTest,
  )

  if sequentialFiles.len > 0:
    echo "\nRunning ", sequentialFiles.len, " flaky test(s) sequentially..."
    for file in sequentialFiles:
      let code = execCmd(buildCommand(file))
      if code != 0:
        failedTests.add((file, code))
        if exitCode == 0:
          exitCode = code

  echo "\nFinished ", totalFiles, " files"

  if failedTests.len > 0:
    echo "\nFailed (", failedTests.len, "/", totalFiles, "):"
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
