require "spec"
require "json"
require "wait_group"
require "../../../src/github/rest"

# Returns a Link header value for the given page and total.
private def link_header(base : URI, page : Int32, total : Int32) : String
  links = [] of String
  links << %(<#{base}?page=#{page + 1}&per_page=3>; rel="next") if page < total
  links << %(<#{base}?page=#{page - 1}&per_page=3>; rel="prev") if page > 1
  links << %(<#{base}?page=1&per_page=3>; rel="first")
  links << %(<#{base}?page=#{total}&per_page=3>; rel="last")
  links.join(", ")
end

describe GitHub::REST::ArrayPaginator do
  pages = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8],
  ]

  server = HTTP::Server.new do |context|
    request, response = context.request, context.response
    page = (request.query_params["page"]? || "1").to_i
    data = pages[page - 1]? || ([] of Int32)
    base = URI.parse("http://#{request.headers["Host"]}#{request.path}")
    if pages.size > 1
      response.headers["Link"] = link_header(base, page, pages.size)
    end
    response.content_type = "application/json"
    data.to_json(response)
  end
  addr = server.bind_unused_port
  base = URI.parse("http://#{addr}/items?page=1&per_page=3")
  client_uri = URI.parse("http://#{addr}")
  wg = WaitGroup.new

  before_all { wg.spawn { server.listen } }
  after_all { server.close; wg.wait }

  it "iterates all items across pages" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ArrayPaginator(Int32).new(base, http)
    paginator.to_a.should eq [1, 2, 3, 4, 5, 6, 7, 8]
  end

  it "is multi-pass" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ArrayPaginator(Int32).new(base, http)
    paginator.to_a.should eq [1, 2, 3, 4, 5, 6, 7, 8]
    paginator.to_a.should eq [1, 2, 3, 4, 5, 6, 7, 8]
  end

  it "exposes link properties on the cursor" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ArrayPaginator(Int32).new(base, http)
    cursor = paginator.each

    # Consume first page.
    3.times { cursor.next }
    cursor.next_link.should_not be_nil
    cursor.prev_link.should be_nil
    cursor.first_link.should_not be_nil
    cursor.last_link.should_not be_nil

    # Consume second page.
    3.times { cursor.next }
    cursor.prev_link.should_not be_nil

    # Consume third (last) page.
    2.times { cursor.next }
    cursor.next_link.should be_nil
  end

  it "streams valid JSON via to_json" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ArrayPaginator(Int32).new(base, http)
    json = paginator.each.to_json
    Array(Int32).from_json(json).should eq [1, 2, 3, 4, 5, 6, 7, 8]
  end

  it "supports Iterable methods" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ArrayPaginator(Int32).new(base, http)
    paginator.each_slice(4).to_a.should eq [[1, 2, 3, 4], [5, 6, 7, 8]]
  end

  it "uses the initial response without re-fetching" do
    http = HTTP::Client.new(client_uri)
    initial = http.get(base.request_target)
    paginator = GitHub::REST::ArrayPaginator(Int32).new(base, http, initial)
    paginator.to_a.should eq [1, 2, 3, 4, 5, 6, 7, 8]
  end

  it "handles a single page with no Link header" do
    single_server = HTTP::Server.new do |context|
      context.response.content_type = "application/json"
      [42].to_json(context.response)
    end
    single_addr = single_server.bind_unused_port
    single_wg = WaitGroup.new
    single_wg.spawn { single_server.listen }

    http = HTTP::Client.new(URI.parse("http://#{single_addr}"))
    uri = URI.parse("http://#{single_addr}/items")
    paginator = GitHub::REST::ArrayPaginator(Int32).new(uri, http)
    paginator.to_a.should eq [42]

    single_server.close
    single_wg.wait
  end

  it "handles an empty collection" do
    empty_server = HTTP::Server.new do |context|
      context.response.content_type = "application/json"
      ([] of Int32).to_json(context.response)
    end
    empty_addr = empty_server.bind_unused_port
    empty_wg = WaitGroup.new
    empty_wg.spawn { empty_server.listen }

    http = HTTP::Client.new(URI.parse("http://#{empty_addr}"))
    uri = URI.parse("http://#{empty_addr}/items")
    paginator = GitHub::REST::ArrayPaginator(Int32).new(uri, http)
    paginator.to_a.should be_empty

    empty_server.close
    empty_wg.wait
  end
end

describe GitHub::REST::ObjectPaginator do
  wrapped_pages = [
    {total_count: 5, items: [1, 2, 3]},
    {total_count: 5, items: [4, 5]},
  ]

  server = HTTP::Server.new do |context|
    request, response = context.request, context.response
    page = (request.query_params["page"]? || "1").to_i
    data = wrapped_pages[page - 1]
    base = URI.parse("http://#{request.headers["Host"]}#{request.path}")
    if wrapped_pages.size > 1
      response.headers["Link"] = link_header(base, page, wrapped_pages.size)
    end
    response.content_type = "application/json"
    data.to_json(response)
  end
  addr = server.bind_unused_port
  base = URI.parse("http://#{addr}/items?page=1&per_page=3")
  client_uri = URI.parse("http://#{addr}")
  wg = WaitGroup.new

  before_all { wg.spawn { server.listen } }
  after_all { server.close; wg.wait }

  it "extracts items from wrapper objects" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ObjectPaginator(Int32).new(base, http)
    paginator.to_a.should eq [1, 2, 3, 4, 5]
  end

  it "is multi-pass" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ObjectPaginator(Int32).new(base, http)
    paginator.to_a.should eq [1, 2, 3, 4, 5]
    paginator.to_a.should eq [1, 2, 3, 4, 5]
  end

  it "uses the initial response without re-fetching" do
    http = HTTP::Client.new(client_uri)
    initial = http.get(base.request_target)
    paginator = GitHub::REST::ObjectPaginator(Int32).new(base, http, initial)
    paginator.to_a.should eq [1, 2, 3, 4, 5]
  end

  it "exposes total_count" do
    http = HTTP::Client.new(client_uri)
    paginator = GitHub::REST::ObjectPaginator(Int32).new(base, http)
    paginator.total_count.should be_nil
    paginator.to_a
    paginator.total_count.should eq 5
  end

  it "handles an empty array in wrapper" do
    empty_server = HTTP::Server.new do |context|
      context.response.content_type = "application/json"
      {total_count: 0, items: [] of Int32}.to_json(context.response)
    end
    empty_addr = empty_server.bind_unused_port
    empty_wg = WaitGroup.new
    empty_wg.spawn { empty_server.listen }

    http = HTTP::Client.new(URI.parse("http://#{empty_addr}"))
    uri = URI.parse("http://#{empty_addr}/items")
    paginator = GitHub::REST::ObjectPaginator(Int32).new(uri, http)
    paginator.to_a.should be_empty

    empty_server.close
    empty_wg.wait
  end
end

describe "paginator error handling" do
  it "raises REST::Error on non-success during pagination" do
    error_server = HTTP::Server.new do |context|
      request = context.request
      page = (request.query_params["page"]? || "1").to_i
      if page == 1
        base = URI.parse("http://#{request.headers["Host"]}#{request.path}")
        context.response.headers["Link"] = %(<#{base}?page=2>; rel="next")
        context.response.content_type = "application/json"
        [1, 2].to_json(context.response)
      else
        context.response.status = HTTP::Status::FORBIDDEN
        context.response.content_type = "application/json"
        %q({"message":"rate limit exceeded"}).to_s(context.response)
      end
    end
    error_addr = error_server.bind_unused_port
    error_wg = WaitGroup.new
    error_wg.spawn { error_server.listen }

    http = HTTP::Client.new(URI.parse("http://#{error_addr}"))
    uri = URI.parse("http://#{error_addr}/items")
    paginator = GitHub::REST::ArrayPaginator(Int32).new(uri, http)
    ex = expect_raises(GitHub::REST::Error) { paginator.to_a }
    ex.status.should eq HTTP::Status::FORBIDDEN
    ex.body.should contain "rate limit"

    error_server.close
    error_wg.wait
  end
end
