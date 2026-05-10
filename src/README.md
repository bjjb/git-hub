# src

Source code for `git-hub`.

## Guidelines

- Use the stdlib as much as possible — avoid external
  deps when stdlib suffices
- Be functional — prefer immutable data, pure functions,
  and composition
- Minimal requires — nested files should only require
  what they need
- Run `crystal tool format` before considering work done
- Follow all ameba guidelines (`bin/ameba`)

## Layout

| File / Directory | Purpose                          |
|------------------|----------------------------------|
| `main.cr`        | CLI entrypoint                   |
| `git.cr`         | Git wrapper (config, remotes)    |
| `github.cr`      | `GitHub` class — public API      |
| `github/`        | Sub-modules (REST, CLI parsing)  |

Every folder under `src/` has a `README.md` describing
its contents.
