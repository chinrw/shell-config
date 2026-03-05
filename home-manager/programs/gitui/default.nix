{ ... }:
{
  programs.gitui = {
    enable = true;
    keyConfig = ''
      (
          // Vim-style navigation (matches lazygit defaults)
          move_left: Some(( code: Char('h'), modifiers: "")),
          move_right: Some(( code: Char('l'), modifiers: "")),
          move_up: Some(( code: Char('k'), modifiers: "")),
          move_down: Some(( code: Char('j'), modifiers: "")),

          // Vim-style scrolling
          page_up: Some(( code: Char('b'), modifiers: "CONTROL")),
          page_down: Some(( code: Char('f'), modifiers: "CONTROL")),
          home: Some(( code: Char('g'), modifiers: "")),
          end: Some(( code: Char('G'), modifiers: "SHIFT")),
          shift_up: Some(( code: Char('u'), modifiers: "CONTROL")),
          shift_down: Some(( code: Char('d'), modifiers: "CONTROL")),

          // Tab navigation (lazygit uses 1-5 for panels)
          tab_status: Some(( code: Char('1'), modifiers: "")),
          tab_log: Some(( code: Char('2'), modifiers: "")),
          tab_files: Some(( code: Char('3'), modifiers: "")),
          tab_stashing: Some(( code: Char('4'), modifiers: "")),
          tab_stashes: Some(( code: Char('5'), modifiers: "")),
          tab_toggle: Some(( code: Tab, modifiers: "")),
          tab_toggle_reverse: Some(( code: BackTab, modifiers: "SHIFT")),

          // General
          exit: Some(( code: Char('q'), modifiers: "")),
          quit: Some(( code: Char('Q'), modifiers: "SHIFT")),
          exit_popup: Some(( code: Esc, modifiers: "")),
          open_help: Some(( code: Char('?'), modifiers: "")),
          toggle_workarea: Some(( code: Char('w'), modifiers: "")),

          // Staging (space to toggle, like lazygit)
          stage_unstage_item: Some(( code: Char(' '), modifiers: "")),
          status_stage_all: Some(( code: Char('a'), modifiers: "")),
          status_reset_item: Some(( code: Char('d'), modifiers: "")),
          status_ignore_file: Some(( code: Char('i'), modifiers: "")),

          // Diff
          diff_stage_lines: Some(( code: Char('s'), modifiers: "")),
          diff_reset_lines: Some(( code: Char('d'), modifiers: "")),

          // Commit (c like lazygit)
          open_commit: Some(( code: Char('c'), modifiers: "")),
          open_commit_editor: Some(( code: Char('C'), modifiers: "SHIFT")),
          commit_amend: Some(( code: Char('A'), modifiers: "SHIFT")),
          toggle_signoff: Some(( code: Char('S'), modifiers: "SHIFT")),

          // Remote (P=push, p=pull like lazygit)
          push: Some(( code: Char('P'), modifiers: "SHIFT")),
          force_push: Some(( code: Char('P'), modifiers: "CONTROL")),
          pull: Some(( code: Char('p'), modifiers: "")),
          fetch: Some(( code: Char('f'), modifiers: "")),
          undo_commit: Some(( code: Char('z'), modifiers: "CONTROL")),

          // Branch (n=new, like lazygit)
          create_branch: Some(( code: Char('n'), modifiers: "")),
          rename_branch: Some(( code: Char('r'), modifiers: "")),
          delete_branch: Some(( code: Char('D'), modifiers: "SHIFT")),
          merge_branch: Some(( code: Char('M'), modifiers: "SHIFT")),
          rebase_branch: Some(( code: Char('R'), modifiers: "SHIFT")),
          select_branch: Some(( code: Enter, modifiers: "")),

          // Stash
          stashing_save: Some(( code: Char('s'), modifiers: "")),
          stash_apply: Some(( code: Char('a'), modifiers: "")),
          stash_open: Some(( code: Enter, modifiers: "")),
          stash_drop: Some(( code: Char('D'), modifiers: "SHIFT")),

          // Log & History
          log_tag_commit: Some(( code: Char('t'), modifiers: "")),
          log_mark_commit: Some(( code: Char(' '), modifiers: "")),
          log_find: Some(( code: Char('/'), modifiers: "")),
          log_reset_commit: Some(( code: Char('r'), modifiers: "")),
          log_reword_commit: Some(( code: Char('R'), modifiers: "SHIFT")),

          // File operations
          edit_file: Some(( code: Char('e'), modifiers: "")),
          blame: Some(( code: Char('B'), modifiers: "SHIFT")),
          file_find: Some(( code: Char('/'), modifiers: "")),
          branch_find: Some(( code: Char('/'), modifiers: "")),
          copy: Some(( code: Char('y'), modifiers: "")),

          // Tags
          tags: Some(( code: Char('T'), modifiers: "SHIFT")),
          delete_tag: Some(( code: Char('D'), modifiers: "SHIFT")),
      )
    '';
  };
}
