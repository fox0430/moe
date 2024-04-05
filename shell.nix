with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    ncurses.dev
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    ncurses.dev
  ];
}
