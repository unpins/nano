{
  description = "Standalone build of nano";

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
      windows = true;
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
    };
}
