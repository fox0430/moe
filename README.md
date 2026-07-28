[![](https://github.com/fox0430/moe/workflows/Build/badge.svg)](https://github.com/fox0430/moe/workflows/Build)
[![](https://github.com/fox0430/moe/workflows/CFF/badge.svg)](https://github.com/fox0430/moe/workflows/CFF)
[![](https://github.com/fox0430/moe/workflows/Tests/badge.svg)](https://github.com/fox0430/moe/workflows/Tests)
[![](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## moe

A command line based editor inspired by Vim written in Nim.

This project's goals are easily customizable, high productivity, user friendly, and high performance editor.

![moe](https://user-images.githubusercontent.com/15966436/146791140-e020a07f-7ca1-4bfd-a6a4-f20f4c7885db.png)

## Features

- Written in [Nim](https://nim-lang.org)

- [Selectable buffer backend](https://github.com/fox0430/moe/blob/develop/documents/features.md#buffer-backends) ( >= 0.5.0 )
  - GapBuffer
  - Sqrt Decomposition
  - Rope (B-tree)
  - Piece Table (RB-Tree)

- UTF-8 and other encodings support (Incomplete)

- Vim like mode (Normal, Insert, Visual, Replace, Command, Filer, etc...)

- Vim like keybinds

- Undo/redo

- Syntax highlighting:
  - C
  - C++
  - C#
  - Go
  - Haskell
  - Java
  - JavaScript
  - Markdown
  - Nim
  - Python
  - Rust
  - Shell languages:
    - Bash
    - Fish
    - Zsh
  - TOML
  - YAML
  - JSON/JSONC
  - Lisp
  - Lua
  - Tcl
  - Hyprland
  - Dockerfile
  - XML

- Auto-completion

- Configuration file (TOML)

- Configuration mode (UI)

- Tab line

- Indentation lines

- Highlight current words

- Highlight/Delete trailing spaces

- Auto close/delete paren

- Simple auto indent

- Incremental search

- Auto save

- Suggestions in Command mode

- TrueColor (24bit color)

- VSCode themes

- Build on save

- QuickRun

- Automatic backups

- Vim like register

- Git support

- Bookmarks

- Syntax checker

  - Nim

- [EditorConfig](https://editorconfig.org) support

- Macros

- Terminal ( >= 0.5.0 )

- Language Server Protocol (WIP)

  - Completion

  - Diagnostics

  - Signature Help

  - Inlay Hints

  - Hover

  - Goto definition

  - Find References

  - Call Hierarchy

  - Document Highlight

  - Document Link

  - Code Lens

  - Document Formatting

  - Rename

  - Semantic Tokens

  - Folding Range

  - Selection Range

  - Document Symbol

## Planned features

- Snippets

- Spell checker

- Edit files over ssh

- Fuzzy search

- Plugin system

- Supports huge file

## Install

We recommend Linux environments.

### Requires


- [Nim](https://nim-lang.org) 2.0.10 or higher


- [xclip](https://github.com/astrand/xclip) v0.13 or higher (Option on GNU/Linux)

- [xsel](http://www.kfish.org/software/xsel/) (Option on GNU/Linux)

- [wl-clipboard](https://github.com/bugaevc/wl-clipboard) (Option on GNU/Linux)

Version <= 0.4.0 (Ncurses base)

- [Ncurses](https://invisible-island.net/ncurses) 6.1 or higher

```sh
nimble install moe
```

Check [detail](https://github.com/fox0430/moe/blob/v0.4.0/documents/overview.md)

Version >= 0.5.0 ([Celina](https://github.com/fox0430/celina) base)

```sh
# Latest developmental state inside Github repository
nimble install moe@#head
```

Check [detail](https://github.com/fox0430/moe/blob/develop/documents/overview.md)

## Usage

[Documents (Celina base)](https://github.com/fox0430/moe/blob/develop/documents/index.md)

[Documents (Ncurses base)](https://github.com/fox0430/moe/blob/v0.4.0/documents/index.md)

## The origin of the name
moe is a recursive acronym for "moe is an optimal editor".

And one more, it comes from the Japanese slang 萌え(moe).

## Contributing, bug reports, feature request
Welcome❤

## Community

Ask me anything!

 - [Discord](https://discord.gg/UaJPnCF)

## License

GNU General Public License version 3
