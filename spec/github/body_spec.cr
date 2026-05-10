require "spec"
require "json"
require "../../src/github/body"

describe GitHub::Body do
  describe ".parse_nested" do
    it "parses flat keys" do
      result = GitHub::Body.parse_nested(["name=test", "private=true"])
      result["name"].as_s.should eq "test"
      result["private"].as_s.should eq "true"
    end

    it "parses dot-separated keys into nested objects" do
      result = GitHub::Body.parse_nested(["a.b.c=enabled"])
      result["a"]["b"]["c"].as_s.should eq "enabled"
    end

    it "merges sibling keys at the same depth" do
      result = GitHub::Body.parse_nested(["a.b=1", "a.c=2"])
      result["a"]["b"].as_s.should eq "1"
      result["a"]["c"].as_s.should eq "2"
    end

    it "mixes flat and nested keys" do
      result = GitHub::Body.parse_nested(["name=repo", "settings.pages.enabled=true"])
      result["name"].as_s.should eq "repo"
      result["settings"]["pages"]["enabled"].as_s.should eq "true"
    end

    it "handles values containing equals signs" do
      result = GitHub::Body.parse_nested(["query=a=b"])
      result["query"].as_s.should eq "a=b"
    end
  end
end
