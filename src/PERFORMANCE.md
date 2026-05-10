# Performance

Notes on benchmarking and potential improvements.

## Benchmarking

Use `Benchmark.ips` for hot-path microbenchmarks:

```crystal
# bench/rest_bench.cr
require "benchmark"
require "../src/github"

gh = GitHub.git("hub")

Benchmark.ips do |x|
  x.report("get user")     { gh.get("user") }
  x.report("get repos")    { gh.get("users/bjjb/repos") }
  x.report("paginate all") { gh.paginate("users/bjjb/repos").each { } }
end
```

Wall-clock for CLI commands:

    time git hub get -a repos/crystal-lang/crystal/issues > /dev/null

Memory profiling options:

- `GC.stats` before/after operations (Boehm GC)
- `jemalloc` with `MALLOC_CONF=stats_print:true`
- macOS `leaks`/`heap` tools on the built binary

## Opportunities

| #   | Change                       | Impact | Effort  |
| --- | ---------------------------- | ------ | ------- |
| 1   | Fix `ObjectPaginator` parse  | Medium | Trivial |
| 2   | Stream paginated JSON output | Large  | Small   |
| 3   | Parallel multi-resource reqs | Medium | Medium  |
| 4   | Stream response bodies       | Medium | Medium  |

### 1. Double-parse in `ObjectPaginator#extract_items`

`extract_items` parses JSON, finds the array,
re-serializes with `to_json`, then re-parses with
`from_json` — three passes per page. Since `T` is
`JSON::Any`, the items are already parsed. Replace
with `items.as_a`.

### 2. Stream paginated JSON output

`paginate(...).each.to_json(output)` collects all items
across all pages before serializing. For large
collections this holds everything in memory. Stream
instead:

```crystal
output << '['
first = true
paginate(resource, q).each do |item|
  output << ',' unless first
  item.to_json(output)
  first = false
end
output << ']'
```

Keeps at most one page in memory at a time.

### 3. Parallel multi-resource requests

`get`, `post`, etc. iterate `args.each` sequentially.
These are independent network calls and could run in
parallel fibers with a `Channel` for ordered collection.

Requires a connection pool — the current single
`HTTP::Client` is not fiber-safe. A channel-based pool
of N clients would suffice.

### 4. Stream response bodies

Every `throttle` call reads the full `response.body`
into a `String`. For commands that just pipe output, use
`HTTP::Client#get` with a block to stream the body
directly to the output IO.
