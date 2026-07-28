# Developer documentation

This document describes how to build, test, debug, and contribute to moe.

## Source layout

```
src/
  moe.nim              # Entry point (main loop, command-line arg handling)
  moepkg/              # Editor implementation
    logger.nim         # File-based debug logger
    message_log.nim    # In-memory message / LSP message log
    cmdline.nim        # Command-line argument parsing
    command_handlers/  # Command-mode dispatchers
    config/            # Config file loading
    ...
tests/                 # std/unittest test suites (test_<module>.nim)
tools/                 # Build/test helpers, doc generators
documents/             # User and developer documentation
example/               # Sample configs and themes
```

## Building

```sh
nimble build           # Default build
nimble release         # Optimized release build (-d:release)
nimble debug           # Debug build (--debugger:native, -d:debug)
```

The resulting binary is `./moe`.

## Running tests

Use the parallel test runner; `nimble test` is **not** the recommended path because it runs serially.

```sh
nimble ptest           # Run all tests in parallel (default: 4 jobs)
nimble ptest 8         # Override job count
```

Environment variables understood by the runner (`tools/paralleltest.nim`):

| Variable             | Purpose                                            |
|----------------------|----------------------------------------------------|
| `MOE_TEST_JOBS`      | Parallel job count (default: 4)                    |
| `MOE_TEST_TIMEOUT`   | Per-file timeout in seconds (default: 120, 0 off)  |

Test files live under `tests/` and follow the `test_<module>.nim` naming convention. They use `std/unittest` (`suite` / `test` / `check`) and are compiled with the chronos async backend (`tests/config.nims` sets `-d:asyncBackend=chronos`).

For async tests, define an inner `proc runTest(): Future[T] {.async.}` and drive it with `waitFor`.

## Code formatting

The repository is formatted with [`nph`](https://github.com/arnetheduck/nph). CI fails if `src/` or `tests/` is not formatted:

```sh
nph src/ tests/
```

## Debug logging

moe ships with a thread-safe file logger (`src/moepkg/logger.nim`) that writes to a log file *outside* the TUI so it does not corrupt the screen.

### Enabling the logger

Logging is **off by default**. Enable it with a command-line flag:

```sh
moe -d                 # or --debug
moe --debug --clear-log    # Also truncate the existing log file on start
```

Or set it in the config file:

```toml
[Log]
clearOnStart = true    # Truncate log file when starting in debug mode
```

### Log file location

- Primary: `./moe-debug.log` (current working directory)
- Fallback: `/tmp/moe-debug.log` (used if the primary path is not writable)

### Writing log entries

`logger.nim` exposes a global logger and four convenience procs. Import it directly — do *not* use `std/logging`.

```nim
import moepkg/logger

logDebug("mymodule", "entering foo()")
logInfo("mymodule",  "loaded config from " & path)
logWarn("mymodule",  "fallback theme in use")
logError("mymodule", "request failed: " & err.msg)
```

Each entry is written as:

```
[2026-05-24 12:34:56] [DEBUG] [mymodule] entering foo()
```

The convenience procs are `gcsafe` and have `raises: []`, so they are safe to call from async handlers and `proc` bodies that disallow exceptions.

## In-editor log viewers

Some information is kept only in memory (it is not flushed to disk) and is viewed through editor commands.

### `:log` / `:messages` — editor message log

Stores command-line messages (errors, save notifications, etc.) emitted by `addMessageLog` (`src/moepkg/message_log.nim`). Use this to recover a message that disappeared from the command line too quickly to read.

```nim
import moepkg/message_log

addMessageLog("saved: " & path)
```

### `:lsplog` — LSP message log

Same mechanism as `:log` but scoped to LSP traffic. Populate it with `addLspMessageLog`.

### `:debug` — debug viewer

Opens a vertical split with a live (~500 ms refresh) dump of internal editor state: active window node, buffer status, search state, macro state, visual selection, jump list, and LSP state.

Which sections are shown is controlled by the `[Debug.*]` tables in `moerc.toml`. See `example/moerc.toml` for the full list of toggles (`Debug.WindowNode`, `Debug.EditorView`, `Debug.BufferStatus`, `Debug.Search`, `Debug.MacroState`, `Debug.Visual`, `Debug.JumpList`, `Debug.Lsp`).

## Adding a syntax language

Syntax highlighting is dispatched from `src/moepkg/syntax/tokenizer.nim`. To add a language:

1. Add a `lang<Name>` value to the `SourceLanguage` enum.
2. Add entries in `sourceLanguageToStr` and `getSourceLanguage` so filetype detection and LSP language IDs round-trip.
3. Add a `case` arm in `getNextToken` that dispatches to `<name>NextToken`.
4. Implement the tokenizer in `src/moepkg/syntax/syntax_<name>.nim`.
5. If the tokenizer carries multi-line state (block comments, raw/long strings, template literals, mode flags, …), put it in a `<Name>State` object under `LangState` in `tokenizer.nim`, seed the initial value in `defaultLangState`, and access it as `g.lang.<name>.<field>`. Do **not** add fields directly to `GeneralTokenizer`; those are silently dropped by the incremental highlighter's capture/restore.
6. **Any language whose tokenizer touches a `LangState` member (or otherwise carries state across lines via `g.state`) requires an entry in `tests/test_highlight_fuzz.nim`**: a `<name>Corpus` proc with snippets that exercise every stateful path, a `runFuzz` test in the `Incremental Highlight Fuzz` suite, and an entry in the `Monotonic-advance guard` corpora table. The fuzz suite is the only automated check that the incremental output matches a full reparse under random edits.
7. Register the file extension(s) in `detectLanguage` (`src/moepkg/highlight.nim`) so buffers pick up the new language automatically.

## Documentation generators

Parts of `documents/` are auto-generated from source. Regenerate them after changing config options or commands:

```sh
nimble gendocs         # Both config and howtouse
nimble genhowtouse     # Just documents/howtouse.md
```

## Contributing

Bug reports, feature requests, and pull requests are welcome. Before opening a PR:

1. Run `nimble ptest` locally and make sure it passes.
2. Run `nph ./` so the formatting check passes in CI.
3. If you changed config keys or commands, run `nimble gendocs` and commit the generated `documents/*.md` updates.
