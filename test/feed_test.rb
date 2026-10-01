# frozen_string_literal: true

require "test_helper"
require "feedjira"
require "reverse_markdown"
require "rexml/document"

class FeedTest < Minitest::Test
  include SiteBuilder

  def feed = build_feed
  def items = REXML::Document.new(feed).get_elements("//item")
  def item(title) = items.find { |i| i.elements["title"].text == title }

  def test_is_valid_rss_with_every_post_that_did_not_opt_out
    assert_equal ["Plain Post", "Code & Links"], items.map { |i| i.elements["title"].text }
  end

  def test_carries_the_full_post
    body = item("Code & Links").elements["content:encoded"].text

    assert_includes body, "<pre><code>def hello"
    assert_includes body, %(<a href="https://example.com/about/">link</a>)
    assert_includes body, %(<img src="https://example.com/assets/pic.png")
    assert_includes body, %(href="//cdn.example.com/x.js")
    refute_includes body, "rouge-table"
  end

  def test_leaves_code_samples_as_written
    body = item("Code & Links").elements["content:encoded"].text

    assert_includes body, %(&lt;img src="/logo.png"&gt;)
    assert_includes body, %(&lt;a href="/raw"&gt;plain block&lt;/a&gt;)
  end

  def test_uses_tags_then_categories
    assert_equal %w[ruby jekyll], item("Code & Links").get_elements("category").map(&:text)
    assert_equal %w[notes], item("Plain Post").get_elements("category").map(&:text)
  end

  def test_links_and_self_reference
    assert_equal "https://example.com/2026/01/10/code-and-links.html", item("Code & Links").elements["link"].text
    assert_includes feed, %(<atom:link href="https://example.com/devto.xml")
  end

  def test_limit_and_path_are_configurable
    custom = build_feed("devto" => { "path" => "/feeds/dev.xml", "limit" => 1 })

    assert_equal ["Plain Post"], REXML::Document.new(custom).get_elements("//item").map { |i| i.elements["title"].text }
  end

  # Replays dev.to's import: Feedjira picks `content` (content:encoded) over the
  # summary, Forem's CleanHtml drops every class, ReverseMarkdown converts.
  def test_survives_the_dev_to_import
    entry = Feedjira.parse(feed).entries.find { |e| e.title == "Code & Links" }
    html = Nokogiri::HTML(entry.content).tap { |doc| doc.xpath("//@class").remove }.to_html
    markdown = ReverseMarkdown.convert(html, github_flavored: true)

    assert_includes markdown, "```\ndef hello\n  puts \"hi\"\nend\n```"
    refute_match(/```\n1\n/, markdown)
    assert_includes markdown, "[link](https://example.com/about/)"
  end
end
