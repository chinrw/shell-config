{
  inputs,
  pkgs,
  lib,
  stdenv,
  bun,
  fetchurl,
  rustPlatform,
  ...
}:
let
  source = inputs.oh-my-pi;
  system = stdenv.hostPlatform.system;
  rootManifest = lib.importJSON "${source}/package.json";
  version = (lib.importJSON "${source}/packages/coding-agent/package.json").version;

  # Keep the compiler/runtime aligned with upstream's packageManager field.
  bunVersion = lib.removePrefix "bun@" rootManifest.packageManager;
  bunSources = {
    aarch64-darwin = {
      asset = "bun-darwin-aarch64.zip";
      hash = "sha256-2LliIYKK1vl6x6wKt+lYcjQa92MAHogD6CZ2UsJlJiA=";
    };
    aarch64-linux = {
      asset = "bun-linux-aarch64.zip";
      hash = "sha256-on/7Y6gxA3WDbg1vZorhf6jY0YuIw3yCHGUzGXOhmjs=";
    };
    x86_64-linux = {
      asset = "bun-linux-x64-baseline.zip";
      hash = "sha256-oGOQiuCLeFLKEJObvcbO7T3avOj7lALc6D1l1zs25sc=";
    };
  };
  bunSource = bunSources.${system} or (throw "oh-my-pi: unsupported system ${system}");
  bunForOmp = bun.overrideAttrs (_: {
    version = bunVersion;
    src = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/${bunSource.asset}";
      inherit (bunSource) hash;
    };
  });

  bun2nix = inputs.bun2nix.packages.${system}.default;
  # Keep generation out of evaluation so Darwin can evaluate Linux packages.
  # Workspace paths in bun.nix are relative to the upstream repository root.
  bunNix = builtins.toFile "oh-my-pi-bun-deps.nix" (
    builtins.replaceStrings [ "copyPathToStore ./" ] [ "copyPathToStore ${source}/" ] (
      builtins.readFile ./bun.nix
    )
  );
  patchedDependencies = lib.mapAttrs (_: path: source + "/${path}") (
    rootManifest.patchedDependencies or { }
  );
  bunDeps = bun2nix.fetchBunDeps {
    inherit bunNix;
    overrides = bun2nix.patchedDependenciesToOverrides { inherit patchedDependencies; };
  };

  rustChannel =
    (builtins.fromTOML (builtins.readFile "${source}/rust-toolchain.toml")).toolchain.channel;
  rustDate = lib.removePrefix "nightly-" rustChannel;
  rustPkgs = pkgs.extend (import inputs.rust-overlay);
  rustToolchain = rustPkgs.rust-bin.nightly.${rustDate}.minimal;
  cargoDeps = rustPlatform.fetchCargoVendor {
    pname = "oh-my-pi";
    inherit version;
    src = source;
    hash = "sha256-DJzwmMpv7SaMIyOmOkpCpM/sTMcxGgB1wBZiu4fl+ns=";
  };

  linuxLibraryPath = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    pkgs.glibc
    pkgs.openssl
    pkgs.zlib
  ];
  ompBinary =
    if system == "x86_64-linux" then
      "packages/coding-agent/dist/omp-linux-x64"
    else
      "packages/coding-agent/dist/omp";
in
assert lib.assertMsg (bunVersion == "1.3.14")
  "oh-my-pi: update the Bun release hashes for upstream packageManager ${rootManifest.packageManager}";
stdenv.mkDerivation {
  pname = "oh-my-pi";
  inherit version;
  src = source;
  inherit cargoDeps bunDeps;

  nativeBuildInputs = [
    bunForOmp
    bun2nix.hook
    rustToolchain
    rustPlatform.cargoSetupHook
    pkgs.cmake
    pkgs.installShellFiles
    pkgs.pkg-config
    pkgs.python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    pkgs.makeWrapper
    pkgs.patchelf
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    pkgs.darwin.sigtool
    pkgs.llvmPackages.clang
  ];

  buildInputs = [
    pkgs.openssl
    pkgs.zlib
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    pkgs.libiconv
    pkgs.llvmPackages.libclang
  ];

  bunInstallFlags = [
    "--linker=hoisted"
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "--backend=copyfile"
  ];
  dontRunLifecycleScripts = true;

  preBunNodeModulesInstallPhase = ''
    export PATH="${bunForOmp}/bin:$PATH"
  '';

  # Upstream's development helper selects an addon from the builder's AVX2
  # support. Pin baseline so one derivation always produces the same output.
  postPatch = lib.optionalString (system == "x86_64-linux") ''
    substituteInPlace packages/natives/scripts/build-bindings.ts \
      --replace-fail 'import { detectHostAvx2Support } from "../../../scripts/host-detect";' "" \
      --replace-fail 'process.arch === "x64" ? (detectHostAvx2Support() ? "modern" : "baseline") : null;' \
        'process.arch === "x64" ? "baseline" : null;'
  '';

  LIBCLANG_PATH = lib.optionalString stdenv.hostPlatform.isDarwin "${lib.getLib pkgs.llvmPackages.libclang}/lib";
  CARGO_INCREMENTAL = "0";
  # CMake is used by Rust crates; the repository root is not a CMake project.
  dontUseCmakeConfigure = true;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"
    export PATH="${bunForOmp}/bin:$PATH"

    bun --cwd=packages/natives run build:bindings
    ${lib.optionalString (system == "x86_64-linux") "CROSS_TARGET=linux-x64 "}bun --cwd=packages/coding-agent run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    export HOME="$TMPDIR"
    mkdir -p "$out/bin"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm755 ${ompBinary} "$out/libexec/omp"
    patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" "$out/libexec/omp"
    makeWrapper "$out/libexec/omp" "$out/bin/omp" \
      --prefix LD_LIBRARY_PATH : "${linuxLibraryPath}"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    install -Dm755 ${ompBinary} "$out/bin/omp"
  ''
  + ''
    installShellCompletion --cmd omp \
      --bash <("$out/bin/omp" completions bash) \
      --fish <("$out/bin/omp" completions fish) \
      --zsh <("$out/bin/omp" completions zsh)

    runHook postInstall
  '';

  dontPatchELF = stdenv.hostPlatform.isLinux;
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME="$TMPDIR"
    "$out/bin/omp" --version
  '';

  meta = {
    description = "AI coding agent for the terminal";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = builtins.attrNames bunSources;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
}
