require "http/client"
require "json"
require "uri"

# :nodoc:
class GitHub
  # :nodoc:
  class REST
  end
end

# A reusable, multi-pass paginated collection over a GitHub
# REST API list endpoint. Each call to `#each` returns a fresh
# `Cursor` that follows `Link` headers across pages, yielding
# one deserialized item at a time.
#
# Use `ArrayPaginator` for endpoints returning bare JSON arrays,
# and `ObjectPaginator` for endpoints returning wrapper objects
# (e.g. `{"total_count": N, "items": [...]}`). The `REST#paginate`
# factory detects the shape automatically.
abstract class GitHub::REST::Paginator(T)
  include Iterable(T)
  include Enumerable(T)

  def initialize(@uri : URI, @http : HTTP::Client,
                 @initial : HTTP::Client::Response? = nil)
  end

  # Returns a fresh iterator over the collection. The first
  # call uses the initial response if one was provided.
  abstract def each : Cursor(T)

  # Yields each item to the block.
  def each(&) : Nil
    cursor = each
    loop do
      value = cursor.next
      break if value.is_a?(Iterator::Stop)
      yield value
    end
  end

  # The single-pass iterator that does the actual fetching.
  # Follows `Link: rel="next"` headers and exposes all four
  # link relations as getters.
  abstract class Cursor(T)
    include Iterator(T)

    # The URI of the next page, or nil if exhausted.
    getter next_link : URI?
    # The URI of the previous page, or nil if on the first page.
    getter prev_link : URI?
    # The URI of the first page.
    getter first_link : URI?
    # The URI of the last page.
    getter last_link : URI?

    def initialize(@uri : URI, @http : HTTP::Client,
                   initial : HTTP::Client::Response? = nil)
      @buffer = [] of T
      @index = 0
      @started = false
      return unless initial
      parse_links(initial)
      @buffer = extract_items(initial.body)
      @started = true
    end

    def next
      if @index >= @buffer.size
        return stop if @started && @next_link.nil?
        fetch_page
        return stop if @buffer.empty?
      end
      @buffer[(@index &+= 1) - 1]
    end

    # Extracts items from a response body.
    private abstract def extract_items(body : String) : Array(T)

    private def fetch_page
      uri = @started ? @next_link : @uri
      return if uri.nil?
      response = @http.get(uri.request_target)
      raise Error.new(response) unless response.status.success?
      parse_links(response)
      @buffer = extract_items(response.body)
      @index = 0
      @started = true
    end

    private def parse_links(response)
      @next_link = @prev_link = @first_link = @last_link = nil
      header = response.headers["Link"]? || return
      header.scan(/<([^>]+)>;\s*rel="(\w+)"/) do |match|
        uri = URI.parse(match[1])
        case match[2]
        when "next"  then @next_link = uri
        when "prev"  then @prev_link = uri
        when "first" then @first_link = uri
        when "last"  then @last_link = uri
        end
      end
    end
  end
end
