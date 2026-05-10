require "json"

# :nodoc:
class GitHub
end

# Request body construction utilities.
module GitHub::Body
  # Parses "KEY=VALUE" assignments into a nested
  # `JSON::Any` object. Dot-separated keys produce nested
  # objects:
  #
  #     parse_nested(["a.b.c=1"]) => {"a":{"b":{"c":"1"}}}
  #
  def self.parse_nested(args : Array(String)) : JSON::Any
    root = {} of String => JSON::Any
    args.each do |arg|
      k, v = arg.split('=', 2)
      parts = k.split('.')
      target = root
      parts[...-1].each do |part|
        unless target[part]?
          target[part] = JSON::Any.new({} of String => JSON::Any)
        end
        target = target[part].as_h
      end
      target[parts.last] = JSON::Any.new(v)
    end
    JSON::Any.new(root)
  end
end
