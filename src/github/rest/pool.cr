require "http/client"

# :nodoc:
class GitHub
  # :nodoc:
  class REST
  end
end

# A channel-based pool of HTTP clients. Clients are created
# lazily up to `size`, then reused via checkout/checkin.
# Fiber-safe: multiple fibers can checkout clients concurrently.
#
# ```
# pool = GitHub::REST::Pool.new(uri, size: 4) do |http|
#   http.before_request { |r| r.headers["Authorization"] = "Bearer ..." }
# end
# pool.checkout do |http|
#   http.get("/users/bjjb")
# end
# ```
class GitHub::REST::Pool
  @channel : Channel(HTTP::Client)
  @size : Int32
  @created : Atomic(Int32) = Atomic(Int32).new(0)

  def initialize(@uri : URI, @size : Int32 = 4, &@configure : HTTP::Client ->)
    @channel = Channel(HTTP::Client).new(@size)
  end

  # Checks out a client, yields it, and returns it to the pool.
  def checkout(&)
    client = acquire
    begin
      yield client
    ensure
      @channel.send(client)
    end
  end

  # Creates a new configured client outside the pool, for
  # long-lived use (e.g. paginators that hold a connection
  # across multiple requests).
  def checkout_persistent : HTTP::Client
    client = HTTP::Client.new(@uri)
    @configure.call(client)
    client
  end

  private def acquire : HTTP::Client
    prev = @created.add(1)
    if prev < @size
      client = HTTP::Client.new(@uri)
      @configure.call(client)
      client
    else
      @created.sub(1)
      @channel.receive
    end
  end
end
