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

| #   | Change                       | Impact | Effort | Status |
| --- | ---------------------------- | ------ | ------ | ------ |
| 1   | Fix `ObjectPaginator` parse  | Medium | Trivial | ✅ Done |
| 2   | Stream paginated JSON output | Small  | Small   | Deferred |
| 3   | Parallel multi-resource reqs | Medium | Medium  | ✅ Done |
| 4   | Stream response bodies       | Medium | Medium  |        |

### 1. ✅ Double-parse in `ObjectPaginator#extract_items`

Fixed. `extract_items` now returns `items.as_a` directly
when `T` is `JSON::Any` (compile-time macro branch),
skipping the serialize/reparse round-trip. ~2.8× faster
extraction, ~2.4× less memory per page.

### 2. Deferred: Stream paginated JSON output

`paginate(...).each.to_json(output)` collects all items
across all pages before serializing. Streaming would
bound peak memory to O(page_size) instead of
O(total_items), but benchmarks show no throughput
improvement — the gain is only peak RSS for very large
collections. Not worth the complexity yet.

### 3. ✅ Parallel multi-resource requests

Fixed. `REST` now uses a channel-based connection pool
(`REST::Pool`) instead of a single `HTTP::Client`. CLI
commands spawn fibers for each resource arg, with
results collected in order. Single-arg requests run
inline with no overhead.

Benchmark (10 GETs, 50ms server latency each):

    sequential (old)  1.86 (536.70ms)  691kB/op  3.33× slower
    parallel (new)    6.20 (161.25ms)  704kB/op  fastest

Pool size is 4 by default, bounding concurrency.

### 4. Stream response bodies

Every `throttle` call reads the full `response.body`
into a `String`. For commands that just pipe output, use
`HTTP::Client#get` with a block to stream the body
directly to the output IO.
