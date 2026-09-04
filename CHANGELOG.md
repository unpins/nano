# Changelog

## [Unreleased]

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones, and is 15% smaller (1.19 MB to 1.02 MB). Checked on Windows 10: the
  version banner, the compiled options and the full `--help` are identical to
  the previous binary's, and `rnano` still starts in restricted mode.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.
