## Shared test helpers for config-related tests.

import std/[os, envvars, tempfiles]

template withTempHome*(tmpDir, body: untyped) =
  ## Redirect HOME to a temporary directory so that tests never touch
  ## the real ``~/.config``.  The original environment is restored and
  ## the temporary directory is removed when the block exits.
  let tmpDir = createTempDir("moe_test_", "_config")
  let origHome = getEnv("HOME")
  let origXdg = getEnv("XDG_CONFIG_HOME")
  putEnv("HOME", tmpDir)
  delEnv("XDG_CONFIG_HOME")
  defer:
    putEnv("HOME", origHome)
    if origXdg.len > 0:
      putEnv("XDG_CONFIG_HOME", origXdg)
    else:
      delEnv("XDG_CONFIG_HOME")
    removeDir(tmpDir)
  body
