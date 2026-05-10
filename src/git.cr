require "uri"

# Git provides a wrapper around git.
module Git
  extend self

  def config(name : String, key : String) : String?
    run("config", "#{name}.#{key}").strip.presence
  rescue
    nil
  end

  # A named git remote and its URL.
  class Remote
    getter name : String
    getter url : String { Git.run("remote", "get-url", @name).strip }
    getter uri : URI { URI.parse(url) }

    def initialize(@name)
    end
  end

  def remotes : Enumerable(Remote)
    run("remote").strip.split.map(&.strip).map { |name| Remote.new(name) }
  end

  # Returns the tag before the given ref, or nil.
  def previous_tag(ref = "HEAD") : String?
    run("describe", "--tags", "--abbrev=0", "#{ref}^").strip.presence
  rescue
    nil
  end

  # Returns a changelog of commit subjects between two refs.
  def log(range : String, format = "%s") : Array(String)
    run("log", "--format=#{format}", range).strip.lines.reject(&.blank?)
  rescue
    [] of String
  end

  # Runs a git command with the given arguments, returning stdout.
  # Raises on non-zero exit.
  def run(*args : String) : String
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("git", args.to_a, output: output, error: error)
    raise error.to_s unless status.success?
    output.to_s
  end

  # Generates a Markdown changelog between a previous tag and a ref.
  def changelog(tag : String, ref = "HEAD") : String?
    prev = previous_tag(ref)
    range = prev ? "#{prev}..#{ref}" : ref
    commits = log(range)
    return if commits.empty?
    String.build do |str|
      str << "## What's Changed\n\n"
      commits.each { |subject| str << "* #{subject}\n" }
      str << "\n**Full Changelog**: #{prev}..#{tag}\n" if prev
    end
  end
end
