require "spec"
require "http/server"
require "wait_group"
require "../../../src/github/rest"

describe GitHub::REST::Pool do
  server = HTTP::Server.new do |ctx|
    ctx.response.content_type = "application/json"
    ctx.response << %({"ok":true})
  end
  addr = server.bind_unused_port
  uri = URI.parse("http://#{addr}")
  wg = WaitGroup.new

  before_all { wg.spawn { server.listen } }
  after_all { server.close; wg.wait }

  it "checks out and returns clients" do
    pool = GitHub::REST::Pool.new(uri, size: 2) { }
    pool.checkout do |http|
      response = http.get("/test")
      response.status.should eq HTTP::Status::OK
    end
  end

  it "creates a persistent client outside the pool" do
    pool = GitHub::REST::Pool.new(uri, size: 1) { }
    http = pool.checkout_persistent
    response = http.get("/test")
    response.status.should eq HTTP::Status::OK
    http.close
  end

  it "limits concurrent clients to pool size" do
    pool = GitHub::REST::Pool.new(uri, size: 2) { }
    active = Atomic(Int32).new(0)
    max_active = Atomic(Int32).new(0)

    WaitGroup.wait do |group|
      5.times do
        group.spawn do
          pool.checkout do |http|
            current = active.add(1) + 1
            loop do
              old = max_active.get
              break if current <= old
              break if max_active.compare_and_set(old, current)[1]
            end
            http.get("/test")
            sleep 10.milliseconds
            active.sub(1)
          end
        end
      end
    end

    max_active.get.should be <= 2
  end
end
