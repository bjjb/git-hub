require "spec"
require "json"
require "wait_group"
require "../../../src/github/rest"

describe GitHub::REST::RateLimit do
  it "parses from response headers" do
    server = HTTP::Server.new do |context|
      context.response.headers["X-RateLimit-Limit"] = "5000"
      context.response.headers["X-RateLimit-Remaining"] = "4999"
      context.response.headers["X-RateLimit-Reset"] = "1700000000"
      context.response.headers["X-RateLimit-Used"] = "1"
      context.response.headers["X-RateLimit-Resource"] = "core"
      context.response.content_type = "application/json"
      %q({"ok":true}).to_s(context.response)
    end
    addr = server.bind_unused_port
    wg = WaitGroup.new
    wg.spawn { server.listen }

    rest = GitHub::REST.new(URI.parse("http://#{addr}"), -> { "tok" })
    rest.rate_limit.should be_nil
    rest.get("test")
    rl = rest.rate_limit
    rl.should_not be_nil
    rl = rl.as(GitHub::REST::RateLimit)
    rl.limit.should eq 5000
    rl.remaining.should eq 4999
    rl.used.should eq 1
    rl.resource.should eq "core"
    rl.exhausted?.should be_false
    rl.low?.should be_false

    server.close
    wg.wait
  end

  it "reports low when remaining is below 10% of limit" do
    rl = GitHub::REST::RateLimit.new(
      limit: 5000, remaining: 499, reset: Time.utc,
      used: 4501, resource: "core"
    )
    rl.low?.should be_true
  end

  it "does not report low when remaining is above 10%" do
    rl = GitHub::REST::RateLimit.new(
      limit: 5000, remaining: 500, reset: Time.utc,
      used: 4500, resource: "core"
    )
    rl.low?.should be_false
  end

  it "does not report low when limit is zero" do
    rl = GitHub::REST::RateLimit.new(
      limit: 0, remaining: 0, reset: Time.utc,
      used: 0, resource: "core"
    )
    rl.low?.should be_false
  end

  it "retries on 429" do
    attempts = 0
    server = HTTP::Server.new do |context|
      attempts += 1
      if attempts == 1
        context.response.status = HTTP::Status::TOO_MANY_REQUESTS
        context.response.headers["Retry-After"] = "0"
        context.response.headers["X-RateLimit-Remaining"] = "0"
        context.response.headers["X-RateLimit-Reset"] = "0"
        context.response.content_type = "application/json"
        %q({"message":"rate limit"}).to_s(context.response)
      else
        context.response.headers["X-RateLimit-Remaining"] = "99"
        context.response.headers["X-RateLimit-Reset"] = "0"
        context.response.content_type = "application/json"
        %q({"ok":true}).to_s(context.response)
      end
    end
    addr = server.bind_unused_port
    wg = WaitGroup.new
    wg.spawn { server.listen }

    rest = GitHub::REST.new(URI.parse("http://#{addr}"), -> { "tok" })
    response = rest.get("test")
    response.status.should eq HTTP::Status::OK
    attempts.should eq 2

    server.close
    wg.wait
  end
end
