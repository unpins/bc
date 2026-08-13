{
  description = "GNU bc (bc + dc calculators) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # bc --with-readline pulls ncurses for terminfo lookup. Line editing works
  # without a host /usr/share/terminfo because the fallback terminfo is baked
  # into ncurses centrally (native-overlay/ncurses.nix), for every engine-Linux
  # build — this package needs no swap of its own.
  outputs = { self, unpins-lib }:
    let
      lib = unpins-lib.lib;
    in
    lib.mkStandaloneFlake {
      inherit self;
      name = "bc";
      smoke = [ "--version" ];
      smokePattern = "1\\.08";

      # bc + dc fold into one `bc` binary on every target, windows included;
      # `dc` is an argv[0] alias. `bc` is itself a program, so a bare invocation
      # runs it. Pure C — no requires.cxx.
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [ { name = "bc"; } { name = "dc"; } ];
      };
      build = pkgs: pkgs.pkgsStatic.bc;
      # Windows goes through mingw (bc is pure compute), with three non-POSIX
      # fixes: drop readline/flex (nixpkgs lists them as host inputs, which
      # cross-leak full mingw builds); --without-readline; and -Dsrandom/-Drandom
      # since mingw has no BSD random().
      windowsBuild = pkgs:
        (lib.mingwStaticCross pkgs).bc.overrideAttrs (old: {
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
    };
}
