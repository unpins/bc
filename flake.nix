{
  description = "GNU bc (bc + dc calculators) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # bc + dc folded into one multicall binary at $out/bin/bc with `dc` as an
  # argv[0]-dispatch UNPIN_META alias. See ./multicall.nix. bc builds
  # --with-readline; readline pulls ncurses for terminfo lookup, so we swap in
  # the embedded-fallback ncurses (same as dash) so interactive line editing
  # works without a host /usr/share/terminfo.
  outputs = { self, unpins-lib }:
    let
      lib = unpins-lib.lib;
      withReadlineFallback = p:
        let ncFB = lib.embedFallbackTerminfoOnly p.ncurses;
        in p.bc.override { readline = p.readline.override { ncurses = ncFB; }; };
    in
    lib.mkStandaloneFlake {
      inherit self;
      name = "bc";
      binName = "bc";
      smoke = [ "--version" ];
      smokePattern = "1\\.08";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // lib; } {
          inherit pkgs;
          basePkg = withReadlineFallback pkgs.pkgsStatic;
          isTargetDarwin = pkgs.pkgsStatic.stdenv.hostPlatform.isDarwin;
        };
      # Windows: NO cosmo needed. bc is pure compute (zero POSIX-only headers),
      # so it goes through mingw with three small, non-POSIX fixes:
      #   * buildInputs = [] — nixpkgs lists `readline` and `flex` (libfl) as
      #     host inputs, which cross-leak full readline-mingw + flex-mingw builds;
      #   * configureFlags = [ "--without-readline" ];
      #   * -Dsrandom=srand -Drandom=rand (mingw has no BSD random()).
      # Same multicall fold as native (./multicall.nix isWindows path): one
      # bc.exe with `dc` as an embedded argv[0] alias, no $(READLINELIB) link.
      windowsBuild = pkgs:
        let
          mingwPkgs = lib.mingwStaticCross pkgs;
          mingwBc = mingwPkgs.bc.overrideAttrs (old: {
            buildInputs = [ ];
            configureFlags = (old.configureFlags or [ ]) ++ [ "--without-readline" ];
            env = (old.env or { }) // {
              NIX_CFLAGS_COMPILE = builtins.concatStringsSep " " [
                (old.env.NIX_CFLAGS_COMPILE or "")
                "-Dsrandom=srand"
                "-Drandom=rand"
              ];
            };
          });
        in
        import ./multicall.nix { lib = pkgs.lib // lib; } {
          inherit pkgs;
          basePkg = mingwBc;
          isWindows = true;
        };
    };
}
