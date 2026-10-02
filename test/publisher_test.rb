# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class PublisherTest < Minitest::Test
  NOW = Time.utc(2026, 1, 12, 18)

  FEED = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <item><title>New Post</title><link>https://example.com/new/</link><pubDate>Mon, 12 Jan 2026 15:00:00 +0000</pubDate></item>
      <item><title>Rejected &amp; Retried</title><link>https://example.com/rejected/</link><pubDate>Sun, 11 Jan 2026 15:00:00 +0000</pubDate></item>
      <item><title>Old Post</title><link>https://example.com/old/</link><pubDate>Thu, 01 Jan 2026 15:00:00 +0000</pubDate></item>
      <item><title>Scheduled</title><link>https://example.com/later/</link><pubDate>Tue, 13 Jan 2026 15:00:00 +0000</pubDate></item>
    </channel></rss>
  XML

  # Stands in for dev.to. `reject` answers a PUT with an error, `ignore`
  # accepts it but leaves the article a draft.
  class FakeClient
    attr_reader :updates

    def initialize(drafts, reject: [], ignore: [])
      @drafts = drafts
      @reject = reject
      @ignore = ignore
      @updates = []
    end

    def drafts = @drafts.map(&:dup)

    def update(id, article)
      @updates << [id, article]
      raise Jekyll::Devto::Client::Error, "PUT /api/articles/#{id} failed: 422" if @reject.include?(id)

      @drafts.reject! { |d| d['id'] == id } unless @ignore.include?(id)
      { 'url' => "https://dev.to/x/#{id}" }
    end
  end

  def draft(id, title, canonical: nil, body: "---\ntitle: #{title}\npublished: false\n---\n\nBody")
    { 'id' => id, 'title' => title, 'canonical_url' => canonical, 'body_markdown' => body }
  end

  def run_publisher(client, publish: true, days: 7)
    Dir.mktmpdir do |dir|
      feed = File.join(dir, 'devto.xml')
      File.write(feed, FEED)
      out = StringIO.new
      err = StringIO.new
      failures = Jekyll::Devto::Publisher.new(feed: feed, client: client, days: days, publish: publish, now: NOW, out: out, err: err).run
      [failures, out.string, err.string]
    end
  end

  def test_only_posts_inside_the_window_and_not_in_the_future
    failures, out, = run_publisher(FakeClient.new([]), publish: false)

    assert_equal 0, failures
    assert_includes out, 'Posts live in the last 7 days: 2'
    refute_includes out, 'Old Post'
    refute_includes out, 'Scheduled'
  end

  def test_dry_run_changes_nothing
    client = FakeClient.new([draft(1, 'New Post')])
    _, out, = run_publisher(client, publish: false)

    assert_includes out, %(would publish "New Post" -> dev.to draft 1)
    assert_empty client.updates
  end

  def test_publishes_and_flips_the_front_matter
    client = FakeClient.new([draft(1, 'New Post', body: "---\r\ntitle: New Post\r\npublished: false\r\n---\r\n\r\npublished: false stays in the body")])
    failures, out, = run_publisher(client)

    assert_equal 0, failures
    assert_includes out, 'sent'
    id, article = client.updates.first
    assert_equal 1, id
    assert article[:published]
    assert_equal "---\r\ntitle: New Post\r\npublished: true\r\n---\r\n\r\npublished: false stays in the body", article[:body_markdown]
  end

  def test_only_the_front_matter_is_flipped
    body = "---\ntitle: X\n---\n\nSet\npublished: false\nin your own front matter.\n\n---\n\nMore."

    assert_equal body, Jekyll::Devto::Publisher.published_body(body)
  end

  def test_code_languages_are_written_into_the_fences
    body = "---\ntitle: X\n---\n\nText\n\n```\nputs 1\n```\n\n- item\n\n  ```\n  ls\n  ```\n\n```\nplain\n```\n"
    expected = "---\ntitle: X\n---\n\nText\n\n```ruby\nputs 1\n```\n\n- item\n\n  ```bash\n  ls\n  ```\n\n```\nplain\n```\n"

    blocks = [['ruby', 'puts 1'], ['bash', 'ls'], [nil, 'plain']]

    assert_equal expected, Jekyll::Devto::Publisher.with_code_languages(body, blocks)
  end

  # dev.to does not turn every block into a fence (a block inside a list item
  # can come out unfenced), so blocks are matched by their first line of code,
  # never by position.
  def test_code_languages_match_by_content_when_a_block_is_missing
    body = "```\nputs 1\n```\n\n```\necho hi\n```\n"
    blocks = [['ruby', 'puts 1'], ['bash', 'ls -la'], ['bash', 'echo hi']]

    assert_equal "```ruby\nputs 1\n```\n\n```bash\necho hi\n```\n", Jekyll::Devto::Publisher.with_code_languages(body, blocks)
  end

  def test_code_languages_leave_an_unknown_block_alone
    body = "```\nedited on dev.to\n```\n"

    assert_equal body, Jekyll::Devto::Publisher.with_code_languages(body, [['ruby', 'puts 1']])
  end

  def test_code_languages_ignore_squeezed_spaces
    body = "```\nsrc/a.js test/a.js\n```\n"

    assert_equal "```js\nsrc/a.js test/a.js\n```\n", Jekyll::Devto::Publisher.with_code_languages(body, [['js', Jekyll::Devto::HTML.first_line("src/a.js      test/a.js")]])
  end

  def test_code_languages_keep_a_language_already_set
    body = "```js\nx\n```\n"

    assert_equal body, Jekyll::Devto::Publisher.with_code_languages(body, [['ruby', 'x']])
  end

  def test_code_languages_use_each_block_once_in_order
    body = "```\nx = 1\n```\n\n```\nx = 1\n```\n"
    blocks = [['ruby', 'x = 1'], ['python', 'x = 1']]

    assert_equal "```ruby\nx = 1\n```\n\n```python\nx = 1\n```\n", Jekyll::Devto::Publisher.with_code_languages(body, blocks)
  end

  # A block missing from the draft must not lend its language to a later
  # fence that starts the same way.
  def test_code_languages_never_match_a_block_behind_the_last_match
    body = "```\nls\n```\n\n```\nx = 1\n```\n"
    blocks = [['ruby', 'x = 1'], ['bash', 'ls'], ['python', 'x = 1']]
  
    assert_equal "```bash\nls\n```\n\n```python\nx = 1\n```\n", Jekyll::Devto::Publisher.with_code_languages(body, blocks)
  end
  
  def test_code_languages_recognize_a_fence_with_any_language
    body = "```c#\nint x;\n```\n\n```\nls\n```\n"
  
    assert_equal "```c#\nint x;\n```\n\n```bash\nls\n```\n", Jekyll::Devto::Publisher.with_code_languages(body, [['bash', 'ls']])
  end
  
  def test_cover_is_added_to_the_front_matter
    post = Jekyll::Devto::Publisher::Post.new(cover: 'https://example.com/og.png')
    body = "---\ntitle: X\npublished: false\n---\n\nBody"

    assert_equal "---\ntitle: X\npublished: true\ncover_image: https://example.com/og.png\n---\n\nBody", Jekyll::Devto::Publisher.prepared_body(body, post)
  end

  # A cover chosen on dev.to is the author's call; the feed does not replace it.
  def test_a_cover_already_on_the_draft_is_kept
    post = Jekyll::Devto::Publisher::Post.new(cover: 'https://example.com/og.png')
    body = "---\ntitle: X\ncover_image: https://dev.to/mine.png\n---\n"

    assert_equal body, Jekyll::Devto::Publisher.prepared_body(body, post)
  end

  def test_cover_keeps_crlf_line_endings
    post = Jekyll::Devto::Publisher::Post.new(cover: 'https://example.com/og.png')
    body = "---\r\ntitle: X\r\n---\r\n\r\nBody"

    assert_equal "---\r\ntitle: X\r\ncover_image: https://example.com/og.png\r\n---\r\n\r\nBody", Jekyll::Devto::Publisher.prepared_body(body, post)
  end

  def test_no_cover_leaves_the_front_matter_alone
    body = "---\r\ntitle: X\r\n---\r\n"

    assert_equal body, Jekyll::Devto::Publisher.prepared_body(body, Jekyll::Devto::Publisher::Post.new)
  end

  def test_matches_by_canonical_url_before_title
    client = FakeClient.new([draft(1, 'Renamed On Dev', canonical: 'https://example.com/new'), draft(2, 'New Post')])
    run_publisher(client)

    assert_equal [1], client.updates.map(&:first)
  end

  def test_a_rejected_post_does_not_stop_the_rest
    client = FakeClient.new([draft(2, 'Rejected & Retried'), draft(1, 'New Post')], reject: [2])
    failures, _, err = run_publisher(client)

    assert_equal 1, failures
    assert_includes err, %(FAILED  "Rejected & Retried")
    assert_equal [1, 2].sort, client.updates.map(&:first).sort
  end

  def test_a_post_left_as_a_draft_fails_the_run
    client = FakeClient.new([draft(1, 'New Post')], ignore: [1])
    failures, _, err = run_publisher(client)

    assert_equal 1, failures
    assert_includes err, %(STILL A DRAFT: "New Post")
  end

  def test_reports_a_missing_draft_with_the_closest_title
    client = FakeClient.new([draft(1, 'New Post!')])
    _, out, = run_publisher(client, publish: false)

    assert_includes out, %(closest draft title: "New Post!")
  end
end
