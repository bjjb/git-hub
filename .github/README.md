# GitHub Configuration

## CI

The [CI workflow][ci] runs on every push and pull
request. It uses the [Crystal Alpine container][img]
directly — no third-party actions except
[actions/cache][cache] for `lib/`.

### Jobs

- **lint** — checks formatting (`crystal tool format`)
  and runs [ameba][] with all rules enabled
- **test** — runs the spec suite with TAP output

### Caching

Both jobs cache `lib/` keyed on `shard.lock`. The first
run after a dependency change will be slow (~60s to
build ameba); subsequent runs restore from cache.

### Adding or updating Crystal

The Crystal version is pinned in the container image
tag in `workflows/ci.yml`. Bump it to match the
minimum version in `shard.yml`.

[ci]: workflows/ci.yml
[img]: https://hub.docker.com/r/crystallang/crystal
[cache]: https://github.com/actions/cache
[ameba]: https://github.com/crystal-ameba/ameba
