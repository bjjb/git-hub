require "uri"

# Git provides a wrapper around git.
module Git
  extend self

  def config(name : String, key : String) : String?
    `git config #{name}.#{key}`.strip.presence
  rescue
    nil
  end

  # A named git remote and its URL.
  class Remote
    getter name : String
    getter url : String { `git remote get-url #{@name}`.strip }
    getter uri : URI { URI.parse(url) }

    def initialize(@name)
    end
  end

  def remotes : Enumerable(Remote)
    `git remote`.strip.split.map(&.strip).map { |name| Remote.new(name) }
  end

  # Returns the tag before the given ref, or nil.
  def previous_tag(ref = "HEAD") : String?
    `git describe --tags --abbrev=0 #{ref}^ 2>/dev/null`.strip.presence
  rescue
    nil
  end

  # Returns a changelog of commit subjects between two refs.
  def log(range : String, format = "%s") : Array(String)
    `git log --format=#{format} #{range}`.strip.lines.reject(&.blank?)
  rescue
    [] of String
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
