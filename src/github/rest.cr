require "http/client"

# :nodoc:
class GitHub
end

# An HTTP client for the GitHub REST API.
class GitHub::REST
  # Creates a new GitHub HTTP REST client for the given uri, which calls its
  # token proc and sets the Authorization header for every request.
  def initialize(@uri : URI, token : -> String, user_agent = "bjjb/git-hub/rest")
    @http = HTTP::Client.new(@uri)
    @http.before_request do |request|
      unless %w(GET HEAD DELETE).includes?(request.method.upcase)
        request.headers["Content-Type"] = "application/json"
      end
      request.headers["User-Agent"] = user_agent
      request.headers["Accept"] = "application/vnd.github+json"
      request.headers["Authorization"] = "Bearer #{token.call}"
    end
  end

  # Gets a response for the given resource.
  def get(resource)
    @http.get(uri(resource))
  end

  # Gets a response with query params.
  def get(resource, query)
    @http.get(uri(resource, query(query)))
  end

  # Creates a new resource and returns the response.
  def post(collection, body)
    @http.post(uri(collection), body: body(body))
  end

  # Creates a new resource with query params.
  def post(collection, query, body)
    @http.post(uri(collection, query(query)), body: body(body))
  end

  # Replaces a resource and returns the response.
  def put(resource, body)
    @http.put(uri(resource), body: body(body))
  end

  # Replaces a resource with query params.
  def put(resource, query, body)
    @http.put(uri(resource, query(query)), body: body(body))
  end

  # Patches a resource and returns the response.
  def patch(resource, body)
    @http.patch(uri(resource), body: body(body))
  end

  # Patches a resource with query params.
  def patch(resource, query, body)
    @http.patch(uri(resource, query(query)), body: body(body))
  end

  # Deletes a resource and returns the response.
  def delete(resource)
    @http.delete(uri(resource))
  end

  # Deletes a resource with query params.
  def delete(resource, query)
    @http.delete(uri(resource, query(query)))
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
