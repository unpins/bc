{
  description = "GNU bc (bc + dc calculators) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # bc --with-readline pulls ncurses for terminfo lookup, so swap in the
  # embedded-fallback ncurses (same as dash) so line editing works without a
  # host /usr/share/terminfo.
  outputs = { self, unpins-lib }:
    let
      lib = unpins-lib.lib;
      # ncurses fallback-terminfo is baked centrally for every engine-Linux build
      # (native-overlay/ncurses.nix), so p.ncurses already carries it — no
      # per-package embedFallbackTerminfo. bc is Linux-only (Windows = mingw).
      withReadlineFallback = p:
        p.bc.override { readline = p.readline.override { ncurses = p.ncurses; }; };
    in
    lib.mkStandaloneFlake {
      inherit self;
      name = "bc";
      binName = "bc";
      smoke = [ "--version" ];
      smokePattern = "1\\.08";

      # bc + dc fold into one `bc` binary; `dc` is an argv[0] alias.
      # defaultProgram pins bc so the bare `--version` smoke hits it.
      engine = "unpin-llvm";
      multicall = {
        defaultProgram = "bc";
        programs = [ { name = "bc"; } { name = "dc"; } ];
      };
      build = pkgs: withReadlineFallback pkgs.pkgsStatic;
      # Windows goes through mingw (bc is pure compute), with three non-POSIX
      # fixes: drop readline/flex (nixpkgs lists them as host inputs, which
      # cross-leak full mingw builds); --without-readline; and -Dsrandom/-Drandom
      # since mingw has no BSD random().
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
