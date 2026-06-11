{
  description = "nano as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # nano ships an `rnano` symlink that dispatches via argv[0] to enable
  # restricted mode (same as `nano -R`). Drop the symlink at build time
  # and embed it as UNPIN_META so unpin's installer recreates the alias.
  #
  # Plus: bake the curated terminfo fallback list into ncurses → nano
  # renders correctly on hosts without `/usr/share/terminfo`. Host
  # terminfo still wins when present (database stays enabled).
  outputs = { self, unpins-lib }:
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "nano";
      build = pkgs:
        let
          ulib = unpins-lib.lib;
          p = pkgs.pkgsStatic;
          ncursesFB = ulib.embedFallbackTerminfo p.ncurses;
          pruned = (p.nano.override {
            ncurses = ncursesFB;
          }).overrideAttrs (old: {
            postInstall = (old.postInstall or "") + "\n" + ''
              for o in $outputs; do
                d="''${!o}"
                [ -L "$d/bin/rnano" ] && rm -f "$d/bin/rnano"
                true
              done
            '';
          });
        in
        ulib.withAliases pkgs
          {
            primary = "nano";
            aliases = [ "rnano" ];
          }
          pruned;
      # nano cross-mingw pulls `pkgsCross.mingwW64.file` for libmagic; `file`
      # itself fails to cross (readcdf.c hits the same upstream bug the
      # unpins/file repo patches over). `file = null` falls back to
      # extension-based syntax detection.
      #
      # The remaining clash is in browser.c: nano's bundled gnulib
      # `#define DIR struct gl_directory` so its `dirfd` module works, but
      # leaves `rewinddir` unreplaced. mingw's `<dirent.h>` declaration
      # `rewinddir(mingw_DIR *)` thus coexists with `dir` having type
      # `struct gl_directory *`. The patch swaps rewinddir for
      # closedir+opendir under `_WIN32` only — smaller blast radius than
      # patching gnulib, native builds unchanged.
      windowsBuild = pkgs:
        let
          ulib = unpins-lib.lib;
          cross = ulib.mingwStaticCross pkgs;
          patched = (cross.nano.override { file = null; }).overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./nano-mingw-rewinddir.patch ];
            # nano's Makefile links nano.exe with direct gcc (no libtool), so `-static`
            # is the right flag — `-all-static` is libtool-specific and gcc rejects it.
            makeFlags = (old.makeFlags or [ ]) ++ [ "LDFLAGS=-static" ];
            # mingw ncurses headers default to `__declspec(dllimport)` for COLS/wmove/
            # waddnstr/etc., which leaves `__imp_*` references for the static link.
            # `NCURSES_STATIC` flips them back to plain extern declarations.
            env = (old.env or { }) // {
              NIX_CFLAGS_COMPILE = builtins.concatStringsSep " " (
                (pkgs.lib.optional (old ? env && old.env ? NIX_CFLAGS_COMPILE)
                  old.env.NIX_CFLAGS_COMPILE)
                ++ [ "-DNCURSES_STATIC" ]);
            };
            # nano's install rule creates `bin/rnano -> bin/nano`, but mingw's binary
            # is `nano.exe` — the symlink dangles and trips noBrokenSymlinks. Drop it;
            # withAliases recreates it as UNPIN_META.
            postInstall = (old.postInstall or "") + "\n" + ''
              for o in $outputs; do
                d="''${!o}"
                [ -L "$d/bin/rnano" ] && rm -f "$d/bin/rnano"
                true
              done
            '';
          });
        in
        ulib.withAliases pkgs
          {
            primary = "nano.exe";
            aliases = [ "rnano" ];
          }
          patched;
    };
}
