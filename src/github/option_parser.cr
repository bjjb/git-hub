require "option_parser"
require "json"
require "wait_group"

# :nodoc:
class GitHub
  # Expands combined short options (e.g., "-qt" becomes ["-q", "-t"]).
  def self.expand_short_options(args : Array(String), op : OptionParser? = nil) : Array(String)
    args.flat_map do |arg|
      if arg.starts_with?("-") && !arg.starts_with?("--") && arg.size > 2
        expand_short_option(arg, op)
      else
        [arg]
      end
    end
  end

  private def self.expand_short_option(arg : String, op : OptionParser?) : Array(String)
    result = [] of String
    chars = arg[1..].chars
    i = 0
    while i < chars.size
      flag = "-#{chars[i]}"
      if op && takes_argument?(op, flag) && i + 1 < chars.size
        result << flag
        result << chars[(i + 1)..].join
        break
      else
        result << flag
      end
      i += 1
    end
    result
  end

  private def self.takes_argument?(op : OptionParser, flag : String) : Bool
    handlers = op.@handlers
    if handler = handlers[flag]?
      handler.@value_type != OptionParser::FlagValue::None
    else
      false
    end
  end

  # Parses "KEY=VALUE" assignments into a Hash(String, String).
  def self.parse_assignments(args : Array(String), into : Hash(String, String)) : Hash(String, String)
    args.each do |arg|
      k, v = arg.split('=', 2)
      into[k] = v
    end
    into
  end

  # Parses "KEY=VALUE" assignments, accumulating repeated keys.
  def self.parse_assignments(args : Array(String), into : Hash(String, Array(String))) : Hash(String, Array(String))
    args.each do |arg|
      k, v = arg.split('=', 2)
      into[k] ||= [] of String
      into[k] << v
    end
    into
  end

  # Raised when a request body is expected but stdin is a TTY.
  class NoBodyError < Error; end

  EMPTY_BODY = ""

  # Resolves the request body from xargs or stdin.
  # Warns on stderr and returns EMPTY_BODY when stdin
  # is a TTY and no attributes are given.
  private def resolve_body(xargs, input : IO) : String
    xargs.empty? ? body(input) : body(xargs)
  rescue NoBodyError
    error.puts "Warning: sending request with no body"
    EMPTY_BODY
  end

  # Builds a request body by reading from an IO.
  # Raises `NoBodyError` when stdin is a TTY.
  private def body(io : IO) : String
    if io.responds_to?(:tty?) && io.tty?
      raise NoBodyError.new
    end
    io.gets_to_end
  rescue ex : IO::Error
    raise CLI::Error.new("Failed to read input: #{ex.message}", 1)
  end

  # Builds a request body from KEY=VALUE assignments.
  # Supports dot notation for nested keys.
  private def body(assignments : Enumerable(String)) : String
    args = assignments.to_a
    if args.any?(&.split('=', 2).first.includes?('.'))
      GitHub::Body.parse_nested(args).to_json
    else
      GitHub.parse_assignments(args, {} of String => String).to_json
    end
  end

  # Runs a block for each item in parallel, returning results
  # in the original order. For a single item, runs inline.
  private def parallel(items : Array(String), &block : String -> String) : Array(String)
    return items.map { |item| block.call(item) } if items.size <= 1
    results = Array(String).new(items.size, "")
    WaitGroup.wait do |group|
      items.each_with_index do |item, i|
        group.spawn do
          results[i] = block.call(item)
        end
      end
    end
    results
  end

  getter option_parser do
    OptionParser.new do |op|
      prog = Path[PROGRAM_NAME].basename
      version = GitHub::VERSION
      op.banner = <<-EOT
      Usage: #{prog} [options...] COMMAND ...
          Makes requests to the server at #{uri}.
      Options:
      EOT
      op.on("-h", "--help", "print this help") { output.puts op; self.done = true }
      op.on("-V", "--version", "print version") { output.puts version; self.done = true }
      op.on("-t TOKEN", "--token TOKEN", "use TOKEN for authentication") do |token|
        self.token = -> { token }
      end
      op.invalid_option { |opt| raise CLI::Error.new("Invalid option: #{opt}") }
      op.unknown_args do |args|
        next if done?
        unless args.empty?
          arg = args.first
          raise CLI::Error.new("Invalid option: #{arg}") if arg.starts_with?('-')
          error.puts "Unknown command: #{arg}"
          error.puts op
          raise CLI::Error.new(nil, 1)
        end
      end
      op.separator "Commands:"
      op.on "version", "prints client and/or server version" do
        op.banner = <<-EOT
        Usage: #{prog} version [client|server]
            Prints the client version, the server version, or both (the
            default).
        Options:
        EOT
        op.unknown_args do |args|
          next if done?
          case args.first?
          when "client"
            output.puts version
          when "server"
            response = get("meta")
            raise CLI::Error.new(nil, 1) unless response.status.success?
            response.body.to_s(output)
          when nil
            output.puts "client: #{version}"
            response = get("meta")
            raise CLI::Error.new(nil, 1) unless response.status.success?
            output.puts "server: #{response.body}"
          else
            error.puts "Unknown argument: #{args.first}"
            error.puts op
            raise CLI::Error.new(nil, 1)
          end
        end
      end
      op.on "token", "print the token" do
        op.banner = <<-EOT
        Usage: #{prog} token
            Prints the configured token.
        Options:
        EOT
        op.unknown_args { output.puts token.call }
      end
      op.on "get", "gets resource" do
        all = false
        op.banner = <<-EOT
        Usage: #{prog} get [options] RESOURCES -- FILTERS
            Gets resources from the server sequentially. Common filters can be
            specified after '--', in the form NAME=VALUE. Each response body is
            printed to standard out. Stops and exits non-zero if a request gets
            a non 2xx response.
        Examples:
            # Get the authenticated user
            #{prog} get user | jq .login

            # Search for repos
            #{prog} get search/repositories -- q=crystal+language:crystal

            # List all issues
            #{prog} get -a repos/owner/repo/issues | jq '.[].title'
        Options:
        EOT
        op.on("-a", "--all", "fetch all pages") { all = true }
        op.unknown_args do |args, xargs|
          q = GitHub.parse_assignments(xargs, {} of String => Array(String))
          parallel(args) do |resource|
            if all
              io = IO::Memory.new
              self.paginate(resource, q).each.to_json(io)
              io.to_s
            else
              response = get(resource, q)
              raise CLI::Error.new(nil, 1) unless response.status.success?
              response.body
            end
          end.each(&.to_s(output))
        end
      end
      op.on "post", "creates resources" do
        op.banner = <<-EOT
        Usage: #{prog} post PATHS -- ATTRIBUTES
            Creates resources on the server sequentially, one at each path.
            Common attributes are specified after '--', in the form NAME=VALUE.
            If no attributes are given, reads a JSON body from standard input.
        Examples:
            # Create a new repo
            #{prog} post user/repos -- name=myproject private=true

            # Create an issue
            #{prog} post repos/owner/repo/issues -- title=Bug
        Options:
        EOT
        op.unknown_args do |args, xargs|
          b = resolve_body(xargs, input)
          parallel(args) do |resource|
            response = post(resource, b)
            raise CLI::Error.new(nil, 1) unless response.status.success?
            response.body
          end.each(&.to_s(output))
        end
      end
      op.on "put", "creates/replaces resources" do
        op.banner = <<-EOT
        Usage: #{prog} put PATHS -- ATTRIBUTES
            Creates or replaces resources on the server. If no attributes are
            given, reads a JSON body from standard input.
        Options:
        EOT
        op.unknown_args do |args, xargs|
          b = resolve_body(xargs, input)
          parallel(args) do |resource|
            response = put(resource, b)
            raise CLI::Error.new(nil, 1) unless response.status.success?
            response.body
          end.each(&.to_s(output))
        end
      end
      op.on "patch", "modifies resources" do
        op.banner = <<-EOT
        Usage: #{prog} patch PATHS -- CHANGES
            Modifies resources on the server. If no changes are given, reads
            a JSON body from standard input.
        Options:
        EOT
        op.unknown_args do |args, xargs|
          b = resolve_body(xargs, input)
          parallel(args) do |resource|
            response = patch(resource, b)
            raise CLI::Error.new(nil, 1) unless response.status.success?
            response.body
          end.each(&.to_s(output))
        end
      end
      op.on "delete", "deletes resources" do
        op.banner = <<-EOT
        Usage: #{prog} delete PATHS
            Deletes resources from the server, one for each path.
        Options:
        EOT
        op.unknown_args do |args, _|
          parallel(args) do |resource|
            response = delete(resource)
            raise CLI::Error.new(nil, 1) unless response.status.success?
            ""
          end
        end
      end
      op.on "current", "gets the current repo or namespace" do
        quiet = false
        show_type = false
        show_path = false
        op.banner = <<-EOT
        Usage: #{prog} current [options]
            Prints information about the current working directory's GitHub
            repo or namespace. Exits non-zero if neither can be determined.
        Options:
        EOT
        op.on("-q", "--quiet", "exit 0/1 without printing") { quiet = true }
        op.on("-t", "--type", "print 'repo' or 'namespace'") { show_type = true }
        op.on("-p", "--path", "print the owner/repo path") { show_path = true }
        op.unknown_args do |args|
          next if done?
          args.each do |arg|
            raise CLI::Error.new("Invalid option: #{arg}") if arg.starts_with?("-")
          end
          path : String? = nil
          type : String? = nil
          if repo = repo?
            path = repo.full_name
            type = "repo"
          elsif ns = namespace?
            path = ns
            type = "namespace"
          else
            raise CLI::Error.new(nil, 1)
          end

          if quiet
            # just exit 0
          elsif show_type
            output.puts type
          elsif show_path
            output.puts path
          else
            if type == "repo"
              response = get("repos/#{path}")
              raise CLI::Error.new(nil, 2) unless response.status.success?
              response.body.to_s(output)
            else
              response = get("users/#{path}")
              raise CLI::Error.new(nil, 2) unless response.status.success?
              response.body.to_s(output)
            end
          end
        end
      end
      op.on "release", "manages releases" do
        release_name : String? = nil
        release_body : String? = nil
        draft = false
        prerelease = false
        op.banner = <<-EOT
        Usage: #{prog} release COMMAND [options]
            Manages releases for the current repo.
        Commands:
            create [TAG]   Create a release
            list           List releases
            delete TAG     Delete a release
        Options:
        EOT
        op.on("-n NAME", "--name NAME", "release name") { |name| release_name = name }
        op.on("-b DESC", "--body DESC", "release body") { |desc| release_body = desc }
        op.on("--draft", "create as draft") { draft = true }
        op.on("--prerelease", "mark as prerelease") { prerelease = true }
        op.unknown_args do |args|
          next if done?
          command = args.shift?
          repo = repo? || raise CLI::Error.new("Not in a repo directory.", 1)
          full_name = repo.full_name
          case command
          when "create"
            tag = args.first? || raise CLI::Error.new("No tag specified.", 1)
            description = release_body || Git.changelog(tag) || "Release #{tag}"
            payload = {
              tag_name:   tag,
              name:       release_name || tag,
              body:       description,
              draft:      draft,
              prerelease: prerelease,
            }.to_json
            response = post("repos/#{full_name}/releases", payload)
            unless response.status.success?
              error.puts "release create failed: #{response.status} #{response.body}"
              raise CLI::Error.new(nil, 1)
            end
            response.body.to_s(output)
          when "list"
            response = get("repos/#{full_name}/releases")
            unless response.status.success?
              error.puts "release list failed: #{response.status} #{response.body}"
              raise CLI::Error.new(nil, 1)
            end
            response.body.to_s(output)
          when "delete"
            tag = args.first? || raise CLI::Error.new("No tag specified.", 1)
            # GitHub needs release ID; get it by tag first
            response = get("repos/#{full_name}/releases/tags/#{URI.encode_path_segment(tag)}")
            unless response.status.success?
              error.puts "release not found: #{tag}"
              raise CLI::Error.new(nil, 1)
            end
            id = JSON.parse(response.body)["id"].as_i
            response = delete("repos/#{full_name}/releases/#{id}")
            unless response.status.success?
              error.puts "release delete failed: #{response.status} #{response.body}"
              raise CLI::Error.new(nil, 1)
            end
          else
            error.puts op
            raise CLI::Error.new(nil, 1)
          end
        end
      end
      op.on "issue", "manages issues" do
        all = false
        op.banner = <<-EOT
        Usage: #{prog} issue COMMAND [options]
            Manages issues for the current repo.
        Commands:
            list           List open issues
            NUMBER...      Get specific issues by number
        Examples:
            # List open issues
            #{prog} issue list

            # List all issues across all pages
            #{prog} issue list -a

            # Get issue #42
            #{prog} issue 42

            # Get issues #1 and #2
            #{prog} issue 1 2
        Options:
        EOT
        op.on("-a", "--all", "fetch all pages") { all = true }
        op.unknown_args do |args, xargs|
          next if done?
          command = args.shift? || raise CLI::Error.new(op.to_s, 1)
          repo = repo? || raise CLI::Error.new("Not in a repo directory.", 1)
          full_name = repo.full_name
          case command
          when "list"
            q = GitHub.parse_assignments(xargs, {} of String => Array(String))
            resource = "repos/#{full_name}/issues"
            if all
              self.paginate(resource, q).each.to_json(output)
            else
              response = get(resource, q)
              raise CLI::Error.new(nil, 1) unless response.status.success?
              response.body.to_s(output)
            end
          else
            numbers = [command] + args
            parallel(numbers) do |number|
              response = get("repos/#{full_name}/issues/#{number}")
              raise CLI::Error.new(nil, 1) unless response.status.success?
              response.body
            end.each(&.to_s(output))
          end
        end
      end
    end
  end
end
