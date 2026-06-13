# bc

[GNU bc](https://www.gnu.org/software/bc/) — an arbitrary-precision numeric language, plus its companion `dc` reverse-Polish desk calculator. A single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/bc/actions/workflows/bc.yml/badge.svg)](https://github.com/unpins/bc/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install bc`.

`bc` and `dc` are folded into one binary; `dc` runs via the command name (argv[0]).

## Usage

Run the `bc` program with [unpin](https://github.com/unpins/unpin):

```bash
echo '3 + 4 * 2' | unpin bc          # -> 11
echo 'scale=10; 1/3' | unpin bc      # -> .3333333333
unpin bc --unpin-program=dc -e '5 6 + p'   # run dc -> 11
```

To install it onto your PATH:

```bash
unpin install bc
```

Installing creates both `bc` and `dc`.

## Build locally

```bash
nix build github:unpins/bc
./result/bin/bc --version
```

Or run directly:

```bash
nix run github:unpins/bc -- --version
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/bc/releases) page has standalone binaries for manual download.

## Build notes

- **Platforms:** Linux, macOS, Windows.
- **Multicall:** `bc` and `dc` each get their own renamed copy of the whole object graph — the shared `lib/number.o` calls back into per-program `rt_error`/`out_of_memory`, so a single shared copy can't bind both. See [`multicall.nix`](multicall.nix).
- **Line editing:** Linux/macOS link readline with an embedded-fallback terminfo so interactive editing works without a host `/usr/share/terminfo`. The Windows (mingw) build is `--without-readline` (pure compute), so no readline/ncurses cross is pulled in.
- **Man pages:** the `bc.1` and `dc.1` pages are embedded; read with `unpin man bc` / `unpin man bc dc`.
