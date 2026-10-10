# Toolchain

The reference tool versions are ProVerif 2.05, Tamarin Prover 1.12.0, and
Maude 3.5.1. The release uses Bash, GNU `timeout` and `sha256sum`, Node.js 20.x,
and a UTF-8 locale. GPU hardware is not required.

## ProVerif

Install OCaml and the build prerequisites for the official ProVerif source.
On Ubuntu, the basic prerequisites can be installed with:

```bash
sudo apt-get install ocaml build-essential curl nodejs coreutils
bash formal/proverif/build-proverif-2.05.sh
```

Check `node --version`: the reference runner used Node.js 20.20.1. If the
distribution's `nodejs` package installs another major version, install
Node.js 20.x separately before running the JavaScript helpers.

The helper downloads
<https://proverif.inria.fr/proverif2.05.tar.gz>, checks SHA-256
`4871f53c32ab4a04669a060c4886ba5d9080496963fb980a9a62d2c429ceabc4`,
and builds with `./build -nointeract`. Tools are placed in the ignored
`.formal-tools/` directory. No third-party tool binaries are distributed in
this repository.

## Tamarin and Maude

Install the pinned Tamarin version from its
[official 1.12.0 release](https://github.com/tamarin-prover/tamarin-prover/releases/tag/1.12.0)
and Maude 3.5.1 from the
[official Maude releases](https://github.com/maude-lang/Maude/releases/tag/Maude3.5.1).
Keep the Maude distribution's supporting files with its executable. General
installation and WSL2 instructions are in the
[Tamarin manual](https://tamarin-prover.com/manual/master/book/002_installation.html).

Confirm the versions with `tamarin-prover --version`; its output must identify
both Tamarin 1.12.0 and Maude 3.5.1. General package-manager installation
commands may install another version, which this release's runner will reject.

```bash
TAMARIN_BIN=/path/to/tamarin-prover MAUDE_BIN=/path/to/maude \
  bash formal/tamarin/run_all.sh
```

The runner places Maude's directory on PATH and verifies that Tamarin sees
the pinned dependency. It defaults to `C.UTF-8` and four RTS cores. If a
different UTF-8 locale is required, set `TAMARIN_UTF8_LOCALE`. Record any
resource or timeout changes when reporting an independent reproduction.

Tool versions are acceptance prerequisites. Executable hashes describe the
actual local builds; they are not assumed to match across operating systems
and compilation environments. No result is accepted solely because a tool
starts successfully.
