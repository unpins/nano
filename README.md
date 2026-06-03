# nano

Standalone build of [GNU nano](https://www.nano-editor.org/).

[![CI](https://github.com/unpins/nano/actions/workflows/nano.yml/badge.svg)](https://github.com/unpins/nano/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

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

The syntax-highlighting `*.nanorc` files ship in the `data.tar.zst` companion and land under the install dir's `share/nano/`. To enable them, add to `~/.nanorc`:

```
include "~/.local/share/unpin/unpins/nano/<tag>/share/nano/*.nanorc"
```

(Adjust the path for non-Linux installs; nano doesn't auto-discover syntax files relative to the binary.)

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

## Man pages

`nano.1`, `nanorc.5`, and `rnano.1` are embedded in the binary — read with `unpin man nano`.

## Manual download

The [Releases](https://github.com/unpins/nano/releases) page has standalone binaries and a `.tar.zst` data archive (`*.nanorc` syntax files) for manual download.
