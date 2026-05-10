require "spec"
require "file_utils"
require "../src/github"

describe GitHub do
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
  gh = GitHub.new(URI.parse("http://#{addr}"), -> { "abc123" })
  wg = WaitGroup.new

  before_all { wg.spawn { server.listen } }
  after_all { server.close; wg.wait }

  describe "#get" do
    it "gets a resource" do
      response = gh.get("foo")
      response.status.should eq HTTP::Status::OK
      JSON.parse(response.body)["method"].should eq "GET"
    end

    it "gets a resource with query params" do
      response = gh.get("foo", {"bar" => ["1"]})
      response.status.should eq HTTP::Status::OK
      JSON.parse(response.body)["uri"].as_s.should contain "bar=1"
    end
  end

  describe "#post" do
    it "posts a String body" do
      response = gh.post("foo", %({"name":"test"}))
      response.status.should eq HTTP::Status::CREATED
      json = JSON.parse(response.body)
      json["method"].should eq "POST"
      json["body"].should eq %({"name":"test"})
    end

    it "posts a Hash body as JSON" do
      response = gh.post("foo", {"name" => "hash"})
      response.status.should eq HTTP::Status::CREATED
      JSON.parse(response.body)["body"].should eq %({"name":"hash"})
    end

    it "posts a nil body" do
      response = gh.post("foo", nil)
      response.status.should eq HTTP::Status::CREATED
    end
  end

  describe "#put" do
    it "puts a String body" do
      response = gh.put("foo", %({"name":"test"}))
      response.status.should eq HTTP::Status::OK
      json = JSON.parse(response.body)
      json["method"].should eq "PUT"
      json["body"].should eq %({"name":"test"})
    end
  end

  describe "#patch" do
    it "patches a String body" do
      response = gh.patch("foo", %({"name":"test"}))
      response.status.should eq HTTP::Status::OK
      json = JSON.parse(response.body)
      json["method"].should eq "PATCH"
      json["body"].should eq %({"name":"test"})
    end
  end

  describe "#delete" do
    it "deletes a resource" do
      response = gh.delete("foo")
      response.status.should eq HTTP::Status::NO_CONTENT
    end
  end

  describe "#run" do
    {% for method in %w(post put patch) %}
    describe "{{method.id}}" do
      it "reads JSON from stdin when no attributes are given" do
        stdin = IO::Memory.new(%({"name":"from-stdin"}))
        stdout = IO::Memory.new
        code = gh.run(["{{method.id}}", "foo"], input: stdin, output: stdout)
        code.should eq 0
        JSON.parse(stdout.to_s)["body"].should eq %({"name":"from-stdin"})
      end

      it "uses assignments when given after --" do
        stdin = IO::Memory.new("should be ignored")
        stdout = IO::Memory.new
        code = gh.run(["{{method.id}}", "foo", "--", "name=from-args"], input: stdin, output: stdout)
        code.should eq 0
        JSON.parse(stdout.to_s)["body"].should eq %({"name":"from-args"})
      end

      it "sends an empty body when stdin is empty" do
        stdin = IO::Memory.new
        stdout = IO::Memory.new
        code = gh.run(["{{method.id}}", "foo"], input: stdin, output: stdout)
        code.should eq 0
      end

      it "errors when stdin is a TTY and no attributes are given" do
        stdin = TTYMemory.new
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = gh.run(["{{method.id}}", "foo"], input: stdin, output: stdout, error: stderr)
        code.should eq 1
        stderr.to_s.should contain "No input provided"
      end
    end
    {% end %}
  end

  describe %(.git(String)) do
    tmpdir = File.tempname("git-hub")
    name = "foo"
    uri = "https://api.test"
    token = "abc123"
    home = "~/foo"
    user = "alice"

    before_all do
      Dir.mkdir(tmpdir)
      Dir.cd(tmpdir) do
        Process.run("git", %w(init))
        Process.run("git", Process.parse_arguments("config #{name}.uri #{uri}"))
        Process.run("git", Process.parse_arguments("config #{name}.tokencmd 'printf #{token}'"))
        Process.run("git", Process.parse_arguments("config #{name}.home #{home}"))
        Process.run("git", Process.parse_arguments("config #{name}.user #{user}"))
      end
    end

    after_all { FileUtils.rm_rf(tmpdir) }

    it "gets the uri from git config" do
      Dir.cd(tmpdir) { GitHub.git(name) }.uri.to_s.should eq uri
    end

    it "gets the token using git config" do
      Dir.cd(tmpdir) { GitHub.git(name) }.token.call.should eq token
    end

    it "gets home directory from git config" do
      Dir.cd(tmpdir) { GitHub.git(name) }.home.should eq Path[home].expand(home: true)
    end

    it "gets the user from git config" do
      Dir.cd(tmpdir) { GitHub.git(name) }.user.to_s.should eq user
    end

    it "detects the repo if there's a .git/config" do
      Dir.cd(tmpdir) do
        github = GitHub.git(name)
        github.repo?.should be_nil
        Process.run("git", Process.parse_arguments("remote add origin https://github.com/foo/bar.git"))
        github.repo?.should_not be_nil
      end
    end
  end
end

# A mock IO that pretends to be a TTY.
class TTYMemory < IO::Memory
  def tty? : Bool
    true
  end
end
