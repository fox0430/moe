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

Syntax highlighting is dispatched from `codeBlockNextToken` in `src/moepkg/syntax/syntax_markdown.nim`. This is the single dispatch shared by top-level tokenization (`getNextToken` in `src/moepkg/syntax/tokenizer.nim`) and markdown code fences. To add a language:

1. Add a `lang<Name>` value to the `SourceLanguage` enum.
2. Add entries in `sourceLanguageToStr` and `getSourceLanguage` so filetype detection and LSP language IDs round-trip.
3. Add a `case` arm in `codeBlockNextToken` that dispatches to `<name>NextToken`.
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

## Optional Matter syntax backend

Enable the `matter` Nimble feature to install and build the TextMate-grammar
engine (Nimble 0.24.1 or newer):

```sh
nimble --parser:declarative --features:matter build -d:release
```

For direct compiler invocations, install the optional dependencies first, then
build with `-d:moe.matter` or `-d:features.moe.matter`:

```sh
nimble --parser:declarative --features:matter install -d -y
nimble --parser:declarative --features:matter setup
nim c -d:release -d:moe.matter --out:moe src/moe.nim
```

Moe does not embed or implicitly select any TextMate grammars. A Matter-enabled
build continues to use the builtin tokenizer until a grammar is explicitly
provided. Host applications can opt a buffer or an editor into Matter by passing
grammar text through the public API:

```nim
let grammar = readFile("Nim.tmLanguage.json")
editor.setMatterGrammar(langNim, grammar, "Nim.tmLanguage.json")
# Or limit the opt-in to one buffer:
buffer.setMatterGrammar(langNim, grammar, "Nim.tmLanguage.json")
```

For standalone Moe, place JSON `.tmLanguage.json` or XML plist `.tmLanguage`
files inside Moe's configuration directory (normally `~/.config/moe`) and name
them in `moerc.toml`. Relative subdirectories are allowed; absolute paths and
paths escaping the configuration directory are rejected:

```toml
[Highlight]
backend = "matter"
matterGrammarFiles = ["grammars/Nim.tmLanguage.json"]
```

Config-loaded roots are matched to Moe languages by their declared TextMate
`scopeName`; additional listed grammars may satisfy external includes. The API
overload associates the supplied root with its `SourceLanguage` explicitly, so
custom scope names are supported there.

The existing `[Standard] syntax` toggle enables/disables rendering for either
backend. Reloading config switches existing buffers and invalidates their syntax
caches. A binary compiled without either Matter define uses builtin highlighting
even if the config requests Matter. A Matter-enabled binary also falls back per
language when no valid grammar was supplied. Diff and Log always retain Moe's
builtin lexer.

Matter shares Moe's progressive-load and budgeted incremental paths, per-line
length cap, reserved-word colours, and URI/LSP/diagnostic overlays. Tokenization
has a soft 20ms per-line limit: a timeout or grammar error makes that line and
following lines plain until a reparse starts from an earlier successful state
or the backend is reset. This avoids caching a partial multiline state. Debug
builds and expensive grammars (notably C++) may reach this limit more often.
Debug logging records these failures; see the logging section above.
Build with `-d:matterTimeLimitMs=N` to adjust the soft deadline (`0` disables it).

Moe never downloads grammars. The config path reads only the files explicitly
listed by the user; the API path performs no filesystem access. Grammar licenses
and provenance remain the responsibility of the user or embedding application.

Run the optional tests with
`nim c -r -d:features.moe.matter tests/test_matter_backend.nim` and
`nim c -r -d:features.moe.matter -d:matterTimeLimitMs=0 tests/test_highlight_matter.nim`.

## Contributing

Bug reports, feature requests, and pull requests are welcome. Before opening a PR:

1. Run `nimble ptest` locally and make sure it passes.
2. Run `nph ./` so the formatting check passes in CI.
3. If you changed config keys or commands, run `nimble gendocs` and commit the generated `documents/*.md` updates.
