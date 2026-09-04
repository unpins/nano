# nano

[GNU nano](https://www.nano-editor.org/) as a single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/nano/actions/workflows/nano.yml/badge.svg)](https://github.com/unpins/nano/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install nano`.

## Usage

Run the `nano` program with [unpin](https://github.com/unpins/unpin):

```bash
unpin nano file.txt
```

To install it onto your PATH:

```bash
unpin install nano
```

Installing also creates an `rnano` command next to `nano`; invoking it is equivalent to `nano -R` (restricted mode).

Syntax highlighting works with no setup: the 39 definitions nano ships (C, Python, Go, Rust, Markdown, shell, …) travel inside the binary and are read from there. Your own `~/.nanorc` is still read on top, so you can override a colour or add a syntax of your own.

## Man pages

`nano.1`, `nanorc.5`, and `rnano.1` are embedded in the binary — read with `unpin man nano`.

## Build notes

- **Windows** uses mingw; Linux and macOS use static builds. All three ship one binary; `rnano` is the same file under another name (nano reads its own program name and switches to restricted mode), which `unpin install` creates for you.
- **Syntax definitions embedded.** nano reads its system configuration from a compiled-in path, so that path is pointed at a mount served from a ZIP at the binary's end (the shared unpin-vfs core), holding a `nanorc` and the 39 syntax files it includes. Only the two reads that can land in the mount — the system nanorc and each file it includes — go through the VFS; every other file nano touches reaches the real filesystem by construction. A build-time check refuses to ship a binary where that wiring did not take, since the failure would otherwise be silent: nano would find no configuration and simply not highlight.
- **Syntax detection.** On Linux/macOS nano links `libmagic` for content-based syntax detection (the `magic` nanorc directive) in addition to the usual extension and first-line matching. The Windows build drops libmagic (it doesn't cross-compile cleanly) and relies on extension/first-line matching only.
- **Terminal.** nano links ncurses; a minimal fallback terminfo is embedded so it renders on common terminals even when the host has no terminfo database. A host database still takes precedence when present.
- **Tests.** nano's testsuite lives in its upstream git tree, not the release tarball, so there is no `make check` to run; `nano --version` is the smoke floor.

## Build locally

```bash
nix build github:unpins/nano
./result/bin/nano
```

Or run directly:

```bash
nix run github:unpins/nano
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/nano/releases) page has standalone binaries and a `.tar.zst` data archive (`*.nanorc` syntax files) for manual download.
