# GNU bc ships two programs — `bc` (the calculator) and `dc` (the RPN desk
# calculator) — built from bc/*.o and dc/*.o, both linking the shared
# lib/libbc.a (number.c bignum core + GNU getopt + vfprintf). To honour the
# unpins one-pkg-one-bin rule we post-link them into one multicall ELF/Mach-O.
#
# This is a procps-class fold, NOT the simple diffutils shape: the shared
# lib/number.o *calls back* into `rt_error` / `out_of_memory` / `rt_warn`
# (number.c:1172,1218,…), which bc and dc each define PRIVATELY with different
# behaviour. A single shared number.o can only bind one set, so we can't share
# it. Instead we give each program its OWN renamed copy of the whole object
# graph (its own objects + the lib objects), privatising every defined global
# behind a per-program prefix so the two graphs can't collide.
#
#   1. `make` runs upstream normally → bc/bc, dc/dc, every .o, lib/libbc.a.
#   2. Phase A (discovery, BEFORE any recompile so symbol names are canonical):
#      for each program nm its full object set (program objs + lib objs) and
#      emit `multicall/<p>.rename.h` = `#define main <p>_main` plus
#      `#define <sym> <p>__<sym>` for every defined global.
#   3. Phase B (recompile + isolate): per program, rebuild its program objs and
#      the lib objs with `-include <p>.rename.h` (the gcc-wrapper prepends it to
#      every compile), then copy the fresh .o into multicall/<p>/ so the next
#      program's rebuild can clobber the shared lib/ path. cpp-level rename is
#      mandatory under pkgsStatic fat-LTO (objcopy --redefine-sym would leave
#      the bitcode `main` intact).
#   4. dispatcher.o (basename(argv[0]) → bc_main / dc_main) via the shared
#      Recipe-A generator; final link folds both renamed graphs + $(READLINELIB)
#      + $(LIBS), no libbc.a.
#   5. Replace the two upstream binaries with one `bc` + a `dc` applet symlink;
#      lib.withAliases harvests it into unpin/aliases.
#
# Two callers:
#   - flake.nix `build`        → native pkgsStatic (Linux ELF, macOS Mach-O),
#                                bc with the readline-fallback ncurses.
#   - flake.nix `windowsBuild`  → mingw cross. bc is pure compute (no POSIX-only
#                                headers), so it goes through mingw, NOT cosmo;
#                                see flake.nix for the three cross fixes. The
#                                fold is identical — one bc.exe with `dc` as an
#                                embedded argv[0] alias (no symlink on Windows),
#                                and no $(READLINELIB) in the link (the mingw
#                                build is --without-readline).
{ lib }:
{ pkgs                  # build-host pkgs (writeText, withAliases)
, basePkg               # the bc derivation to fold (native or mingw)
, isWindows ? false     # mingw PE: bin/bc.exe, embedded `dc` alias, no symlink
, isTargetDarwin ? false # Mach-O: nm prints `_`-prefixed names + `S`-type data
}:
let
  exe = lib.optionalString isWindows ".exe";
  outName = "bc${exe}";
  # mingw is --without-readline, so $(READLINELIB) would be undefined/empty;
  # native links it (readline + the fallback-terminfo ncurses).
  readlineLib = lib.optionalString (!isWindows) "$(READLINELIB)";
  progObjs = {
    bc = [ "main.o" "bc.o" "scan.o" "execute.o" "load.o" "storage.o" "util.o" "global.o" "warranty.o" ];
    dc = [ "dc.o" "input.o" "misc.o" "eval.o" "stack.o" "array.o" "numeric.o" "string.o" ];
  };
  libObjs = [ "getopt.o" "getopt1.o" "vfprintf.o" "number.o" ];

  # mingw's `gcc -o multicall/bc` auto-appends `.exe`; name the target with the
  # extension so $@ matches the file actually written (and the install source).
  multicallMk = pkgs.writeText "unpin-bc-multicall.mk" ''
    MULTI_OUT ?= $(top_builddir)/multicall/${outName}

    .PHONY: multicall-link
    multicall-link: $(MULTI_OUT)

    $(MULTI_OUT): $(top_builddir)/multicall/dispatcher.o
    	$(LINK) \
    		$(top_builddir)/multicall/dispatcher.o \
    		$(top_builddir)/multicall/obj_bc/*.o \
    		$(top_builddir)/multicall/obj_dc/*.o \
    		${readlineLib} $(LIBS)
  '';

  mkRenameSnippet = prog:
    let objs = lib.concatStringsSep " " ((map (o: "${prog}/${o}") progObjs.${prog})
      ++ (map (o: "lib/${o}") libObjs));
    in ''
      {
        echo "/* bc multicall rename header: ${prog} */"
        echo "#define main ${prog}_main"
        $NM --defined-only -g ${objs} 2>/dev/null \
          | awk -v p="${prog}" -v strip=${if isTargetDarwin then "1" else "0"} '
              $2 ~ /^[TBDRWVCS]$/ {
                sym = $3
                if (strip && sym ~ /^_/) sym = substr(sym, 2)
                if (sym ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && sym != "main" && !seen[sym]++)
                  print "#define " sym " " p "__" sym
              }'
      } > multicall/${prog}.rename.h
    '';

  mkRebuildSnippet = prog: ''
    rm -f ${prog}/*.o lib/*.o
    make -C ${prog} -j''${NIX_BUILD_CORES:-1} ${lib.concatStringsSep " " progObjs.${prog}} \
      NIX_CFLAGS_COMPILE="$_orig_NIX_CFLAGS_COMPILE -include $PWD/multicall/${prog}.rename.h"
    make -C lib -j''${NIX_BUILD_CORES:-1} ${lib.concatStringsSep " " libObjs} \
      NIX_CFLAGS_COMPILE="$_orig_NIX_CFLAGS_COMPILE -include $PWD/multicall/${prog}.rename.h"
    mkdir -p multicall/obj_${prog}
    for o in ${lib.concatStringsSep " " progObjs.${prog}}; do cp "${prog}/$o" "multicall/obj_${prog}/$o"; done
    for o in ${lib.concatStringsSep " " libObjs}; do cp "lib/$o" "multicall/obj_${prog}/lib_$o"; done
  '';

  multicall = basePkg.overrideAttrs (old: {
    pname = "bc-multi";
    doCheck = false;

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p multicall
      _orig_NIX_CFLAGS_COMPILE=''${NIX_CFLAGS_COMPILE:-}

      # Phase A: discovery (canonical symbols, before any recompile).
      ${mkRenameSnippet "bc"}
      ${mkRenameSnippet "dc"}

      # Phase B: recompile + isolate.
      ${mkRebuildSnippet "bc"}
      ${mkRebuildSnippet "dc"}

      printf 'bc\tbc\ndc\tdc\n' > multicall/applets.list
${lib.multicallTableDispatcherC { name = "bc"; defaultApplet = "bc"; }}
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      install -m644 ${multicallMk} bc/unpin-multicall.mk
      make -C bc -f Makefile -f unpin-multicall.mk multicall-link
    '';

    # Replace upstream's `make install` entirely: it would relink the
    # standalone bc/dc binaries, which now fail (main renamed to bc_main/
    # dc_main). We only ship the multicall + its man pages.
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      install -m755 "multicall/${outName}" "$out/bin/${outName}"
      ${lib.optionalString (!isWindows) ''ln -s bc "$out/bin/dc"''}
      install -m644 doc/bc.1 "$out/share/man/man1/bc.1"
      install -m644 doc/dc.1 "$out/share/man/man1/dc.1"
      runHook postInstall
    '';

    # The binary is fully static (0 embedded store paths); the only closure
    # refs are readline/flex listed in nix-support/propagated-build-inputs
    # metadata. Drop it — this is a leaf artifact, nothing consumes it as a
    # nix input.
    postFixup = (old.postFixup or "") + ''
      rm -rf "$out/nix-support"
    '';
  });
in
lib.withAliases pkgs
  ({ primary = outName; }
   // (if isWindows
       then { aliases = [ "dc" ]; }
       else { aliasesFromSymlinksIn = "bin"; }))
  multicall
