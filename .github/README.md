# git-hub

[![CI][badge]][ci]

[git][1] + [hub][2] = a git subcommand for GitHub.

Adds a `hub` command to git that wraps the [GitHub
REST API][3]. Also usable as a Crystal library.

## Quick Start

You need [Crystal][4]. Clone the repo and build:

    shards install
    shards build --release --production

Put `bin/git-hub` on your `$PATH`, then configure:

    git config hub.uri https://api.github.com        # the default
    git config hub.tokencmd 'pass github.com/token'  # for example
    git config hub.home ~/src/github.com             # or ~/Projects, etc
    git config hub.user myuser                       # your GitHub handle

## Usage

    git hub get user | jq .login
    git hub post user/repos -- name=myproject private=true
    git hub get repos/myuser/myproject
    git hub release create v1.0.0
    git hub help

## Library

```yaml
# shard.yml
dependencies:
  git-hub:
    github: bjjb/git-hub
```

```crystal
require "github"
gh = GitHub.new
puts gh.get("user").body
```

## Development

    shards install
    crystal spec
    crystal tool format .
    bin/ameba

See [CI][] for how the pipeline works.

## Contributing

1. Fork it
2. Create your feature branch
3. `crystal spec && crystal tool format .`
4. Push and open a pull request

## Project Configuration

| Setting                          | Value     |
|----------------------------------|-----------|
| Visibility                       | public    |
| Default branch                   | `main`    |
| License                          | MIT       |
| Issues                           | enabled   |
| Wiki                             | enabled   |
| Projects                         | enabled   |
| Discussions                      | disabled  |
| Forking                          | allowed   |

### Security

| Feature                          | Status    |
|----------------------------------|-----------|
| Secret scanning                  | enabled   |
| Secret scanning push protection  | enabled   |
| Private vulnerability reporting  | enabled   |
| Dependabot alerts                | enabled   |
| Code scanning                    | n/a       |

See [SECURITY.md][] for the reporting policy.

### CI

The [CI workflow][ci] runs on every push and pull
request. It uses the [Crystal Alpine container][img]
directly — no third-party actions except
[actions/cache][cache] for `lib/`.

**Jobs:**

- **lint** — checks formatting (`crystal tool format`)
  and runs [ameba][] with all rules enabled
- **test** — runs the spec suite with TAP output

Both jobs cache `lib/` and `bin/` keyed on
`shard.lock`. The first run after a dependency change
will be slow (~60s to build ameba); subsequent runs
restore from cache.

The Crystal version is pinned in the container image
tag in `workflows/ci.yml`. Bump it to match the
minimum version in `shard.yml`.

## License

[MIT](LICENSE)

[1]: https://git-scm.com
[2]: https://github.com
[3]: https://docs.github.com/en/rest
[4]: https://crystal-lang.org
[badge]: https://github.com/bjjb/git-hub/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/bjjb/git-hub/actions/workflows/ci.yml
[img]: https://hub.docker.com/r/crystallang/crystal
[cache]: https://github.com/actions/cache
[ameba]: https://github.com/crystal-ameba/ameba
[SECURITY.md]: ../SECURITY.md
