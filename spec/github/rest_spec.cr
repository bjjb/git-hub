require "spec"
require "json"
require "wait_group"
require "../../src/github/rest"

describe GitHub::REST do
  server = HTTP::Server.new do |context|
    request, response = context.request, context.response
    method, uri, headers, body = request.method, request.uri, request.headers, request.body.try(&.gets)
    authorization = headers["Authorization"]?
    next response.respond_with_status(HTTP::Status::UNAUTHORIZED) if authorization.nil?
    next response.respond_with_status(HTTP::Status::FORBIDDEN) unless authorization == "Bearer abc123"
    response.status = case method
                      when "POST"   then HTTP::Status::CREATED
                      when "DELETE" then HTTP::Status::NO_CONTENT
                      else               HTTP::Status::OK
                      end
    next if method == "DELETE"
    {method: method, uri: uri.to_s, headers: headers, body: body}.to_json(response)
  end
  addr = server.bind_unused_port
  uri = URI.parse("http://#{addr}")
  token = -> { "abc123" }
  rest = GitHub::REST.new(uri, token)
  wg = WaitGroup.new

  before_all { wg.spawn { server.listen } }
  after_all { server.close; wg.wait }

  describe "#get" do
    it "gets a resource" do
      response = rest.get("foo")
      response.status.should eq HTTP::Status::OK
      json = JSON.parse(response.body)
      json["method"].should eq "GET"
      json["uri"].as_s.should contain "/foo"
    end

    it "gets a resource with a query string" do
      response = rest.get("foo", "bar=1&baz=2")
      json = JSON.parse(response.body)
      json["uri"].as_s.should contain "bar=1"
      json["uri"].as_s.should contain "baz=2"
    end

    it "gets a resource with a query hash" do
      response = rest.get("foo", {"bar" => ["1"], "baz" => ["2"]})
      json = JSON.parse(response.body)
      json["uri"].as_s.should contain "bar=1"
      json["uri"].as_s.should contain "baz=2"
    end

    it "gets a resource with URI::Params" do
      response = rest.get("foo", URI::Params{"bar" => "1", "baz" => "2"})
      json = JSON.parse(response.body)
      json["uri"].as_s.should contain "bar=1"
      json["uri"].as_s.should contain "baz=2"
    end
  end

  describe "#post" do
    it "posts a resource with a body" do
      response = rest.post("foo", %({"name":"test"}))
      response.status.should eq HTTP::Status::CREATED
      json = JSON.parse(response.body)
      json["method"].should eq "POST"
      json["body"].should eq %({"name":"test"})
    end

    it "posts a resource with a query and body" do
      response = rest.post("foo", "bar=1", %({"name":"test"}))
      response.status.should eq HTTP::Status::CREATED
      json = JSON.parse(response.body)
      json["uri"].as_s.should contain "bar=1"
      json["body"].should eq %({"name":"test"})
    end
  end

  describe "#put" do
    it "puts a resource with a body" do
      response = rest.put("foo", %({"resolved":"true"}))
      response.status.should eq HTTP::Status::OK
      json = JSON.parse(response.body)
      json["method"].should eq "PUT"
      json["body"].should eq %({"resolved":"true"})
    end

    it "puts a resource with a query and body" do
      response = rest.put("foo", "bar=1", %({"resolved":"true"}))
      json = JSON.parse(response.body)
      json["uri"].as_s.should contain "bar=1"
      json["body"].should eq %({"resolved":"true"})
    end
  end

  describe "#patch" do
    it "patches a resource with a body" do
      response = rest.patch("foo", %({"name":"updated"}))
      response.status.should eq HTTP::Status::OK
      json = JSON.parse(response.body)
      json["method"].should eq "PATCH"
      json["body"].should eq %({"name":"updated"})
    end

    it "patches a resource with a query and body" do
      response = rest.patch("foo", "bar=1", %({"name":"updated"}))
      json = JSON.parse(response.body)
      json["uri"].as_s.should contain "bar=1"
      json["body"].should eq %({"name":"updated"})
    end
  end

  describe "#delete" do
    it "deletes a resource" do
      response = rest.delete("foo")
      response.status.should eq HTTP::Status::NO_CONTENT
    end

    it "deletes a resource with a query" do
      response = rest.delete("foo", "bar=1")
      response.status.should eq HTTP::Status::NO_CONTENT
    end
  end
end
