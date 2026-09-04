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
    let
      ulib = unpins-lib.lib;

      # VFS mount for nano's system configuration. nano reads SYSCONFDIR
      # "/nanorc", so the mount IS the sysconfdir and the ZIP root maps onto it.
      vfsRoot = "/__unpins_nanorc__";
      # The slash-free middle: on mingw vfs.c matches by strstr, not by POSIX
      # prefix, so a drive/backslash-mangled path still resolves.
      vfsMarker = "__unpins_nanorc__";

      # The syntax definitions upstream ships in syntax/, plus a nanorc that
      # pulls each one in by name. Explicit includes rather than a wildcard:
      # nano expands an include through glob(3), and a literal path needs
      # nothing from the mount but the open itself. Text files, so one
      # build-host copy serves every target.
      syntaxTree = pkgs: pkgs.buildPackages.runCommand "nano-syntax" { } ''
        mkdir -p "$out/syntax" src
        tar xf ${pkgs.buildPackages.nano.src} -C src --strip-components=1
        cp src/syntax/*.nanorc "$out/syntax/"
        for f in "$out"/syntax/*.nanorc; do
          echo "include \"${vfsRoot}/syntax/$(basename "$f")\"" >> "$out/nanorc"
        done
        test -s "$out/nanorc"
      '';

      # Vendor the unpin-vfs core so nano reads its system nanorc and the
      # syntax files straight out of the binary. The objects are precompiled
      # with the right -D knobs (the implicit .c.o rule carries none) and put
      # on the link line through nano_LDADD, kept out of nano_SOURCES so make
      # never rebuilds them with the wrong flags.
      injectVfs = pkgs: drv: drv.overrideAttrs (old:
        let
          lib = pkgs.lib;
          isWin = pkgs.stdenv.hostPlatform.isWindows;
        in
        {
          postPatch = (old.postPatch or "") + ''
            echo "==> inject unpin-vfs core (self-EOF + zstd) for the embedded nanorc"
            cp ${ulib.vfsCore}/*.c ${ulib.vfsCore}/*.h src/

            echo "==> put the VFS objects on nano's link line"
            substituteInPlace src/Makefile.in \
              --replace-fail 'nano_LDADD = $(top_builddir)/lib/libgnu.a' \
                'nano_LDADD = vfs.o miniz.o unpin_zstd.o $(top_builddir)/lib/libgnu.a'

            echo "==> read the rcfiles through the VFS"
            # The explicit API at the two call sites, rather than binding the
            # libc name for the whole program: these are the only two opens
            # that may land in the mount, and naming them keeps every other
            # file nano touches on the real filesystem by construction. It is
            # also the one binding that reads the same on all three platforms
            # -- vfs.c's _WIN32 half has no rename mode, and a force-included
            # header cannot come before gnulib's config.h.
            #
            # is_good_file() is the gate in front of both: nano only parses an
            # rcfile it has already access()ed and stat()ed, so those two go
            # through the VFS as well. The other guard,
            #     if (access(file, R_OK) == 0 && !is_good_file(file)) return;
            # is left alone and works in our favour: for a path that lives only
            # in the binary that access() fails against the real filesystem,
            # the && short-circuits, and the fopen below is reached.
            sed -i '/#include "prototypes.h"/a extern FILE *unpin_vfs_fopen(const char *path, const char *mode);\nextern int unpin_vfs_access(const char *path, int mode);\nextern int unpin_vfs_stat(const char *path, struct stat *st);' src/rcfile.c
            substituteInPlace src/rcfile.c \
              --replace-fail 'rcstream = fopen(file, "rb");' \
                             'rcstream = unpin_vfs_fopen(file, "rb");' \
              --replace-fail 'FILE *rcstream = fopen(nanorc, "rb");' \
                             'FILE *rcstream = unpin_vfs_fopen(nanorc, "rb");' \
              --replace-fail 'if (access(file, R_OK) != 0)' \
                             'if (unpin_vfs_access(file, R_OK) != 0)' \
              --replace-fail 'if (stat(file, &rcinfo) != -1 && (S_ISDIR(rcinfo.st_mode) ||' \
                             'if (unpin_vfs_stat(file, &rcinfo) != -1 && (S_ISDIR(rcinfo.st_mode) ||'
          '';

          # After configure, so the conftest links (which carry no vfs.o) are
          # untouched, and before anything links.
          preBuild = (old.preBuild or "") + ''
            echo "==> pre-compile the unpin-vfs objects"
            MZ="-DMINIZ_USE_ZSTD -DMINIZ_NO_TIME -DMINIZ_NO_ARCHIVE_WRITING_APIS -DMINIZ_NO_ZLIB_APIS -DMINIZ_NO_ZLIB_COMPATIBLE_NAMES"
            ( cd src
              $CC -O2 -c vfs.c -DUNPIN_VFS_DIRS -DUNPIN_VFS_SELF ${
                   if isWin then "-DUNPIN_VFS_WIN_MARKER='\"${vfsMarker}\"'"
                   else "-DUNPIN_VFS_NOWRAP" } \
                -DUNPIN_VFS_ROOT='"${vfsRoot}/"' $MZ -o vfs.o
              $CC -O2 -c miniz.c      -D_GNU_SOURCE -w $MZ -o miniz.o
              $CC -O2 -c unpin_zstd.c -D_GNU_SOURCE -w $MZ -DUNPIN_ZSTD_VENDORED -o unpin_zstd.o
            )
          '';

          # A binding that fails silently is the whole risk here: nano would go
          # on reading the real filesystem, find no nanorc, and simply not
          # highlight -- with a green build. rcfile.o is where the system
          # nanorc is opened, so it has to name the shim.
          postBuild = (old.postBuild or "") + ''
            echo "==> guard: the rcfile reads actually reach the VFS"
            # All three, not just the open: nano decides whether an rcfile is
            # worth reading in is_good_file(), which asks access() and stat()
            # first. Binding only fopen builds clean, passes a one-symbol
            # check, and still highlights nothing -- measured.
            for sym in unpin_vfs_fopen unpin_vfs_access unpin_vfs_stat; do
              $NM src/rcfile.o 2>/dev/null | grep -q "$sym" || {
                echo "nano: $sym is not referenced from rcfile.o -- the VFS binding did not take" >&2
                exit 1
              }
            done
          '';
        }
      );

    in
    ulib.mkStandaloneFlake {
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
        # Merge the syntax tree into the mega's EOF ZIP, the way file's magic
        # database and tcc's sysroot ride along.
        runtimeDataRoot = pkgs: syntaxTree pkgs;
      };

      # The same tree on the shipped standalone binary; man pages are
      # auto-harvested alongside it.
      runtimeEmbed = {
        native = pkgs: base: {
          runtimeStage = ''
            cp -a ${syntaxTree pkgs}/. "$__unpin_stage/"
            chmod -R u+w "$__unpin_stage"
          '';
        };
        windows = pkgs: base: {
          runtimeStage = ''
            cp -a ${syntaxTree pkgs}/. "$__unpin_stage/"
            chmod -R u+w "$__unpin_stage"
          '';
        };
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
        injectVfs pkgs (pruned.overrideAttrs (o: {
          # nano reads its system configuration from SYSCONFDIR "/nanorc";
          # point that at the VFS mount so the shipped nanorc and the syntax
          # files it includes come out of the binary.
          configureFlags = (o.configureFlags or [ ]) ++ [ "--sysconfdir=${vfsRoot}" ];

          # Off, and measured: `make check` recurses through doc/, src/ and the
          # rest and reports "Nothing to be done" in each. nano's test suite
          # lives in a separate repository (nano-tests), not in the release
          # tarball, so there is nothing here to run.
          doCheck = false;
        }));
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
        # `cross`, not `pkgs`: injectVfs branches on hostPlatform, and the outer
        # pkgs is the x86_64-linux build set, which would take the POSIX path.
        injectVfs cross patched;
    };
}
