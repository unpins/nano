{
  description = "nano as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # nano's `rnano` symlink is dropped at build time; multicall.programs
  # declares it as an alias, which unpin's installer recreates. The fallback
  # terminfo comes with nix-lib's ncurses.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;

      # VFS mount for nano's system configuration. nano reads SYSCONFDIR
      # "/nanorc", so the mount IS the sysconfdir and the ZIP root maps onto it.
      vfsRoot = "/__unpins_nanorc__";
      # The slash-free middle: on mingw vfs.c matches by strstr, not by POSIX
      # prefix, so a drive/backslash-mangled path still resolves.
      vfsMarker = "__unpins_nanorc__";

      # The syntax definitions nixpkgs' nano installs (upstream's syntax/ plus
      # its nix.nanorc), and a nanorc that pulls each one in by name; extra/
      # rides along for a user's own `include`. Explicit includes rather than a
      # wildcard: nano expands an include through glob(3), and a literal path
      # needs nothing from the mount but the open itself. Text files, so one
      # build-host copy serves every target, and so does libmagic's compiled
      # database (byte-order independent, the same file's version), read by
      # ./nano-vfs-magic.patch.
      syntaxTree = pkgs: pkgs.buildPackages.runCommand "nano-syntax" { } ''
        mkdir -p "$out/syntax"
        cp ${pkgs.buildPackages.nano}/share/nano/*.nanorc "$out/syntax/"
        cp -r ${pkgs.buildPackages.nano}/share/nano/extra "$out/syntax/extra"
        for f in "$out"/syntax/*.nanorc; do
          echo "include \"${vfsRoot}/syntax/$(basename "$f")\"" >> "$out/nanorc"
        done
        test -s "$out/nanorc" && test -s "$out/syntax/nix.nanorc"
        cp ${pkgs.buildPackages.file}/share/misc/magic.mgc "$out/magic.mgc"
      '';

      # Vendor the unpin-vfs core so nano reads its system nanorc and the
      # syntax files straight out of the binary (./nano-vfs.patch binds the
      # rcfile reads and links the objects). The objects are precompiled with
      # the right -D knobs; the implicit .c.o rule carries none.
      injectVfs = pkgs: drv: drv.overrideAttrs (old:
        let
          lib = pkgs.lib;
          isWin = pkgs.stdenv.hostPlatform.isWindows;
        in
        {
          patches = (old.patches or [ ]) ++ [ ./nano-vfs.patch ];
          # nano reads its system configuration from SYSCONFDIR "/nanorc";
          # point that at the VFS mount so the shipped nanorc and the syntax
          # files it includes come out of the binary.
          configureFlags = (old.configureFlags or [ ]) ++ [ "--sysconfdir=${vfsRoot}" ];
          postPatch = (old.postPatch or "") + ''
            echo "==> inject unpin-vfs core (self-EOF + zstd) for the embedded nanorc"
            cp ${ulib.vfsCore}/*.c ${ulib.vfsCore}/*.h src/
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
        runtimeDataRoot = syntaxTree;
      };

      # The same tree on the shipped standalone binary; man pages are
      # auto-harvested alongside it.
      runtimeEmbed =
        let stage = pkgs: base: {
          runtimeStage = ''
            cp -a ${syntaxTree pkgs}/. "$__unpin_stage/"
            chmod -R u+w "$__unpin_stage"
          '';
        };
        in { native = stage; windows = stage; };
      build = pkgs:
        let
          p = pkgs.pkgsStatic;
          # Fallback terminfo is baked centrally for every engine-Linux ncurses
          # (native-overlay/ncurses.nix), so p.ncurses already carries it.
          # nano reads the embedded magic.mgc (./nano-vfs-magic.patch). This
          # moves libmagic's compiled fallback, reached only if that copy is
          # missing, from file's store path (a live reference that drags file's
          # closure) to /usr/share/misc/magic.
          magicFile = p.file.overrideAttrs (fo: {
            configureFlags = (fo.configureFlags or [ ]) ++ [ "--datadir=/usr/share" ];
            installFlags = (fo.installFlags or [ ]) ++ [ "datadir=${placeholder "out"}/share" ];
          });
          pruned = (p.nano.override { file = magicFile; }).overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./nano-vfs-magic.patch ];
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
          # Off, and measured: the release tarball has no test suite
          # (SUBDIRS = doc lib m4 po src syntax), so `make check` reports
          # "Nothing to be done" in each.
          doCheck = false;
        }));
      # libmagic on mingw follows unpins/file's recipe (static libgnurx, its
      # cdf.h patch). Its getline.c replacement also defines getdelim, which
      # nano's gnulib defines too; libmagic's pair is renamed at compile time
      # (LTO bitcode, so no objcopy). Its unlisted link deps go in LIBS for
      # nano's -lmagic probe.
      #
      # browser.c: nano's bundled gnulib
      # `#define DIR struct gl_directory` so its `dirfd` module works, but
      # leaves `rewinddir` unreplaced. mingw's `<dirent.h>` declaration
      # `rewinddir(mingw_DIR *)` thus coexists with `dir` having type
      # `struct gl_directory *`. The patch swaps rewinddir for
      # closedir+opendir under `_WIN32` only — smaller blast radius than
      # patching gnulib, native builds unchanged.
      windowsBuild = pkgs:
        let
          cross = ulib.mingwStaticCross pkgs;
          libgnurxStatic = cross.windows.libgnurx.overrideAttrs (old: {
            NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " -std=gnu17";
            buildPhase = ''
              runHook preBuild
              make regex.o
              $AR rcs libgnurx.a regex.o
              runHook postBuild
            '';
            postInstall = "";
            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib $out/include
              install -m 644 libgnurx.a $out/lib/libgnurx.a
              install -m 644 regex.h $out/include/regex.h
              runHook postInstall
            '';
          });
          magicFile = (cross.file.override { libgnurx = libgnurxStatic; }).overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./file-mingw.patch ];
            makeFlags = (old.makeFlags or [ ]) ++ [ "LDFLAGS=-all-static" ];
            NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " -Dgetline=file_getline -Dgetdelim=file_getdelim";
            configureFlags = (old.configureFlags or [ ]) ++ [ "--datadir=/usr/share" ];
            installFlags = (old.installFlags or [ ]) ++ [ "datadir=${placeholder "out"}/share" ];
          });
          patched = (cross.nano.override { file = magicFile; }).overrideAttrs (old: {
            buildInputs = (old.buildInputs or [ ]) ++ [ libgnurxStatic cross.zlib ];
            LIBS = "-lgnurx -lz -lshlwapi";
            patches = (old.patches or [ ]) ++ [
              ./nano-vfs-magic.patch
              ./nano-mingw-rewinddir.patch
              ./nano-mingw-stat-time.patch
              ./nano-mingw-access.patch
            ];
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
