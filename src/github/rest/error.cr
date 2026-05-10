require "http/client"

# :nodoc:
class GitHub
  # :nodoc:
  class REST
  end
end

# Raised when a GitHub REST API request returns a non-success status.
class GitHub::REST::Error < Exception
  # The HTTP status of the failed response.
  getter status : HTTP::Status
  # The raw response body.
  getter body : String

  def initialize(response : HTTP::Client::Response)
    @status = response.status
    @body = response.body
    super("#{@status.code} #{@status}")
  end
end
