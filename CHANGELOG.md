# Changelog

## [Unreleased]

### Added

- Nix syntax highlighting, which nixpkgs adds to nano, and the five optional
  definitions upstream keeps in `extra/` (Ada, Fortran, Haskell, POV-Ray, RPM
  spec), turned on with an `include` line in your `~/.nanorc`.
- `set magic` works without the host's `file` database: libmagic's database is
  now inside the binary (+325 KB).
- Windows: `set magic` (content-based syntax detection), as on Linux and
  macOS.

### Fixed

- Windows: syntax highlighting. The 9.2-1 `.exe` looked for its configuration
  in `/etc/nanorc` instead of inside the binary, so it coloured nothing.
- Windows: opening any file no longer shows "Path '.' is not accessible", and
  nano creates its lock file again.
- The README no longer offers a `.tar.zst` syntax archive; the release never
  had one.

## [9.2-1] - 2026-09-26

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

- Updated to nano 9.2.
- The Windows binary is now built by the same compiler as the Linux and macOS
  ones. It stays the same size (1.14 MB to 1.13 MB): the new compiler makes it
  about 15% smaller and the syntax definitions put that back. Checked on
  Windows 10: the version banner, the compiled options and the full `--help`
  are identical to the previous binary's, and `rnano` still starts in
  restricted mode.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.
