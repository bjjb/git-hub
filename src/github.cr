require "uri"
require "json"
require "./git"

# A GitHub provides a simple API for interacting with a GitHub server.
class GitHub
  # The version of the module.
  VERSION = "0.1.0"

  # A default URI for API requests.
  @@uri : URI = URI.parse("https://api.github.com")
  # A default token proc for authorization.
  @@token : (-> String) = -> { ENV.fetch("GITHUB_TOKEN", "") }
  # A default path for the home of the tree.
  @@home : Path = Path["~/src/github.com"].expand(home: true)
  # A default user name.
  @@user : String = ENV.fetch("USER", "")

  # The URI used to create the client.
  getter uri : URI
  # The token proc used to create the client.
  property token : -> String
  # The home path used to create the workdir tree manager.
  getter home : Path
  # The username.
  getter user : String

  # Makes a new GitHub which can make requests to uri using the result of
  # calling token, and treats home as the root of its repo tree.
  def initialize(@uri = @@uri, @token = @@token, @home = @@home, @user = @@user)
    @rest = REST.new(@uri, -> { @token.call }, "bjjb/git-hub@#{VERSION}")
  end

  def self.version
    VERSION
  end

  # The most recently observed rate limit, or nil.
  def rate_limit
    @rest.rate_limit
  end

  # Gets a resource.
  def get(resource, form = {} of String => Array(String))
    @rest.get(resource, form)
  end

  # Creates a new resource.
  def post(collection, body : String | Bytes | IO | Nil)
    @rest.post(collection, body)
  end

  # :ditto:
  def post(collection, body)
    @rest.post(collection, body.to_json)
  end

  # Sets a resource.
  def put(resource, body : String | Bytes | IO | Nil)
    @rest.put(resource, body)
  end

  # :ditto:
  def put(resource, body)
    @rest.put(resource, body.to_json)
  end

  # Modifies a resource.
  def patch(resource, body : String | Bytes | IO | Nil)
    @rest.patch(resource, body)
  end

  # :ditto:
  def patch(resource, body)
    @rest.patch(resource, body.to_json)
  end

  # Deletes a resource.
  def delete(resource)
    @rest.delete(resource)
  end

  # Returns a paginated collection over a list endpoint.
  def paginate(resource, query = nil)
    @rest.paginate(resource, query)
  end

  # A local git repo with remotes pointing to a GitHub repository.
  class Repo
    getter remotes = {} of String => URI
    getter workdir : Path

    def initialize(workdir = ".")
      workdir = File.realpath(workdir)
      @workdir = Path[workdir].expand(home: true)
      Dir.cd(@workdir) do
        Git.remotes.each { |remote| @remotes[remote.name] = remote.uri }
      end
    end

    # Returns "owner/repo" from the origin remote.
    def full_name(remote = "origin")
      path = @remotes[remote].path
      # SSH: git@github.com:owner/repo.git → path after ':'
      host, sep, rest = path.partition(':')
      slug = sep.blank? ? host : rest
      slug.lchop('/').rchop(".git")
    end
  end

  # Returns a Repo if the given path represents a git repository.
  def repo?(path = ".")
    return unless File.exists?(Path[path, ".git/config"].expand(home: true))
    repo = Repo.new(Path[path].expand(home: true))
    repo unless repo.remotes.empty?
  end

  # Returns the namespace path if the given path is within home but not a
  # repo.
  def namespace?(path = ".") : String?
    expanded = Path[path].expand(home: true)
    return nil if File.exists?(expanded / ".git/config")
    return nil unless expanded.to_s.starts_with?(home.to_s)
    relative = expanded.relative_to(home)
    return nil if relative.to_s.empty? || relative.to_s == "."
    relative.to_s
  end

  # A general GitHub error.
  class Error < Exception
  end

  # CLI error with exit code for testable error handling.
  class CLI::Error < Exception
    getter code : Int32

    def initialize(message : String? = nil, @code : Int32 = 1)
      super(message)
    end
  end

  # IO streams for CLI output.
  property input : IO = STDIN
  property output : IO = STDOUT
  property error : IO = STDERR

  # Flag to indicate a terminal command was handled.
  property? done : Bool = false

  # Runs the CLI with the given arguments, returning an exit code.
  def run(args : Array(String), @input : IO = STDIN, @output : IO = STDOUT, @error : IO = STDERR) : Int32
    @done = false
    op = option_parser
    op.parse(GitHub.expand_short_options(args, op))
    0
  rescue ex : CLI::Error
    error.puts(ex.message) if ex.message
    ex.code
  ensure
    if (rl = rate_limit) && rl.low?
      error.puts "Warning: #{rl.remaining}/#{rl.limit} API requests remaining (resets #{rl.reset})"
    end
  end

  # Makes a new GitHub using values from the git configuration under name,
  # falling back to environment variables or defaults.
  def self.git(name : String)
    uri = git_config(name, "uri") || ENV["GITHUB_API_URL"]? || @@uri.to_s
    tokencmd = git_config(name, "tokencmd")
    home = git_config(name, "home") || @@home.to_s
    user = git_config(name, "user") || ENV["GITHUB_USER"]? || @@user

    token_proc = if tokencmd
                   -> { `#{tokencmd}`.strip }
                 elsif token = ENV["GITHUB_TOKEN"]?
                   -> { token }
                 else
                   @@token
                 end

    new(
      URI.parse(uri),
      token_proc,
      Path.new(home).expand(home: true),
      user,
    )
  end

  # Reads a git config value, returning nil if git is unavailable or the
  # key is unset.
  private def self.git_config(name : String, key : String) : String?
    Git.config(name, key)
  end
end

require "./github/*"
