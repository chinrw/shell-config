# augment-command.yazi

A [Yazi][yazi-link] plugin that enhances Yazi's default commands.
This plugin is inspired by the
[Yazi tips page][yazi-tips-page],
the [bypass.yazi](https://github.com/Rolv-Apneseth/bypass.yazi) plugin
and the [fast-enter.yazi](https://github.com/ourongxing/fast-enter.yazi)
plugin.

## Table of Contents

- [Requirements](#requirements)
  - [Optional dependencies](#optional-dependencies)
- [Installation](#installation)
- [Configuration](#configuration)
- [What about the commands are augmented?][augment-section]
- [Augmented commands](#augmented-commands)
  - [Open (`open`)](#open-open)
  - [Extract (`extract`)](#extract-extract)
  - [Enter (`enter`)](#enter-enter)
  - [Leave (`leave`)](#leave-leave)
  - [Rename (`rename`)](#rename-rename)
  - [Remove (`remove`)](#remove-remove)
  - [Create (`create`)](#create-create)
  - [Shell (`shell`)](#shell-shell)
    - [Passing arguments to the `shell` command](#passing-arguments-to-the-shell-command)
  - [Paste (`paste`)](#paste-paste)
  - [Tab create (`tab_create`)](#tab-create-tab_create)
  - [Tab switch (`tab_switch`)](#tab-switch-tab_switch)
  - [Quit (`quit`)](#quit-quit)
  - [Arrow (`arrow`)](#arrow-arrow)
- [New commands](#new-commands)
  - [Parent arrow (`parent_arrow`)](#parent-arrow-parent_arrow)
  - [Archive (`archive`)](#archive-archive)
  - [Editor (`editor`)](#editor-editor)
  - [Pager (`pager`)](#pager-pager)
- [Usage](#usage)
  - [Using the `extract` command as an opener](#using-the-extract-command-as-an-opener)
  - [Full configuration example](#full-configuration-example)
- [Licence](#licence)

## Requirements

- [Yazi][yazi-link] v25.4.8+
- [`7z` or `7zz` command][7z-link]
- [`file` command][file-command-link]

### Optional dependencies

- [`tar` command][gnu-tar-link] for the `preserve_file_permissions` option

## Installation

```sh
# Add the plugin
ya pack -a hankertrix/augment-command

# Install plugin
ya pack -i

# Update plugin
ya pack -u
```

## Configuration

| Configuration                       | Values                                                    | Default   | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ----------------------------------- | --------------------------------------------------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `prompt`                            | `true` or `false`                                         | `false`   | Create a prompt to choose between hovered and selected items when both exist. If this option is disabled, selected items will only be operated on when the hovered item is selected, otherwise the hovered item will be the default item that is operated on.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `default_item_group_for_prompt`     | `hovered`, `selected` or `none`                           | `hovered` | The default item group to operate on when the prompt is submitted without any value. This only takes effect if `prompt` is set to `true`, otherwise this option doesn't do anything. `hovered` means the hovered item is operated on, `selected` means the selected items are operated on, and `none` just cancels the operation.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `smart_enter`                       | `true` or `false`                                         | `true`    | Use one command to open files or enter a directory. With this option set, the `enter` and `open` commands will both call the `enter` command when a directory is hovered and call the `open` command when a regular file is hovered. You can also enable this behaviour by passing the `--smart` flag to the `enter` or `open` commands.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `smart_paste`                       | `true` or `false`                                         | `false`   | Paste items into a directory without entering it. The behaviour is exactly the same as the [smart paste tip on Yazi's documentation][smart-paste-tip]. Setting this option to `false` will use the default `paste` behaviour. You can also enable this behaviour by passing the `--smart` flag to the `paste` command.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `smart_tab_create`                  | `true` or `false`                                         | `false`   | Create tabs in the directory that is being hovered instead of the current directory. The behaviour is exactly the same as the [smart tab tip on Yazi's documentation][smart-tab-tip]. Setting this option to `false` will use the default `tab_create` behaviour, which means you need to pass the `--current` flag to the command. You can also enable this behaviour by passing the `--smart` flag to the `tab_create` command.                                                                                                                                                                                                                                                                                                                                                                                                 |
| `smart_tab_switch`                  | `true` or `false`                                         | `false`   | If the tab that is being switched to does not exist yet, setting this option to `true` will create all the tabs in between the current number of open tabs, and the tab that is being switched to. The behaviour is exactly the same as the [smart switch tip on Yazi's documentation][smart-switch-tip]. Setting this option to `false` will use the default `tab_switch` behaviour. You can also enable this behaviour by passing the `--smart` flag to the `tab_switch` command.                                                                                                                                                                                                                                                                                                                                               |
| `confirm_on_quit`                   | `true` or `false`                                         | `true`    | Setting this option to `true` will cause Yazi to prompt you for a confirmation before quitting when there is more than 1 tab open. Setting this option to `false` will use the default `quit` behaviour, which is to immediately quit Yazi. You can also enable this behaviour by passing the `--confirm` flag to the `quit` command.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `open_file_after_creation`          | `true` or `false`                                         | `false`   | This option determines whether the plugin will open a file after it has been created. Setting this option to `true` will cause the plugin to open the created file. You can also enable this behaviour by passing the `--open` flag to the `create` command.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `enter_directory_after_creation`    | `true` or `false`                                         | `false`   | This option determines whether the plugin will enter a directory after it has been created. Setting this option to `true` will cause the plugin to enter the created directory. You can also enable this behaviour by passing the `--enter` flag to the `create` command.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `use_default_create_behaviour`      | `true` or `false`                                         | `false`   | This option determines whether the plugin will use the behaviour of Yazi's `create` command. Setting this option to `true` will use the behaviour of Yazi's `create` command. You can also enable this behaviour by passing the `--default-behaviour` flag to the `create` command.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `enter_archives`                    | `true` or `false`                                         | `true`    | Automatically extract and enter archive files. This option requires the [`7z` or `7zz` command][7z-link] to be present.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `extract_retries`                   | An integer, like `1`, `3`, `10`, etc.                     | `3`       | This option determines how many times the plugin will retry opening an encrypted or password-protected archive when a wrong password is given. This value plus 1 is the total number of times the plugin will try opening an encrypted or password-protected archive.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `recursively_extract_archives`      | `true` or `false`                                         | `true`    | This option determines whether the plugin will extract all archives inside an archive file recursively. If this option is set to `false`, archive files inside an archive will not be extracted, and you will have to manually extract them yourself.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `preserve_file_permissions`         | `true` or `false`                                         | `false`   | This option determines whether to preserve the file permissions of the items in the extracted archive. Setting this option to `true` will preserve the file permissions of the extracted items. It requires the [`tar` command][gnu-tar-link] and will only work on `tar` archives, or tarballs, as [`7z`][7z-link] does not support preserving file permissions. You will receive a warning if you have this option set but [`tar`][gnu-tar-link] is not installed. Do note that there are significant security implications of setting this option to `true`, as any executable file or binary in an archive can be immediately executed after it is extracted, which can compromise your system if you extract a malicious archive. As such, the default value is `false`, and it is strongly recommended to leave it as such. |
| `encrypt_archives`                  | `true` or `false`                                         | `false`   | This option determines whether the plugin will encrypt the archives it creates. If this option is set to `true`, the plugin will prompt for the archive password when creating an archive to encrypt it with. The plugin will prompt twice for the password, and will check both of them to see if they match. If they do, the password entered is set as the archive password. Otherwise, the plugin will show an error stating the passwords do not match, and prompt for two passwords again. Cancelling either of the prompts will cancel the whole process.                                                                                                                                                                                                                                                                  |
| `encrypt_archive_headers`           | `true` or `false`                                         | `false`   | This option determines whether the plugin will encrypt the headers of the archives it creates. If this option is set to `true`, the plugin will encrypt the headers of all `7z` archives, which means the file list cannot be previewed and Yazi will not be able to preview the contents of the archive. This encryption is only available to `7z` archives, so the plugin will show a warning message when this option is used, but the selected archive file type, does not support header encryption, like a `zip` archive, but will continue with the creation of the encrypted archive. This option has no effect when the archive is not encrypted, which is when `encrypt_archives` is set to `false`.                                                                                                                    |
| `reveal_created_archive`            | `true` or `false`                                         | `true`    | This option determines whether the plugin will automatically hover over the created archive once created.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `remove_archived_files`             | `true` or `false`                                         | `false`   | This option determines whether the plugin will automatically remove the files that were added to the created archive.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `must_have_hovered_item`            | `true` or `false`                                         | `true`    | This option stops the plugin from executing any commands when there is no hovered item.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `skip_single_subdirectory_on_enter` | `true` or `false`                                         | `true`    | Skip directories when there is only one subdirectory and no other files when entering directories. This behaviour can be turned off by passing the `--no-skip` flag to the `enter` or `open` commands.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `skip_single_subdirectory_on_leave` | `true` or `false`                                         | `true`    | Skip directories when there is only one subdirectory and no other files when leaving directories. This behaviour can be turned off by passing the `--no-skip` flag to the `leave` command.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `smooth_scrolling`                  | `true` or `false`                                         | `false`   | Self-explanatory, this option enables smooth scrolling.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `scroll_delay`                      | A floating point number, like `0.02`, `0.05`, `0.1`, etc. | `0.02`    | The delay, in seconds, between each call of the `arrow` command to scroll through the file list. The smaller the `scroll_delay`, the faster the file list is scrolled. Avoid setting a `scroll_delay` that is more than `1` second. This is due to the plugin being asynchronous, which will result in the plugin continuing to call the `arrow` command even when the directory has changed, or when you are in a different application that doesn't block Yazi, resulting in unexpected behaviour.                                                                                                                                                                                                                                                                                                                              |
| `wraparound_file_navigation`        | `true` or `false`                                         | `true`    | Wrap around from the bottom to the top or from the top to the bottom when using the `arrow` or `parent_arrow` command to navigate.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |

If you would like to use the default configuration, which is shown below,
you don't need to add anything to your `~/.config/yazi/init.lua`
file on Linux and macOS, or your `%AppData%\yazi\config\init.lua`
file on Windows.

```lua
-- ~/.config/yazi/init.lua for Linux and macOS
-- %AppData%\yazi\config\init.lua for Windows

-- Using the default configuration
require("augment-command"):setup({
    prompt = false,
    default_item_group_for_prompt = "hovered",
    smart_enter = true,
    smart_paste = false,
    smart_tab_create = false,
    smart_tab_switch = false,
    confirm_on_quit = true,
    open_file_after_creation = false,
    enter_directory_after_creation = false,
    use_default_create_behaviour = false,
    enter_archives = true,
    extract_retries = 3,
    recursively_extract_archives = true,
    preserve_file_permissions = false,
    encrypt_archives = false,
    encrypt_archive_headers = false,
    reveal_created_archive = true,
    remove_archived_files = false,
    must_have_hovered_item = true,
    skip_single_subdirectory_on_enter = true,
    skip_single_subdirectory_on_leave = true,
    smooth_scrolling = false,
    scroll_delay = 0.02,
    wraparound_file_navigation = true,
})
```

However, if you would like to configure the plugin, you can add
your desired configuration options to your `~/.config/yazi/init.lua` file
on Linux and macOS, or your
`%AppData%\yazi\config\init.lua` file on Windows.
You can leave out configuration options that you would
like to be left as default.
An example configuration is shown below:

```lua
-- ~/.config/yazi/init.lua for Linux and macOS
-- %AppData%\yazi\config\init.lua for Windows

-- Custom configuration
require("augment-command"):setup({
    prompt = true,
    default_item_group_for_prompt = "none",
    open_file_after_creation = true,
    enter_directory_after_creation = true,
    extract_retries = 5,
    encrypt_archives = true,
    smooth_scrolling = true,
    wraparound_file_navigation = false,
})
```

## What about the commands are augmented?

All commands that can operate on multiple files and directories,
like `open`, `rename`, `remove` and `shell`,
as well as the new commands `extract`, `archive`,
`editor` and `pager`,
now determine an item group to operate on.
By default, the command will operate on the hovered item,
unless the hovered item is also selected,
then it will operate on the selected items.

- When `must_have_hovered_item` is set to `true`,
  having no hovered item means the plugin will cancel the operation.
- When `must_have_hovered_item` is set to `false` and
  there are selected items, the selected items will be operated on.
- With `prompt` is set to `true`,
  the plugin will always prompt you to
  choose an item group when there are
  both selected items and a hovered item.

## Augmented commands

### Open (`open`)

- The `open` command is augmented as stated in
  [this section above][augment-section].

  Videos:

  - When `prompt` is set to `true`:

    [open-prompt-video]

  - When `prompt` is set to `false`:

    [open-behaviour-video]

- When `smart_enter` is set to `true`,
  it calls the `enter` command when the hovered item is a directory.
- `--smart` flag to use one command to `open` files
  and `enter` directories.
  This flag will cause the `open` command to call
  the `enter` command when the hovered item is a directory
  even when `smart_enter` is set to `false`.
  This allows you to set a key to use this behaviour
  with the `open` command instead of using it for
  every `open` command.

  Video:

  [smart-enter-video]

- `--no-skip` flag, which only applies
  when `smart_enter` is used as it is passed to the `enter` command.
  More details about this flag can be found at the documentation
  for the [enter command](#enter-enter).
- Automatically extracts and enters archive files,
  with support for skipping directories
  that contain only one subdirectory in the extracted archive.
  This can be disabled by setting `enter_archives` to `false`
  in the configuration.
  This feature requires the
  [`7z` or `7zz` command][7z-link]
  to be present to extract the archives.

  Video:

  [open-auto-extract-archives-video]

- The `open` command makes use of the `extract` command,
  so recursively extracting archives is also supported.
  For more information, look at the section about the
  [`extract` command](#extract-extract).

  Video:

  [open-recursively-extract-archives-video]

### Extract (`extract`)

- Technically this is a new command,
  as Yazi does not provide an `extract` command.
  However, Yazi does provide a built-in plugin called `extract`,
  so this command is included in the
  [augmented commands section](#augmented-commands) instead of the
  [new commands section](#new-commands).
- This command requires the [`7z` or `7zz` command][7z-link] to
  be present to extract the archives, as well as the
  [`file` command][file-command-link] to check if a file is an archive or not.
- You are not meant to use this command directly.
  However, you can do so if you like,
  as the extract command is also augmented as stated in
  [this section above][augment-section].

  Videos:

  - When `must_have_hovered_item` is `true`:

    [extract-must-have-hovered-item-video]

  - When `must_have_hovered_item` is `false`:

    [extract-hovered-item-optional-video]

  - When `prompt` is set to `true`:

    [extract-prompt-video]

  - When `prompt` is set to `false`:

    [extract-behaviour-video]

- Instead, this command is intended to replace the
  built-in `extract` plugin, which is used for the `extract` opener.
  This way, you can use the
  features that come with the augmented `extract` command, like
  recursively extracting archives, with the `open` command.
  This is the intended way to use this command,
  as the `open` command is meant to be the command
  that opens everything, so it is a bit counterintuitive
  to have to use a separate key to extract archives.

  To replace the built-in `extract` plugin, copy the
  [`extract` openers section][yazi-yazi-toml-extract-openers]
  in [Yazi's default `yazi.toml`][yazi-yazi-toml] into your `yazi.toml`,
  which is located at `~/.config/yazi/yazi.toml` for Linux and macOS,
  and `%AppData%\yazi\config\yazi.toml` file on Windows.
  Make sure that the `extract` openers are
  under the `opener` key in your `yazi.toml`.
  Then replace `extract` with `augmented-extract`,
  and you will be using the plugin's `extract` command instead of
  Yazi's built-in `extract` plugin.

  Here is an example configuration:

  ```toml
  # ~/.config/yazi/yazi.toml for Linux and macOS
  # %AppData%\yazi\config\yazi.toml for Windows

  [opener]
  extract = [
      { run = 'ya pub augmented-extract --list "$@"', desc = "Extract here", for = "unix" },
      { run = 'ya pub augmented-extract --list %*',   desc = "Extract here", for = "windows" },
  ]
  ```

  If that exceeds your editor's line length limit,
  another way to do it is:

  ```toml
  # ~/.config/yazi/yazi.toml for Linux and macOS
  # %AppData%\yazi\config\yazi.toml for Windows

  [[opener.extract]]
  run = 'ya pub augmented-extract --list "$@"'
  desc = "Extract here"
  for = "unix"

  [[opener.extract]]
  run = 'ya pub augmented-extract --list %*'
  desc = "Extract here"
  for = "windows"
  ```

- The `extract` command supports recursively extracting archives,
  which means if the extracted archive file contains other archive
  files in it, those archives will be automatically
  extracted, keeping the directory structure
  of the archive if the archive doesn't
  only contain a single archive file.
  This feature requires the
  [`file` command][file-command-link]
  to detect the mime type of the extracted file,
  and to check whether it is an archive file or not.
  This makes extracting binaries from
  compressed tarballs much easier, as there's no need
  to press a key twice to decompress and extract
  the compressed tarballs.
  You can disable this feature by setting
  `recursively_extract_archives` to `false`
  in the configuration.

  Video:

  [extract-recursively-extract-archives-video]

- The `extract` command also supports extracting encrypted archives,
  and will prompt you for a password when it encounters an encrypted
  archive. You can configure the number of times the plugin prompts
  you for a password by setting the `extract_retries` configuration
  option. The default value is `3`, which means the plugin will
  prompt you `3` more times for the correct password after the
  initial password attempt before giving up and showing an error.

  Video:

  [extract-encrypted-archive-video]

- The `preserve_file_permissions` configuration option applies to
  the `extract` command, and requires the [`tar` command][gnu-tar-link]
  to be present, as [`7z`][7z-link] does not support preserving
  file permissions. The plugin will show a warning if the
  `preserve_file_permissions` option is set to `true` but
  [`tar`][gnu-tar-link] is not installed.

  For macOS users, it is highly recommended to install and use
  [GNU `tar`, or `gtar`][gnu-tar-link] instead of the
  [Apple provided `tar` command][apple-tar-link].
  You can install it using the [`brew`][brew-link] command below:

  ```sh
  brew install gnu-tar
  ```

  The plugin will automatically use [GNU `tar`][gnu-tar-link]
  if it finds the [`gtar` command][gnu-tar-link] instead
  of the [Apple provided `tar` command][apple-tar-link].

  Setting the `preserve_file_permissions` configuration
  option to `true` will preserve the file permissions
  of the files contained in a `tar` archive or tarball.

  This has considerable security implications,
  as executables extracted from
  all `tar` archives can be immediately executed on your system,
  possibly compromising your system if you extract a
  malicious `tar` archive.
  Hence, this option is set to `false` by default,
  and should be left as such.
  This option is provided for your convenience,
  but do seriously consider if such convenience
  is worth the risk of extracting a malicious `tar` archive
  that executes malware on your system.

- `--reveal` flag to automatically hover the files
  that have been extracted.

  Video:

  [extract-reveal-extracted-item-video]

- `--remove` flag to automatically remove the archive
  after the files have been extracted.

  Video:

  [extract-remove-extracted-archive-video]

### Enter (`enter`)

- When `smart_enter` is set to `true`,
  it calls the `open` command when the hovered item is a file.
- `--smart` flag to use one command to `enter`
  directories and `open` files. This flag will cause
  the `enter` command to call the `open` command when
  the selected items or the hovered item is a file,
  even when `smart_enter` is set to `false`.
  This allows you to set a key to use this behaviour
  with the `enter` command instead of using it for
  every `enter` command.

  Video:

  [smart-enter-video]

- Automatically skips directories that
  contain only one subdirectory when entering directories.
  This can be turned off by setting
  `skip_single_subdirectory_on_enter` to `false` in the configuration.

  Video:

  [enter-skip-single-subdirectory-video]

- `--no-skip` flag. It stops the plugin from skipping directories
  that contain only one subdirectory when entering directories,
  even when `skip_single_subdirectory_on_enter` is set to `true`.
  This allows you to set a key to navigate into directories
  without skipping the directories that contain only one subdirectory.

### Leave (`leave`)

- Automatically skips directories that
  contain only one subdirectory when leaving directories.
  This can be turned off by
  setting `skip_single_subdirectory_on_leave` to `false`
  in the configuration.

  Video:

  [leave-skip-single-subdirectory-video]

- `--no-skip` flag. It stops the plugin
  from skipping directories that contain only one subdirectory,
  even when `skip_single_subdirectory_on_leave` is set to `true`.
  This allows you to set a key to navigate out of directories
  without skipping the directories that contain only one subdirectory.

### Rename (`rename`)

- The `rename` command is augmented as stated in
  [this section above][augment-section].

  Videos:

  - When `must_have_hovered_item` is `true`:

    [rename-must-have-hovered-item-video]

  - When `must_have_hovered_item` is `false`:

    [rename-hovered-item-optional-video]

  - When `prompt` is set to `true`:

    [rename-prompt-video]

  - When `prompt` is set to `false`:

    [rename-behaviour-video]

### Remove (`remove`)

- The `remove` command is augmented as stated in
  [this section above][augment-section].

  Videos:

  - When `must_have_hovered_item` is `true`:

    [remove-must-have-hovered-item-video]

  - When `must_have_hovered_item` is `false`:

    [remove-hovered-item-optional-video]

  - When `prompt` is set to `true`:

    [remove-prompt-video]

  - When `prompt` is set to `false`:

    [remove-behaviour-video]

### Create (`create`)

- You should use Yazi's default `create` command instead
  of this augmented `create` command if you
  don't want the paths without file extensions to be created
  as directories by default, and you don't care about automatically
  opening and entering the created file and directory respectively.
- The `create` command has a different behaviour from
  Yazi's `create` command.
  When the path given to the command doesn't have a file extension,
  the `create` command will create a directory instead of a file,
  unlike Yazi's `create` command. Other that this major difference,
  the `create` command functions identically
  to Yazi's `create` command,
  which means that you can use a trailing `/` on Linux and macOS,
  or `\` on Windows to create a directory. It will also recursively
  create directories to ensure that the path given exists.
  It also supports all the options supported
  by Yazi's `create` command,
  so you can pass them to the command and expect the same behaviour.
- The rationale for this behaviour is that creating a path without
  a file extension usually means you intend to
  create a directory instead of a file,
  as files usually have file extensions.

  Video:

  [create-behaviour-video]

- When `open_file_after_creation` is set to `true`,
  the `create` command will `open` the created file.
  This behaviour can also be enabled by
  passing the `--open` flag to the `create` command.

  Video:

  [create-and-open-files-video]

  Likewise, when `enter_directory_after_creation` is set to `true`,
  the `create` command will `enter` the created directory.
  This behaviour can also be enabled by passing the `--enter` flag
  to the `create` command.

  Video:

  [create-and-enter-directories-video]

  To enable both behaviours with flags, just pass both the
  `--open` flag and the `--enter` flag to the `create` command.

  Video:

  [create-and-open-files-and-directories-video]

- If you would like to use the behaviour of Yazi's `create` command,
  probably because you would like to automatically open
  and enter the created file and directory respectively,
  you can either set
  `use_default_create_behaviour` to `true`,
  or pass the `--default-behaviour` flag to the `create` command.

  Video:

  [create-default-behaviour-video]

### Shell (`shell`)

- This command runs the shell command given with the augment stated in
  [this section above][augment-section]. You should
  only use this command if you need the plugin to determine a suitable
  item group for the command to operate on. Otherwise, you should just
  use the default `shell` command provided by Yazi.

  Videos:

  - When `must_have_hovered_item` is `true`:

    [shell-must-have-hovered-item-video]

  - When `must_have_hovered_item` is `false`:

    [shell-hovered-item-optional-video]

  - When `prompt` is set to `true`:

    [shell-prompt-video]

  - When `prompt` is set to `false`:

    [shell-behaviour-video]

- To use this command, the syntax is exactly the same as the default
  `shell` command provided by Yazi. You just provide
  the command you want and provide any Yazi shell variable,
  which is documented [here][yazi-shell-variables].
  The plugin will automatically replace the shell variable you give
  with the file paths for the item group before executing the command.

- There is no need to quote the shell variable on Linux and macOS,
  as it is expanded by the plugin instead of the shell,
  and the paths are already quoted using the `ya.quote` function
  before execution, so quoting is entirely unnecessary
  and may result in unexpected behaviour.

- `--exit-if-dir` flag to stop the shell command given
  from executing if the item group consists only of directories.
  For example, if the item group is the hovered item, then
  the shell command will not be executed if the hovered item
  is a directory. If the item group is the selected items group,
  then the shell command will not be executed if **all**
  the selected items are directories. This behaviour comes
  from it being used in the `pager` command.
  The `pager` command is essentially:

  ```toml
  # ~/.config/yazi/keymap.toml on Linux and macOS
  # %AppData%\yazi\config\keymap.toml on Windows

  [[manager.prepend_keymap]]
  on = "i"
  run = "plugin augment-command -- shell '$PAGER $@' --block --exit-if-dir"
  desc = "Open the pager"
  ```

  It is also used in the `editor` command,
  since you usually wouldn't use
  your text editor to open directories,
  especially if you are already using
  a terminal file manager like [Yazi][yazi-link].
  The `editor` command is essentially:

  ```toml
  # ~/.config/yazi/keymap.toml on Linux and macOS
  # %AppData%\yazi\config\keymap.toml on Windows

  [[manager.prepend_keymap]]
  on = "o"
  run = "plugin augment-command -- shell '$EDITOR $@' --block --exit-if-dir"
  desc = "Open the editor"
  ```

  Video:

  [shell-exit-if-directory-video]

#### Passing arguments to the `shell` command

Ideally, you will want to avoid using backslashes to escape
the shell command arguments, so here are a few ways to do it:

1. Shell arguments that don't have special shell variables
   on Linux and macOS, like `$SHELL`, or don't have
   special shell characters like `>`, `|` or spaces,
   need not be quoted with double quotes `"`
   or single quotes `'` respectively.
   For example:

   ```toml
   # ~/.config/yazi/keymap.toml on Linux and macOS
   # %AppData%\yazi\config\keymap.toml on Windows
   [[manager.prepend_keymap]]
   on = "i"
   run = "plugin augment-command -- shell --block 'bat -p --pager less $@'"
   desc = "Open with bat"
   ```

   Even though the `$@` argument above is considered
   a shell variable in Linux and macOS,
   the plugin automatically replaces it with the full path
   of the items in the item group,
   so it does not need to be quoted with
   double quotes `"`, as it is expanded by the plugin,
   and not meant to be expanded by the shell.

2. If the arguments to the `shell` command have special
   shell variables on Linux and macOS, like `$SHELL`,
   or special shell characters like `>`, `|`, or spaces,
   use `--` to denote the end of the flags and options
   passed to the `shell` command.
   For example:

   ```toml
   # ~/.config/yazi/keymap.toml on Linux and macOS
   # %AppData%\yazi\config\keymap.toml on Windows
   [[manager.prepend_keymap]]
   on = "<C-s>"
   run = 'plugin augment-command -- shell --block -- sh -c "$SHELL"'
   desc = "Open a shell inside of a shell here"
   ```

   ```toml
   # ~/.config/yazi/keymap.toml on Linux and macOS
   # %AppData%\yazi\config\keymap.toml on Windows
   [[manager.prepend_keymap]]
   on = "<C-s>"
   run = "plugin augment-command -- shell --block -- sh -c 'echo hello'"
   desc = "Open a shell and say hello inside the opened shell"
   ```

3. If the arguments passed to the `shell` command themselves
   contain arguments that have special shell variables on
   Linux and macOS, like `$SHELL`, or special shell characters
   like `>`, `|`, or spaces, use the triple single quote
   `'''` delimiter for the `run` string.

   ```toml
   # ~/.config/yazi/keymap.toml on Linux and macOS
   # %AppData%\yazi\config\keymap.toml on Windows
   [[manager.prepend_keymap]]
   on = "<C-s>"
   run = '''plugin augment-command -- shell --block -- sh -c 'sh -c "$SHELL"''''
   desc = "Open a shell inside of a shell inside of a shell here"
   ```

   ```toml
   # ~/.config/yazi/keymap.toml on Linux and macOS
   # %AppData%\yazi\config\keymap.toml on Windows
   [[manager.prepend_keymap]]
   on = "<C-s>"
   run = '''plugin augment-command --
       shell --block -- sh -c "$SHELL -c 'echo hello'"
   '''
   desc = "Open a shell inside of a shell and say hello inside the opened shell"
   ```

   A more legitimate use case for this would be something like
   [Yazi's tip to email files using Mozilla Thunderbird][thunderbird-tip]:

   ```toml
   # ~/.config/yazi/keymap.toml on Linux and macOS
   # %AppData%\yazi\config\keymap.toml on Windows
   [[manager.prepend_keymap]]
   on = "<C-e>"
   run = '''plugin augment-command --
       shell --
           paths=$(for p in $@; do echo "$p"; done | paste -s -d,)
           thunderbird -compose "attachment='$paths'"
   '''
   desc = "Email files using Mozilla Thunderbird"
   ```

   Once again, the `$@` variable above does not need to be quoted
   in double quotes `"` as it is expanded by the plugin
   instead of the shell.

If the above few methods to avoid using backslashes
within your shell command to escape the quotes are
still insufficient for your use case,
it is probably more appropriate to write a shell script
in a separate file and execute that instead of
writing the shell command inline
in your `keymap.toml` file.

### Paste (`paste`)

- When `smart_paste` is set to `true`,
  the `paste` command will paste items
  into the hovered directory without entering it.
  If the hovered item is not a directory,
  the command pastes in the current directory instead.
  Otherwise, when `smart_paste` is set to `false`,
  the `paste` command will behave like the default
  `paste` command.
- `--smart` flag to enable pasting in the hovered directory
  without entering the directory.
  This flag will cause the `paste` command to paste items
  into the hovered directory even
  when `smart_paste` is set to `false`.
  This allows you to set a key to use this behaviour
  with the `paste` command instead of using it for
  every `paste` command.

  Video:

  [smart-paste-video]

### Tab create (`tab_create`)

- When `smart_tab_create` is set to `true`,
  the `tab_create` command will create a tab
  in the hovered directory instead of the
  current directory like the default key binds.
  If the hovered item is not a directory,
  then the command just creates a new tab in
  the current directory instead.
  Otherwise, when `smart_tab_create` is set to
  `false`, the `tab_create` command will behave
  like the default key bind to create a tab,
  which is `tab_create --current`.
- `--smart` flag to enable creating a tab
  in the hovered directory.
  This flag will cause the `tab_create` command
  to create a tab in the hovered directory even
  when `smart_tab_create` is set to `false`.
  This allows you to set a specific key to use this
  behaviour with the `tab_create` command instead
  of using it for every `tab_create` command.

  Video:

  [smart-tab-create-video]

### Tab switch (`tab_switch`)

- When `smart_tab_switch` is set to `true`,
  the `tab_switch` command will ensure that
  the tab that is being switched to exist.
  It does this by automatically creating
  all the tabs required for the desired
  tab to exist.
  For example, if you are switching to
  tab 5 (`tab_switch 4`), and you only have
  two tabs currently open (tabs 1 and 2),
  the plugin will create tabs 3, 4 and 5
  and then switch to tab 5.
  The tabs are created using the current
  directory. The `smart_tab_create`
  configuration option does not affect
  the behaviour of this command.
  Otherwise, when `smart_tab_switch` is
  set to `false`, the `tab_switch` command
  will behave like the default `tab_switch`
  command, and simply switch to the tab
  if it exists, and do nothing if it doesn't
  exist.
- `--smart` flag to automatically create
  the required tabs for the desired tab
  to exist.
  This flag will cause the `tab_switch`
  command to automatically create the
  required tabs even when `smart_tab_switch`
  is set to `false`.
  This allows you to set a specific key to use this
  behaviour with the `tab_switch` command instead
  of using it for every `tab_switch` command.

  Video:

  [smart-tab-switch-video]

### Quit (`quit`)

- You should use Yazi's default `quit` command instead of this
  augmented command if you don't want to have a prompt
  when quitting Yazi with multiple tabs open.
  This command has a visual side effect of showing a
  confirmation prompt for a split second before closing Yazi
  when quitting Yazi with only 1 tab open,
  which can be annoying.
  This confirmation prompt is due to the plugin still running
  for a bit after the `quit` command is emitted,
  causing Yazi to prompt you for
  confirmation as there are tasks still running.
  However, once the plugin has stopped running,
  which is a split second after the `quit` command is emitted,
  Yazi will exit.
  You can observe this visual effect in the video demonstration below.
- When `confirm_on_quit` is set to `true`,
  the plugin will prompt you for
  confirmation when there is more than 1 tab open.
  Otherwise, it will immediately quit Yazi,
  just like the default `quit` command.
- `--confirm` flag to get the plugin to prompt you
  for confirmation when quitting with multiple tabs open.
  This flag will cause the `quit` command to
  prompt you for confirmation when quitting with multiple tabs open
  even when `confirm_on_quit` is set to `false`.
  This allows you to set a specific key to use this behaviour with the
  `quit` command instead of using it for every `quit` command.

  Video:

  [quit-with-confirmation-video]

### Arrow (`arrow`)

- When `smooth_scrolling` is set to `true`, the arrow command will
  smoothly scroll through the file list.

  Video:

  [smooth-arrow-video]

- When `wraparound_file_navigation` is set to `true`,
  the arrow command will wrap around from the bottom to the top or
  from the top to the bottom when navigating.

  Video:

  [wraparound-arrow-video]

- When both `smooth_scrolling` and `wraparound_file_navigation`
  are set to `true`,
  the command will smoothly scroll the wraparound transition as well.

  Video:

  [smooth-wraparound-arrow-video]

- Otherwise, it'll behave like the default `arrow 1` command.
- `--no-wrap` flag to prevent the `arrow` command
  from wrapping around,
  even when `wraparound_file_navigation` is set to `true`.

## New commands

### Parent arrow (`parent_arrow`)

- This command behaves like the `arrow` command,
  but in the parent directory.
  It allows you to navigate in the parent directory
  without leaving the current directory.

  Video:

  [parent-arrow-video]

- When `smooth_scrolling` is set to `true`, this command will
  smoothly scroll through the parent directories.

  Video:

  [smooth-parent-arrow-video]

- When `wraparound_file_navigation` is set to `true`,
  this command will also wrap around from the bottom to the top or
  from top to the bottom when navigating in the parent directory.

  Video:

  [wraparound-parent-arrow-video]

- When both `smooth_scrolling` and `wraparound_file_navigation`
  are set to `true`,
  the command will smoothly scroll the wraparound transition as well.

  Video:

  [smooth-wraparound-parent-arrow-video]

- You can also replicate this using this series of commands below,
  but it doesn't work as well,
  and doesn't support wraparound navigation or smooth scrolling:

  ```toml
  # ~/.config/yazi/keymap.toml on Linux and macOS
  # %AppData%\yazi\config\keymap.toml on Windows

  # Use K to move up in the parent directory
  [[manager.prepend_keymap]]
  on = "K"
  run = ["leave", "arrow -1", "enter"]
  desc = "Move up in the parent directory"


  # Use J to move down in the parent directory
  [[manager.prepend_keymap]]
  on = "J"
  run = ["leave", "arrow 1", "enter"]
  desc = "Move down in the parent directory"
  ```

- `--no-wrap` flag to prevent the `parent_arrow` command from
  wrapping around,
  even when `wraparound_file_navigation` is set to `true`.

### Archive (`archive`)

- The `archive` command adds the selected or hovered items
  to an archive, with the plugin prompting for an archive name.
  The archive file extension given will be used to determine
  the type of archive to create.
- This command is also augmented as stated in
  [this section above][augment-section].

  Videos:

  - When `must_have_hovered_item` is `true`:

    [archive-must-have-hovered-item-video]

  - When `must_have_hovered_item` is `false`:

    [archive-hovered-item-optional-video]

  - When `prompt` is set to `true`:

    [archive-prompt-video]

  - When `prompt` is set to `false`:

    [archive-behaviour-video]

- `--encrypt` flag to encrypt the archive with the given password,
  which applies even when `encrypt_archives` is set to `false`.
- `--encrypt-headers` flag to encrypt the archive headers,
  which applies even when `encrypt_archive_headers`
  is set to `false`.
  Note that this option only works with `7z` archives,
  other types of archives like `zip` archives
  do not support header encryption.
  The plugin will show a warning if the archive type
  does not support header encryption and the flag is passed,
  but will continue with the creation of the encrypted archive.
  This option has no effect if either `encrypt_archives`
  is set to `false` or the `--encrypt` flag isn't given.

  Video:

  [archive-encrypt-files-video]

- `--reveal` flag to automatically hover the archive file
  that is created, which applies even when
  `reveal_created_archive` is set to `false`.

  Video:

  [archive-reveal-created-archive-video]

- `--remove` flag to automatically remove the files
  that are added to the archive, which applies even when
  `remove_archived_files` is set to `false`.

  Video:

  [archive-remove-archived-files-video]

### Editor (`editor`)

- The `editor` command opens the default editor set by the
  `$EDITOR` environment variable.
- The command is also augmented as stated in
  [this section above][augment-section].

  Videos:

  - When `must_have_hovered_item` is `true`:

    [editor-must-have-hovered-item-video]

  - When `must_have_hovered_item` is `false`:

    [editor-hovered-item-optional-video]

  - When `prompt` is set to `true`:

    [editor-prompt-video]

  - When `prompt` is set to `false`:

    [editor-behaviour-video]

### Pager (`pager`)

- The `pager` command opens the default pager set by the
  `$PAGER` environment variable.
- The command is also augmented as stated in
  [this section above][augment-section].
- The `pager` command will also skip opening directories, as the pager
  cannot open directories and will error out.
  Hence, the command will not do anything when the hovered item
  is a directory, or if **all** the selected items are directories.
  This makes the pager command less annoying as it will not
  try to open a directory and then immediately fail with an error,
  causing a flash and causing Yazi to send a notification.

  Videos:

  - When `must_have_hovered_item` is `true`:

    [pager-must-have-hovered-item-video]

  - When `must_have_hovered_item` is `false`:

    [pager-hovered-item-optional-video]

  - When `prompt` is set to `true`:

    [pager-prompt-video]

  - When `prompt` is set to `false`:

    [pager-behaviour-video]

## Usage

Add the commands that you would like to use to your `keymap.toml` file,
located at `~/.config/yazi/keymap.toml` on Linux and macOS
and at `%AppData%\yazi\config\keymap.toml`
on Windows, in this format:

```toml
# ~/.config/yazi/keymap.toml on Linux and macOS
# %AppData%\yazi\config\keymap.toml on Windows

[[manager.prepend_keymap]]
on = "key"
run = "plugin augment-command -- command arguments --flags --options=42"
desc = "Description"
```

For example, to use the augmented `enter` command:

```toml
# ~/.config/yazi/keymap.toml on Linux and macOS
# %AppData%\yazi\config\keymap.toml on Windows

[[manager.prepend_keymap]]
on = "l"
run = "plugin augment-command -- enter"
desc = "Enter a directory and skip directories with only a single subdirectory"
```

All the default arguments, flags and options provided by Yazi
are also supported, for example:

```toml
# ~/.config/yazi/keymap.toml on Linux and macOS
# %AppData%\yazi\config\keymap.toml on Windows

[[manager.prepend_keymap]]
on = "k"
run = "plugin augment-command -- arrow -1"
desc = "Move cursor up"

[[manager.prepend_keymap]]
on = "r"
run = "plugin augment-command -- rename --cursor=before_ext"
desc = "Rename a file or directory"

[[manager.prepend_keymap]]
on = "D"
run = "plugin augment-command -- remove --permanently"
desc = "Permanently delete the files"

[[manager.prepend_keymap]]
on = ["g", "j"]
run = "plugin augment-command -- parent_arrow 1"
```

For the default descriptions of the commands, you can refer to
[Yazi's default `keymap.toml` file][yazi-keymap-toml].

Essentially, all you need to do to use this plugin
is to add `plugin augment-command --`, with a space at the end,
in front of a Yazi command, such as `enter`,
which results in `plugin augment-command -- enter'`.

### Using the `extract` command as an opener

This is the intended way to use the `extract` command instead of binding
the `extract` command to a key in your `keymap.toml` file.
Look at the [`extract` command section](#extract-extract)
for details on how to do so.

### Full configuration example

For a full configuration example,
you can have a look at [my `keymap.toml` file][my-keymap-toml]
and [my `yazi.toml` file][my-yazi-toml].

## [Licence]

This plugin is licenced under the [GNU AGPL v3 licence][Licence].
You can view the full licence in the [`LICENSE`][Licence] file.

<!-- Regular links -->

[yazi-link]: https://github.com/sxyazi/yazi
[yazi-tips-page]: https://yazi-rs.github.io/docs/tips
[smart-paste-tip]: https://yazi-rs.github.io/docs/tips#smart-paste
[smart-tab-tip]: https://yazi-rs.github.io/docs/tips#smart-tab
[smart-switch-tip]: https://yazi-rs.github.io/docs/tips#smart-switch
[augment-section]: #what-about-the-commands-are-augmented
[7z-link]: https://www.7-zip.org/
[file-command-link]: https://www.darwinsys.com/file/
[gnu-tar-link]: https://www.gnu.org/software/tar/
[apple-tar-link]: https://ss64.com/mac/tar.html
[brew-link]: https://brew.sh/
[yazi-yazi-toml-extract-openers]: https://github.com/sxyazi/yazi/blob/main/yazi-config/preset/yazi-default.toml#L51-L54
[yazi-yazi-toml]: https://github.com/sxyazi/yazi/blob/main/yazi-config/preset/yazi-default.toml
[yazi-shell-variables]: https://yazi-rs.github.io/docs/configuration/keymap/#manager.shell
[thunderbird-tip]: https://yazi-rs.github.io/docs/tips#email-selected-files-using-thunderbird
[yazi-keymap-toml]: https://github.com/sxyazi/yazi/blob/main/yazi-config/preset/keymap-default.toml
[my-keymap-toml]: https://github.com/hankertrix/Dotfiles/blob/main/.config/yazi/keymap.toml
[my-yazi-toml]: https://github.com/hankertrix/Dotfiles/blob/main/.config/yazi/yazi.toml
[Licence]: LICENSE

<!-- Videos -->

<!-- Open command -->

[open-prompt-video]: https://github.com/user-attachments/assets/624da7a1-99cc-428d-acbb-d4ce684f92cb
[open-behaviour-video]: https://github.com/user-attachments/assets/202f1c07-2001-49d7-a9d7-7a4e7b102c41
[open-auto-extract-archives-video]: https://github.com/user-attachments/assets/dad0572e-15d7-4dfd-bf48-00851af66b6e
[open-recursively-extract-archives-video]: https://github.com/user-attachments/assets/b8e929ce-32cd-4f7e-ad97-ffe94bdacd71

<!-- Extract command -->

[extract-must-have-hovered-item-video]: https://github.com/user-attachments/assets/6b9f347f-34ce-4ca1-8e3a-24dbeb297dc7
[extract-hovered-item-optional-video]: https://github.com/user-attachments/assets/1596f9f8-e0f5-49e3-964c-6f94b1c24055
[extract-prompt-video]: https://github.com/user-attachments/assets/568aef53-dc90-420e-ada9-171f56388ee1
[extract-behaviour-video]: https://github.com/user-attachments/assets/d6ebf5fb-45d3-4ae0-adab-3e89b1ec2f4e
[extract-recursively-extract-archives-video]: https://github.com/user-attachments/assets/d8978671-9149-45b7-9a92-21c1697baa7d
[extract-encrypted-archive-video]: https://github.com/user-attachments/assets/24701662-0c19-4478-b576-75d9284cd695
[extract-reveal-extracted-item-video]: https://github.com/user-attachments/assets/170bf187-dc2a-4310-aa86-5dc9a864aced
[extract-remove-extracted-archive-video]: https://github.com/user-attachments/assets/9b2e625a-a7f8-4678-8a26-265a7d3b8e0c

<!-- Enter command -->

[smart-enter-video]: https://github.com/user-attachments/assets/be950544-a58f-495a-a7e8-e37e99011070
[enter-skip-single-subdirectory-video]: https://github.com/user-attachments/assets/1bd30cb0-611a-44f2-9839-968287af4455

<!-- Leave command -->

[leave-skip-single-subdirectory-video]: https://github.com/user-attachments/assets/735de8f7-6abb-4929-8e3d-bba470fc6063

<!-- Rename command -->

[rename-must-have-hovered-item-video]: https://github.com/user-attachments/assets/b0f608df-7e8d-4e5f-958f-b3df9d0a92fa
[rename-hovered-item-optional-video]: https://github.com/user-attachments/assets/9613d238-d8e3-4e6f-b073-f847a4f331a1
[rename-prompt-video]: https://github.com/user-attachments/assets/6ad26e1b-dab1-4e8e-92af-bfcbf6c5232c
[rename-behaviour-video]: https://github.com/user-attachments/assets/fdd70919-f164-4676-9046-6a4b95cd86ed

<!-- Remove command -->

[remove-must-have-hovered-item-video]: https://github.com/user-attachments/assets/fa0aeb4e-ee6a-4e34-9c6f-4d4bc0afd111
[remove-hovered-item-optional-video]: https://github.com/user-attachments/assets/f42167dc-df59-451d-b26b-16e75be93fad
[remove-prompt-video]: https://github.com/user-attachments/assets/dd901db3-1ab4-4cb7-bb3f-8aec335c7b94
[remove-behaviour-video]: https://github.com/user-attachments/assets/d4087826-3480-486d-98ff-708bca548270

<!-- Create command -->

[create-and-enter-directories-video]: https://github.com/user-attachments/assets/0604e9a3-7c23-4e9c-963a-6e83955fe7ae
[create-and-open-files-video]: https://github.com/user-attachments/assets/2feee5e5-1d56-4150-8f08-101338392950
[create-and-open-files-and-directories-video]: https://github.com/user-attachments/assets/629a6923-6fa5-4b85-93b7-3b5495c8bbbb
[create-behaviour-video]: https://github.com/user-attachments/assets/55b485ea-e49e-4629-b077-4f2a81031f38
[create-default-behaviour-video]: https://github.com/user-attachments/assets/acf04af0-107f-4ebb-9ed2-2a03847071a5

<!-- Shell command -->

[shell-must-have-hovered-item-video]: https://github.com/user-attachments/assets/d9a49cb7-67fd-40fe-8f68-130561de0cca
[shell-hovered-item-optional-video]: https://github.com/user-attachments/assets/f7fdfa7c-d7cc-4157-bb5f-63c37f82ea5b
[shell-prompt-video]: https://github.com/user-attachments/assets/6648ad92-320f-457d-9f3e-b5da6f1c07bc
[shell-behaviour-video]: https://github.com/user-attachments/assets/4727658f-e27c-4fbe-acd7-acfeac54cd17
[shell-exit-if-directory-video]: https://github.com/user-attachments/assets/ef0e9818-cc81-45fc-9126-6903314ed6b3

<!-- Paste command -->

[smart-paste-video]: https://github.com/user-attachments/assets/59800de2-8445-4f68-834b-10a0e394c400

<!-- Tab create command -->

[smart-tab-create-video]: https://github.com/user-attachments/assets/bf48e411-b7ed-4624-abd9-084dcdc25ab5

<!-- Tab switch command -->

[smart-tab-switch-video]: https://github.com/user-attachments/assets/5b94ff0f-f77c-4250-96ac-4fea67eebc46

<!-- Quit command -->

[quit-with-confirmation-video]: https://github.com/user-attachments/assets/9e212a32-c7c3-470f-895e-bb1cba03292d

<!-- Arrow command -->

[smooth-arrow-video]: https://github.com/user-attachments/assets/990935f5-ce6e-4536-9ddc-d8a32da69803
[wraparound-arrow-video]: https://github.com/user-attachments/assets/b8233e26-06b7-436d-bafa-1639ed12aa53
[smooth-wraparound-arrow-video]: https://github.com/user-attachments/assets/59d3618a-59cd-448d-b552-e3cc796d109e

<!-- Parent arrow command -->

[parent-arrow-video]: https://github.com/user-attachments/assets/c412ed7b-a6ee-44e7-bf68-f9f2e5214a50
[smooth-parent-arrow-video]: https://github.com/user-attachments/assets/45fdfa5f-86ef-453c-89a8-1c58d6318e93
[wraparound-parent-arrow-video]: https://github.com/user-attachments/assets/3a429a57-2dc6-47c6-be4e-fab5844bafde
[smooth-wraparound-parent-arrow-video]: https://github.com/user-attachments/assets/7d3d58ea-4b00-4cb2-9aea-950940b1ad1a

<!-- Archive command -->

[archive-must-have-hovered-item-video]: https://github.com/user-attachments/assets/a8d667c8-a8a5-44ed-9220-aa55345c98ed
[archive-hovered-item-optional-video]: https://github.com/user-attachments/assets/213f82d2-fe70-4c42-8f24-b09c7d7d7dfe
[archive-prompt-video]: https://github.com/user-attachments/assets/20366432-f195-4531-bb08-9b3f0e8f848e
[archive-behaviour-video]: https://github.com/user-attachments/assets/dcbe9909-db40-4f96-8591-c1a104b63381
[archive-encrypt-files-video]: https://github.com/user-attachments/assets/08b98e01-2cc2-486e-bd4d-bfbe9da792db
[archive-reveal-created-archive-video]: https://github.com/user-attachments/assets/e908afb8-c431-4e6d-8834-c02216461076
[archive-remove-archived-files-video]: https://github.com/user-attachments/assets/d0495292-6508-4417-b378-033e6acc0c4d

<!-- Editor command -->

[editor-must-have-hovered-item-video]: https://github.com/user-attachments/assets/a0e4500d-7bfe-4fb1-9289-8c39c5c6f323
[editor-hovered-item-optional-video]: https://github.com/user-attachments/assets/96798f1f-2ddc-464a-b6ae-48cc20f88b3c
[editor-prompt-video]: https://github.com/user-attachments/assets/5453cc87-3721-4b80-8cc2-b730ddff5da8
[editor-behaviour-video]: https://github.com/user-attachments/assets/f479ef38-5b78-43f1-83d4-045bef6f5f20

<!-- Pager command -->

[pager-must-have-hovered-item-video]: https://github.com/user-attachments/assets/7daa8e81-bc83-4ff3-9462-d71293565e67
[pager-hovered-item-optional-video]: https://github.com/user-attachments/assets/e123fb58-d49e-46b6-bc33-c41eb01cf9aa
[pager-prompt-video]: https://github.com/user-attachments/assets/cfba76a1-116e-4caf-b25a-57d631d115a0
[pager-behaviour-video]: https://github.com/user-attachments/assets/d036f865-2909-414b-80d9-80e550b6b3dd
