# Changelog

## [Unreleased]

### Added

- Syntax highlighting now works out of the box. The 39 definitions nano ships
  (C, Python, Go, Rust, Markdown, shell, …) travel inside the binary and are
  read from there, so opening a source file colours it with nothing installed
  and nothing to configure. Your own `~/.nanorc` is still read on top.

  The v9.0-1 release highlighted nothing: its README pointed at a companion
  archive of `*.nanorc` files that the release did not contain, and the binary
  carried none either — nano has no syntax definitions built into the program
  itself.

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones. It stays the same size (1.14 MB to 1.13 MB): the new compiler makes it
  about 15% smaller and the syntax definitions put that back. Checked on
  Windows 10: the version banner, the compiled options and the full `--help`
  are identical to the previous binary's, and `rnano` still starts in
  restricted mode.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.
