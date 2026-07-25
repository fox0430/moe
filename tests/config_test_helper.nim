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

const LspFeatureTableNames* = [
  "Completion", "Declaration", "Definition", "TypeDefinition", "Implementation",
  "Diagnostics", "SignatureHelp", "DocumentFormatting", "FoldingRange",
  "SelectionRange", "DocumentSymbol", "Hover", "InlayHint", "References",
  "CallHierarchy", "DocumentHighlight", "DocumentLink", "CodeLens", "Rename",
  "SemanticTokens", "ExecuteCommand",
]
  ## Spelled out on purpose: the `[Lsp.<Feature>]` loader, serializer, UI and
  ## docs are all derived from `LspConfig`, so this is the one independent
  ## check that the derived TOML names are the ones users actually write.
  ## Shared so a new feature table cannot be added to one test file only.
