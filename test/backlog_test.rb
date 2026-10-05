# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require_relative 'publisher_test'

# --backlog N publishes up to N drafts of posts older than the --days window,
# newest first, so an archive dev.to imported as drafts goes out a few at a
# time instead of all at once (each publish notifies the author's followers).
class BacklogTest < Minitest::Test
  NOW = Time.utc(2026, 1, 12, 18)
  FakeClient = PublisherTest::FakeClient

  FEED = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <item><title>Later</title><link>https://example.com/later/</link><pubDate>Tue, 13 Jan 2026 15:00:00 +0000</pubDate></item>
      <item><title>Fresh</title><link>https://example.com/fresh/</link><pubDate>Mon, 12 Jan 2026 15:00:00 +0000</pubDate></item>
      <item><title>Old A</title><link>https://example.com/a/</link><pubDate>Thu, 01 Jan 2026 15:00:00 +0000</pubDate></item>
      <item><title>Old B</title><link>https://example.com/b/</link><pubDate>Sat, 20 Dec 2025 15:00:00 +0000</pubDate></item>
      <item><title>Old C</title><link>https://example.com/c/</link><pubDate>Mon, 01 Dec 2025 15:00:00 +0000</pubDate></item>
    </channel></rss>
  XML

  def draft(id, title)
    { 'id' => id, 'title' => title, 'body_markdown' => "---\ntitle: #{title}\npublished: false\n---\n\nBody" }
  end

  def run_backlog(client, backlog:, publish: true)
    Dir.mktmpdir do |dir|
      File.write(feed = File.join(dir, 'devto.xml'), FEED)
      out = StringIO.new
      err = StringIO.new
      failures = Jekyll::Devto::Publisher.new(feed: feed, client: client, days: 7, publish: publish, backlog: backlog,
                                              now: NOW, out: out, err: err).run
      [failures, out.string, err.string]
    end
  end

  def all_drafts
    [draft(1, 'Fresh'), draft(2, 'Old A'), draft(3, 'Old B'), draft(4, 'Old C'), draft(5, 'Later')]
  end

  def published_titles(client)
    ids = client.updates.map(&:first)
    all_drafts.select { |d| ids.include?(d['id']) }.map { |d| d['title'] }
  end

  def test_without_backlog_old_drafts_stay_drafts
    client = FakeClient.new(all_drafts)
    run_backlog(client, backlog: 0)

    assert_equal ['Fresh'], published_titles(client)
  end

  def test_backlog_publishes_the_newest_old_draft
    client = FakeClient.new(all_drafts)
    failures, out, = run_backlog(client, backlog: 1)

    assert_equal 0, failures
    assert_equal %w[Fresh Old\ A], published_titles(client)
    assert_includes out, 'Backlog: 3 older posts, publishing up to 1'
  end

  def test_backlog_takes_n_in_order
    client = FakeClient.new(all_drafts)
    run_backlog(client, backlog: 2)

    assert_equal ['Fresh', 'Old A', 'Old B'], published_titles(client)
  end

  # An old post with no draft was already published (or never imported); it
  # does not use up the backlog, and it is not reported, since the whole
  # archive would otherwise be listed on every run.
  def test_backlog_skips_old_posts_without_a_draft
    client = FakeClient.new([draft(1, 'Fresh'), draft(3, 'Old B'), draft(4, 'Old C')])
    _, out, = run_backlog(client, backlog: 1)

    assert_equal %w[Fresh Old\ B], published_titles(client)
    refute_includes out, '"Old A"'
  end

  # Thursdays and Saturdays usually have no new post in the window; the
  # backlog must still go out.
  def test_backlog_runs_when_the_window_is_empty
    client = FakeClient.new([draft(2, 'Old A'), draft(3, 'Old B')])
    Dir.mktmpdir do |dir|
      File.write(feed = File.join(dir, 'devto.xml'), FEED.sub(%r{^.*<title>Fresh</title>.*\n}, ''))
      failures = Jekyll::Devto::Publisher.new(feed: feed, client: client, days: 7, publish: true, backlog: 1,
                                              now: NOW, out: StringIO.new, err: StringIO.new).run

      assert_equal 0, failures
    end

    assert_equal ['Old A'], published_titles(client)
  end

  def test_backlog_never_publishes_a_future_post
    client = FakeClient.new([draft(5, 'Later')])
    run_backlog(client, backlog: 3)

    assert_empty client.updates
  end

  def test_dry_run_shows_the_backlog_pick_and_changes_nothing
    client = FakeClient.new(all_drafts)
    _, out, = run_backlog(client, backlog: 1, publish: false)

    assert_includes out, %(would publish "Old A" -> dev.to draft 2 (backlog))
    assert_empty client.updates
  end

  def test_an_empty_backlog_says_so
    client = FakeClient.new([draft(1, 'Fresh')])
    _, out, = run_backlog(client, backlog: 1)

    assert_includes out, 'Backlog: no draft left to publish'
  end  # A draft dev.to rejects must not hold the backlog back on every run: the
  # next old draft still goes out, and the run still reports the failure.
  def test_a_rejected_backlog_draft_does_not_use_up_the_count
    client = FakeClient.new(all_drafts, reject: [2])
    failures, = run_backlog(client, backlog: 1)

    assert_equal 1, failures
    assert_equal [1, 2, 3], client.updates.map(&:first)
  end

  # Matching falls back to the title, so an old post sharing a title with a
  # post in the window must not land on the draft the window already used.
  def test_backlog_does_not_reuse_a_draft_matched_by_title
    feed = FEED.sub('<title>Old A</title>', '<title>Fresh</title>')
    client = FakeClient.new([draft(1, 'Fresh'), draft(3, 'Old B')])
    Dir.mktmpdir do |dir|
      File.write(path = File.join(dir, 'devto.xml'), feed)
      Jekyll::Devto::Publisher.new(feed: path, client: client, days: 7, publish: true, backlog: 1,
                                   now: NOW, out: StringIO.new, err: StringIO.new).run
    end

    assert_equal [1, 3], client.updates.map(&:first)
  end
end
