require "http/client"

# :nodoc:
class GitHub
  # :nodoc:
  class REST
  end
end

# Snapshot of GitHub's rate limit headers for a given resource pool.
record GitHub::REST::RateLimit,
  limit : Int32,
  remaining : Int32,
  reset : Time,
  used : Int32,
  resource : String do
  # Parses rate limit state from response headers.
  def self.from(response : HTTP::Client::Response) : self?
    remaining = response.headers["X-RateLimit-Remaining"]?
    return unless remaining
    new(
      limit: response.headers["X-RateLimit-Limit"]?.try(&.to_i) || 0,
      remaining: remaining.to_i,
      reset: Time.unix(response.headers["X-RateLimit-Reset"]?.try(&.to_i64) || 0i64),
      used: response.headers["X-RateLimit-Used"]?.try(&.to_i) || 0,
      resource: response.headers["X-RateLimit-Resource"]? || "core",
    )
  end

  # True when no requests remain and the reset time is in the future.
  def exhausted? : Bool
    remaining == 0 && reset > Time.utc
  end

  # True when remaining requests are below 10% of the limit.
  def low? : Bool
    limit > 0 && remaining < limit // 10
  end

  # Time to wait before the limit resets, or zero if not exhausted.
  def wait_time : Time::Span
    return Time::Span.zero unless exhausted?
    reset - Time.utc
  end
end
