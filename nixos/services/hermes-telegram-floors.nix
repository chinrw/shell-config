let
  # The owner's rule for Telegram: Hermes reads and downloads, and never runs
  # what it downloaded. Downloads are created without execute bits and owned
  # by telegram-reader, so running one takes an interpreter. These floors deny
  # the common ways to do that while ls, mv, cp, 7zz and sha256sum still pass.
  # Files hand-downloaded in the Telegram client do carry execute bits, and
  # organized files move out of the inbox, so the floors cover both trees:
  # /mnt/data/Downloads/Telegram is the inbox and /mnt/data/harmony/telegram
  # holds the organized files. They
  # match "/Telegram/" and "/telegram/" rather than the full paths so ./, //
  # and .. spellings are caught too, and they rely on Hermes matching each
  # command word with its basename folded. A file moved or extracted outside
  # both trees, the terminal workdir argument, and globbed or variable paths
  # all escape them. The smart policy covers those in chat sessions. Cron and
  # -q runs have no such second layer.
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
  # Piping a download into these, or handing it to them from find -exec.
  telegramPipeRunners = [
    "sh"
    "bash"
    "zsh"
    "python*"
    "perl*"
    "node*"
  ];
  floorsFor = dir:
    [
      "/mnt*/${dir}/*"
      "cd */${dir}*"
      "pushd */${dir}*"
    ]
    ++ map (runner: "${runner} */${dir}/*") telegramRunners
    ++ map (runner: "*/${dir}/*| ${runner}*") telegramPipeRunners
    ++ map (runner: "find */${dir}*-exec ${runner} *") telegramPipeRunners;
in
floorsFor "Telegram" ++ floorsFor "telegram"
