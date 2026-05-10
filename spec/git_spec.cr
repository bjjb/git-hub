require "spec"
require "../src/git"

describe Git do
  describe ".config" do
    it "returns nil for unset keys" do
      Git.config("nonexistent-section-xyz", "key").should be_nil
    end
  end
end
