_commit_type_stats_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    opts="-l -c -prefix -suffix --no-prefix --no-suffix --no-cache --clear -project-name -project-root -h --help"

    case "$prev" in
        -prefix|-suffix|-project-name|-project-root)
            COMPREPLY=()
            return
            ;;
    esac

    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    return 0
}

complete -F _commit_type_stats_completion commit-type-stats
