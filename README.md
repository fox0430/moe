[![Build Status](https://travis-ci.org/fox0430/moe.svg?branch=master)](https://travis-ci.org/fox0430/moe)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## moe

A command line based editor inspired by vi/vim written in Nim.
 
This project's goal is a very customizable, high productivity, user friendly, high performance and funny animation editor.

![moe](https://user-images.githubusercontent.com/15966436/93508284-5fa0ca00-f959-11ea-8282-d64f540e0c54.png)

## Features

- Written in Nim

- Adopt GapBuffer

- UTF-8 and other encodings support (Incomplete)

- Vim like mode (Normal, Insert, Visual, Replace, Ex, Filer)

- Vim like keybinds

- Infinite undo/redo

- Syntax highlighting (Nim, C, C++, C#, Java, Yaml, JavaScript, Python)

- Auto-complete

- Configuration file (TOML)

- Configuration mode (Incomplete)

- Live reload of configuration file

- Multiple file buffers

- Vertical/Horizontal split window

- Tab line

- Simple file manager

- Indentation lines

- Auto close/delete paren

- Simple auto indent

- Incremental search

- Auto save

- Suggestions in ex mode

- Popup window

- VSCode themes

- Build on save

- Work space

- Multiple status bar

- QuickRun

- Automatic backups

- Highlighting current words

## Planned features

- Supports regular expression and PEG

- Supports EditorConfig

- Window management

- Syntax checker

- Snippets

- Spell checker

- Macros

- Terminal

- Git support

- Select data structures

- Edit files over ssh

- Language Server Protocol

- Fuzzy search

- Plugins

- Supports huge file

- Funny animation...

## Install

### Requires

- Nim 1.2.2 or higher

- ncurses (ncursesw)

```sh
# Latest released version
nimble install moe
# Latest developmental state inside Github repository
nimble install moe@#head
```

Check [detail](https://github.com/fox0430/moe/blob/develop/documents/overview.md)
## Usage
[Documents](https://github.com/fox0430/moe/blob/develop/documents/index.md)

## The origin of the name
moe is a recursive acronym for "moe is an optimal editor".    
And one more, it comes from the Japanese slang 萌え(moe).

## Contributing, bug reports, requests
Welcome❤

## License

GNU General Public License version 3
