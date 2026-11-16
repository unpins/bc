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
      build = pkgs:
        pkgs.pkgsStatic.bc.overrideAttrs (_: {
          # nixpkgs sets doCheck for bc, and it buys nothing: `Test/` ships in
          # the tarball but is wired into no build at all — not in SUBDIRS, and
          # no TESTS, check_PROGRAMS or check-local anywhere in the tree, so
          # automake's `check` has nothing to run. Off explicitly, because
          # inheriting a `true` that does nothing reads as coverage. (The files
          # are timing/demo programs with no expected output to compare
          # against; wiring them would mean inventing the expectations.)
          doCheck = false;
        });
      # Windows goes through mingw. flex stays out of buildInputs: the tarball
      # ships the generated scanner, and a host-side flex would cross-build for
      # nothing. readline links termcap there, which defines `PC` as readline's
      # terminal.c does; readline's own NEED_EXTERN_PC makes its copy extern.
      windowsBuild = pkgs:
        let mg = lib.mingwStaticCross pkgs; in
        mg.bc.overrideAttrs (old: {
          buildInputs = [
            (mg.readline.overrideAttrs (o: {
              env = o.env // { CFLAGS = o.env.CFLAGS + " -DNEED_EXTERN_PC"; };
            }))
          ];
          patches = (old.patches or [ ]) ++ [ ./patches/mingw-random.patch ];
        });
    };
}
