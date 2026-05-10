require "http/client"

# :nodoc:
class GitHub
end

# An HTTP client for the GitHub REST API.
class GitHub::REST
  # The most recently observed rate limit, or nil if no
  # requests have been made yet.
  getter rate_limit : RateLimit?

  # Creates a new GitHub HTTP REST client for the given uri, which calls its
  # token proc and sets the Authorization header for every request.
  def initialize(@uri : URI, token : -> String, user_agent = "bjjb/git-hub/rest")
    @pool = Pool.new(@uri) do |http|
      http.before_request do |request|
        unless %w(GET HEAD DELETE).includes?(request.method.upcase)
          request.headers["Content-Type"] = "application/json"
        end
        request.headers["User-Agent"] = user_agent
        request.headers["Accept"] = "application/vnd.github+json"
        request.headers["Authorization"] = "Bearer #{token.call}"
      end
    end
  end

  # Gets a response for the given resource.
  def get(resource)
    throttle(&.get(uri(resource)))
  end

  # Gets a response with query params.
  def get(resource, query)
    throttle(&.get(uri(resource, query(query))))
  end

  # Creates a new resource and returns the response.
  def post(collection, body)
    throttle { |http| http.post(uri(collection), body: body(body)) }
  end

  # Creates a new resource with query params.
  def post(collection, query, body)
    throttle { |http| http.post(uri(collection, query(query)), body: body(body)) }
  end

  # Replaces a resource and returns the response.
  def put(resource, body)
    throttle(&.put(uri(resource), body: body(body)))
  end

  # Replaces a resource with query params.
  def put(resource, query, body)
    throttle { |http| http.put(uri(resource, query(query)), body: body(body)) }
  end

  # Patches a resource and returns the response.
  def patch(resource, body)
    throttle(&.patch(uri(resource), body: body(body)))
  end

  # Patches a resource with query params.
  def patch(resource, query, body)
    throttle { |http| http.patch(uri(resource, query(query)), body: body(body)) }
  end

  # Deletes a resource and returns the response.
  def delete(resource)
    throttle(&.delete(uri(resource)))
  end

  # Deletes a resource with query params.
  def delete(resource, query)
    throttle(&.delete(uri(resource, query(query))))
  end

  # Returns a paginated collection over a list endpoint.
  # Fetches the first page to detect the response shape, then
  # returns an `ArrayPaginator` or `ObjectPaginator` accordingly.
  def paginate(resource, query = nil) : Paginator(JSON::Any)
    full = URI.parse(@uri.to_s)
    full.path = "#{full.path}/#{resource.lstrip('/')}"
    query.try { full.query_params = self.query(query) }
    http = @pool.checkout_persistent
    response = http.get(full.request_target)
    raise Error.new(response) unless response.status.success?
    @rate_limit = RateLimit.from(response) || @rate_limit
    pull = JSON::PullParser.new(response.body)
    case pull.kind
    when .begin_object?
      ObjectPaginator(JSON::Any).new(full, http, response)
    else
      ArrayPaginator(JSON::Any).new(full, http, response)
    end
  end

  # Executes a request block, respecting rate limits. Checks
  # out a client from the pool, waits if the rate limit is
  # exhausted, and retries once on 429.
  private def throttle(&) : HTTP::Client::Response
    if (rl = @rate_limit) && rl.exhausted?
      sleep rl.wait_time
    end
    @pool.checkout do |http|
      response = yield http
      @rate_limit = RateLimit.from(response) || @rate_limit
      if response.status == HTTP::Status::TOO_MANY_REQUESTS
        retry_after = response.headers["Retry-After"]?.try(&.to_i) || 60
        sleep retry_after.seconds
        response = yield http
        @rate_limit = RateLimit.from(response) || @rate_limit
      end
      response
    end
  end

  private def uri(resource, query : URI::Params? = nil)
    uri = URI.parse(@uri.to_s)
    uri.path = "#{uri.path}/#{resource.lstrip('/')}"
    query.try { uri.query_params = query }
    uri.request_target
  end

  private def query(query : String) : URI::Params
    URI::Params.parse(query)
  end

  private def query(query : Hash(String, Enumerable(String)))
    URI::Params.new(query.transform_values(&.to_a))
  end

  private def query(query : URI::Params)
    query.itself
  end

  private def body(body)
    body
  end
end

require "./rest/*"
