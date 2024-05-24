# Nushell Config
$env.config = {
    show_banner: false
    footer_mode: always
    shell_integration: true
    table: {
        mode: rounded
        index_mode: always
        header_on_separator: true
        padding: { left: 2, right: 1 }
    }
    completions: {
        algorithm: fuzzy # fuzzy, prefix
        quick: true
        case_sensitive: false
        external: {
         enable: true
         max_results: 50
         completer: { |spans| carapace $spans.0 nushell ...$spans | from json }
        }
    }
    history: {
        max_size: 10000
        file_format: sqlite
    }
    filesize: {
        metric: true
    }
}
