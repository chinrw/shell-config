{ lib }:
let
  # Hermes matches lowercased commands and executable basenames. The shared
  # /telegram/ component covers both the download inbox and the organized tree.
  telegramRunners = [
    "sh"
    "bash"
    "dash"
    "zsh"
    "ksh"
    "ash"
    "fish"
    "csh"
    "tcsh"
    "busybox"
    "python*"
    "uv"
    "pip*"
    "node*"
    "npm"
    "npx"
    "deno"
    "bun"
    "perl*"
    "ruby*"
    "php*"
    "lua*"
    "java"
    "awk"
    "gawk"
    "mawk"
    "wine*"
    "source"
    "."
    "eval"
    "xargs"
    "ld-linux*"
    "ld.so*"
    "make"
    "dpkg"
    "apt*"
  ];
  # Plain awk reads stdin as data; awk -f on a download is covered above.
  telegramPipeRunners = [
    "sh"
    "bash"
    "dash"
    "zsh"
    "ksh"
    "ash"
    "fish"
    "busybox"
    "python*"
    "node*"
    "deno"
    "bun"
    "perl*"
    "ruby*"
    "php*"
    "lua*"
  ];
  # Match complete names so sh does not catch sha256sum; wildcards cover versions.
  pipeRunnerPatterns = lib.concatMap (
    runner: [ runner ] ++ lib.optional (!(lib.hasSuffix "*" runner)) "${runner}[!a-z0-9._-]*"
  ) telegramPipeRunners;
in
[
  "/mnt*/telegram/*"
  "cd */telegram*"
  "pushd */telegram*"
]
++ map (runner: "${runner} */telegram/*") telegramRunners
# [ /] covers /bin/bash and env bash. Globs also match arguments, so a read
# such as `ls .../telegram/ | grep bash` is blocked too.
++ map (runner: "*/telegram/*|${runner}") pipeRunnerPatterns
++ map (runner: "*/telegram/*|*[ /]${runner}") pipeRunnerPatterns
++ map (runner: "find */telegram*-exec*[ /]${runner}") pipeRunnerPatterns
