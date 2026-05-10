require "./paginator"

# Paginator for endpoints returning bare JSON arrays.
#
# ```
# paginator = GitHub::REST::ArrayPaginator(JSON::Any).new(uri, http)
# paginator.each { |item| puts item }
# ```
class GitHub::REST::ArrayPaginator(T) < GitHub::REST::Paginator(T)
  def each : Cursor(T)
    initial = @initial
    @initial = nil
    Cursor(T).new(@uri, @http, initial)
  end

  # :nodoc:
  class Cursor(T) < GitHub::REST::Paginator::Cursor(T)
    private def extract_items(body : String) : Array(T)
      Array(T).from_json(body)
    end
  end
end
