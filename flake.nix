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
      smoke = [ "--version" ];
      smokePattern = "GNU nano.*[0-9]+\\.[0-9]+";

      # Build via the unpin-llvm engine + emit a bitcode multicall module.
      engine = "unpin-llvm";
      multicall = {
        # The `.exe` on the engine too, not the nixpkgs mingw-gcc cross.
        windows = true;
        programs = [{ name = "nano"; aliases = [ "rnano" ]; }];
        # nano is NLS-enabled and bakes its own $out/share/locale as the
        # gettext domain directory; the standalone ships bin/ only, so the path
        # is dead. (The libmagic database path is handled at the source, in the
        # `file` override below, because that one is READ at run time.)
        removeReferences = [ "nano-static" "nano-x86_64-w64-mingw32" ];
      };
      build = pkgs:
        let
          ulib = unpins-lib.lib;
          p = pkgs.pkgsStatic;
          # Fallback terminfo is baked centrally for every engine-Linux ncurses
          # (native-overlay/ncurses.nix), so p.ncurses already carries it.
          # libmagic compiles its default database path from `file`'s own
          # datadir, so nano linked against pkgsStatic.file was carrying
          # /nix/store/<file>/share/misc/magic -- a LIVE reference (it dragged
          # file's whole closure) that resolves only on a machine that has that
          # exact store path. For everyone running the standalone binary it does
          # not exist, magic_load() fails, and the content-based syntax
          # detection the README promises never happens. /usr/share/misc/magic
          # is where Debian, Fedora and macOS all keep it, so a distro-built
          # nano finds a real database there. The install still writes into
          # $out (datadir at install time), it is only the COMPILED default that
          # moves.
          magicFile = p.file.overrideAttrs (fo: {
            configureFlags = (fo.configureFlags or [ ]) ++ [ "--datadir=/usr/share" ];
            installFlags = (fo.installFlags or [ ]) ++ [ "datadir=${placeholder "out"}/share" ];
          });
          pruned = (p.nano.override { file = magicFile; }).overrideAttrs (old: {
            postInstall = (old.postInstall or "") + "\n" + ''
              for o in $outputs; do
                d="''${!o}"
                [ -L "$d/bin/rnano" ] && rm -f "$d/bin/rnano"
                true
              done
            '';
          });
        in
        pruned.overrideAttrs (_: {
          # Off, and measured: `make check` recurses through doc/, src/ and the
          # rest and reports "Nothing to be done" in each. nano's test suite
          # lives in a separate repository (nano-tests), not in the release
          # tarball, so there is nothing here to run.
          doCheck = false;
        });
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
            # No `LDFLAGS=-static` here: it was for mingw-gcc's runtime DLLs, and
            # the engine has none to fold. Measured, not assumed — the `.exe`
            # built without it is byte-identical.
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
            # `rnano` ships as an embedded alias instead.
            postInstall = (old.postInstall or "") + "\n" + ''
              for o in $outputs; do
                d="''${!o}"
                [ -L "$d/bin/rnano" ] && rm -f "$d/bin/rnano"
                true
              done
            '';
          });
        in
        patched;
    };
}
