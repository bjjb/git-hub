# TODO

Improvements and features planned for `git-hub`.

## Features
- [ ] **Pull Request Management**: Add a `pr` command to create, list, and merge PRs.
- [ ] **Interactive Auth**: Add `auth login` to handle token generation and setup.
- [ ] **Human-friendly Output**: Detect TTY and provide table/pretty-printed output instead of raw JSON.
- [ ] **Search Command**: Dedicated `search` subcommand for repos, issues, and users.
- [ ] **Gist Support**: Basic commands to create and list Gists.

## User Experience
- [ ] **Better Error Reporting**: Display GitHub API error messages on non-2xx responses instead of silent exits.
- [ ] **Shell Completion**: Generate completion scripts for Zsh/Bash.
- [ ] **Auto-pretty-print**: Pretty-print JSON output when connected to a TTY.

## Architecture & Maintenance
- [ ] **Command Pattern**: Refactor `option_parser.cr` to move subcommands into separate files/classes.
- [ ] **Documentation**: Expand the Library section with more complex examples (e.g., custom paginators).
- [ ] **Performance**: Profile parallel execution for very large paginated sets.
