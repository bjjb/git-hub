# git-hub

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

## Contributing

1. Fork it
2. Create your feature branch
3. `crystal spec && crystal tool format .`
4. Push and open a pull request

## License

[MIT](LICENSE)

[1]: https://git-scm.com
[2]: https://github.com
[3]: https://docs.github.com/en/rest
[4]: https://crystal-lang.org
