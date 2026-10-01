# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'open3'
require 'socket'
require 'stringio'

class NetworkTest < Minitest::Test
  FEED = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <item><title>Live</title><link>https://example.com/live/</link><pubDate>#{Time.now.utc.rfc2822}</pubDate></item>
    </channel></rss>
  XML

  # A tiny HTTP server: each path maps to [status, headers, body].
  def serve(routes)
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new do
      loop do
        client = server.accept
        path = client.gets.to_s.split[1]
        nil until client.gets.to_s.strip.empty?
        status, headers, body = routes.fetch(path, [404, {}, ''])
        head = headers.merge('Content-Length' => body.bytesize, 'Connection' => 'close').map { |k, v| "#{k}: #{v}\r\n" }.join
        client.write("HTTP/1.1 #{status} X\r\n#{head}\r\n#{body}")
        client.close
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}"
  ensure
    thread&.kill
    server&.close
  end

  def due_posts(feed)
    Jekyll::Devto::Publisher.new(feed: feed, client: nil, out: StringIO.new, err: StringIO.new).due_posts
  end

  def test_follows_redirects_to_the_feed
    serve('/old' => [301, { 'Location' => '/devto.xml' }, ''], '/devto.xml' => [200, {}, FEED]) do |base|
      assert_equal ['Live'], due_posts("#{base}/old").map(&:title)
    end
  end

  def test_gives_up_after_too_many_redirects
    serve('/loop' => [302, { 'Location' => '/loop' }, '']) do |base|
      error = assert_raises(Jekyll::Devto::Client::Error) { due_posts("#{base}/loop") }
      assert_includes error.message, 'more than 5 redirects'
    end
  end

  def test_a_feed_that_is_not_found_is_an_error
    serve({}) do |base|
      error = assert_raises(Jekyll::Devto::Client::Error) { due_posts("#{base}/devto.xml") }
      assert_includes error.message, '404'
    end
  end

  def test_client_network_errors_become_client_errors
    Net::HTTP.stub(:start, ->(*) { raise OpenSSL::SSL::SSLError, 'certificate verify failed' }) do
      error = assert_raises(Jekyll::Devto::Client::Error) { Jekyll::Devto::Client.new('key').drafts }
      assert_equal 'GET /api/articles/me/unpublished failed: certificate verify failed', error.message
    end
  end

  # The PUTs went out but the confirming list failed: every sent post is
  # reported, and the run fails instead of crashing.
  def test_a_failed_confirmation_keeps_the_summary
    client = Object.new
    calls = 0
    client.define_singleton_method(:drafts) do
      calls += 1
      raise Jekyll::Devto::Client::Error, 'GET failed: timeout' if calls > 1

      [{ 'id' => 1, 'title' => 'Live', 'body_markdown' => "---\npublished: false\n---\n" }]
    end
    client.define_singleton_method(:update) { |*| { 'url' => 'https://dev.to/x' } }

    Dir.mktmpdir do |dir|
      File.write(feed = File.join(dir, 'devto.xml'), FEED)
      err = StringIO.new
      failures = Jekyll::Devto::Publisher.new(feed: feed, client: client, publish: true, out: StringIO.new, err: err).run

      assert_equal 1, failures
      assert_includes err.string, 'could not confirm 1 post(s) went out: GET failed: timeout'
    end
  end

  EXE = File.expand_path('../exe/jekyll-devto', __dir__)

  def test_bad_options_print_usage_not_a_backtrace
    _, err, status = Open3.capture3(RbConfig.ruby, EXE, 'publish', '--days', 'abc')

    refute status.success?
    assert_includes err, 'invalid argument: --days abc'
    assert_includes err, 'Usage: jekyll-devto publish'
    refute_includes err, '.rb:'
  end

  def test_unknown_option
    _, err, status = Open3.capture3(RbConfig.ruby, EXE, 'publish', '--nope')

    refute status.success?
    assert_includes err, 'invalid option: --nope'
  end
end
