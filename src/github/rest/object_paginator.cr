require "./paginator"

# Paginator for endpoints returning wrapper objects with a
# single array field (e.g. `{"total_count": N, "items": [...]}`).
# Finds the lone array value automatically.
#
# Exposes `total_count` from the first response when present.
# Note that GitHub caps search results at 1000 items regardless
# of the reported total.
#
# ```
# paginator = GitHub::REST::ObjectPaginator(JSON::Any).new(uri, http)
# paginator.each { |item| puts item }
# paginator.total_count # => 4523 (may exceed actual results)
# ```
class GitHub::REST::ObjectPaginator(T) < GitHub::REST::Paginator(T)
  # The `total_count` reported by the server, or nil if not
  # yet fetched or absent from the response. May exceed the
  # actual number of items returned (e.g. search caps at 1000).
  getter total_count : Int64?

  def each : Cursor(T)
    initial = @initial
    @initial = nil
    Cursor(T).new(@uri, @http, initial)
  end

  # Yields each item and updates `total_count` after iteration.
  def each(&) : Nil
    cursor = each
    loop do
      value = cursor.next
      break if value.is_a?(Iterator::Stop)
      yield value
    end
    @total_count ||= cursor.total_count
  end

  # :nodoc:
  class Cursor(T) < GitHub::REST::Paginator::Cursor(T)
    # The `total_count` from the most recent response.
    getter total_count : Int64?

    private def extract_items(body : String) : Array(T)
      json = JSON.parse(body).as_h
      if tc = json["total_count"]?
        @total_count = tc.as_i64
      end
      _, items = json.find { |_, v| v.raw.is_a?(Array) } || return [] of T
      Array(T).from_json(items.to_json)
    end
  end
end
