# frozen_string_literal: true

require 'test_helper'
require 'feedjira'
require 'reverse_markdown'
require 'rexml/document'

class FeedTest < Minitest::Test
  include SiteBuilder

  def feed = build_feed
  def items = REXML::Document.new(feed).get_elements('//item')
  def item(title) = items.find { |i| i.elements['title'].text == title }

  def test_is_valid_rss_with_every_post_that_did_not_opt_out
    assert_equal ['Plain Post', 'Code & Links', 'No Cover'], items.map { |i| i.elements['title'].text }
  end

  def test_carries_the_full_post
    body = item('Code & Links').elements['content:encoded'].text

    assert_includes body, '<pre data-lang="ruby"><code>def hello'
    assert_includes body, %(<a href="https://example.com/about/">link</a>)
    assert_includes body, %(<img src="https://example.com/assets/pic.png")
    assert_includes body, %(href="//cdn.example.com/x.js")
    refute_includes body, 'rouge-table'
  end

  def test_leaves_code_samples_as_written
    body = item('Code & Links').elements['content:encoded'].text

    assert_includes body, %(&lt;img src="/logo.png"&gt;)
    assert_includes body, %(&lt;a href="/raw"&gt;plain block&lt;/a&gt;)
  end

  # devto_tags wins so new imports already carry the tags chosen for dev.to.
  def test_uses_devto_tags_then_tags_then_categories
    assert_equal ['ruby', 'jekyll-plugins', 'Dev To', 'rss', 'five'], item('Code & Links').get_elements('category').map(&:text)
    assert_equal %w[notes], item('Plain Post').get_elements('category').map(&:text)
  end

  def test_devto_tags_and_series_are_carried_for_the_publisher
    assert_equal 'ruby,jekyll-plugins,Dev To,rss,five', item('Code & Links').elements['devto:tags'].text
    assert_equal 'Jekyll: the series', item('Code & Links').elements['devto:series'].text
    assert_nil item('Plain Post').elements['devto:tags']
    assert_nil item('Plain Post').elements['devto:series']
  end

  def test_links_and_self_reference
    assert_equal 'https://example.com/2026/01/10/code-and-links.html', item('Code & Links').elements['link'].text
    assert_includes feed, %(<atom:link href="https://example.com/devto.xml")
  end

  def test_highlight_tag_with_linenos_loses_its_gutter
    body = item('Code & Links').elements['content:encoded'].text

    assert_includes body, %(<pre data-lang="ruby"><code>def tagged&#10;  :linenos&#10;end&#10;</code></pre>)
    refute_includes body, 'rouge-table'
  end

  # Content links already carry baseurl (relative_url adds it), so it must not
  # be added again.
  def test_baseurl_is_not_doubled
    custom = build_feed('baseurl' => '/blog')
    body = REXML::Document.new(custom).get_elements('//item').find { |i| i.elements['title'].text == 'Code & Links' }.elements['content:encoded'].text

    assert_includes body, %(href="https://example.com/blog/scoped/")
    refute_includes body, '/blog/blog/'
  end

  def cover_in(feed_xml, title)
    REXML::Document.new(feed_xml).get_elements('//item').find { |i| i.elements['title'].text == title }.elements['devto:cover']&.text
  end

  # Many Open Graph images (jekyll-og-image, Chirpy) carry the post title,
  # which dev.to already shows under the cover, so covers are opt-in.
  def test_no_cover_by_default
    assert_nil item('Code & Links').elements['devto:cover']
    assert_nil item('No Cover').elements['devto:cover']
  end

  def test_devto_cover_is_used_without_the_site_option
    assert_equal 'https://cdn.example.com/cover.png', item('Plain Post').elements['devto:cover'].text
  end

  def test_site_option_uses_each_post_image
    custom = build_feed('devto' => { 'cover' => 'image' })

    assert_equal 'https://example.com/assets/img/og/code-and-links.png', cover_in(custom, 'Code & Links')
    assert_equal 'https://cdn.example.com/cover.png', cover_in(custom, 'Plain Post')
  end

  def test_devto_cover_true_opts_a_post_in_with_its_image
    custom = build_feed('defaults' => [{ 'scope' => { 'path' => '_posts/2026-01-10-code-and-links.md' }, 'values' => { 'devto_cover' => true } }])

    assert_equal 'https://example.com/assets/img/og/code-and-links.png', cover_in(custom, 'Code & Links')
  end

  def test_devto_cover_false_opts_a_post_out
    assert_nil cover_in(build_feed('devto' => { 'cover' => 'image' }), 'No Cover')
  end

  # Image paths leave baseurl out (Chirpy and jekyll-og-image add it when
  # rendering), so the cover needs it, unlike content links.
  def test_cover_carries_the_baseurl
    custom = build_feed('baseurl' => '/blog', 'devto' => { 'cover' => 'image' })

    assert_equal 'https://example.com/blog/assets/img/og/code-and-links.png', cover_in(custom, 'Code & Links')
  end

  def test_limit_and_path_are_configurable
    custom = build_feed('devto' => { 'path' => '/feeds/dev.xml', 'limit' => 1 })

    assert_equal ['Plain Post'], REXML::Document.new(custom).get_elements('//item').map { |i| i.elements['title'].text }
  end

  # Replays dev.to's import (Feeds::AssembleArticleMarkdown): Feedjira picks
  # `content` (content:encoded) over the summary; the HTML is converted only
  # when block tags outnumber blank lines (html_content?), otherwise it is
  # stored raw; CleanHtml drops every class; ReverseMarkdown converts.
  def dev_to_import(title)
    content = Feedjira.parse(feed).entries.find { |e| e.title == title }.content
    block_tags = content.scan(/<\s*(p|div|h[1-6]|ul|ol|li|blockquote|pre|table|section|figure)[\s>]/i).size
    return content unless block_tags > content.scan(/\n\s*\n/).size

    html = Nokogiri::HTML(content).tap { |doc| doc.xpath('//@class').remove }.to_html
    # Forem then deletes every "```\n\n```", which merges two code blocks that
    # have nothing between them (AssembleArticleMarkdown#assemble_body_markdown).
    ReverseMarkdown.convert(html, github_flavored: true).gsub("```\n\n```", '')
  end

  def test_survives_the_dev_to_import
    markdown = dev_to_import('Code & Links')

    assert_includes markdown, "```\ndef hello\n  puts \"hi\"\nend\n```"
    refute_match(/```\n1\n/, markdown)
    assert_includes markdown, '[link](https://example.com/about/)'
  end

  # The fixture post has several code blocks in a row; each must still be its
  # own block after dev.to's import, not one block holding all of them.
  def test_adjacent_code_blocks_stay_separate_through_the_import
    content = item('Code & Links').elements['content:encoded'].text
    fences = dev_to_import('Code & Links').scan(/^```/).size

    assert_equal Jekyll::Devto::HTML.code_blocks(content).size * 2, fences
  end

  # The whole path a code block takes: feed, dev.to's import, then the
  # publisher writing each block's language into the draft's fences.
  def test_code_languages_reach_the_published_draft
    content = item('Code & Links').elements['content:encoded'].text
    published = Jekyll::Devto::Publisher.with_code_languages(dev_to_import('Code & Links'), Jekyll::Devto::HTML.code_blocks(content))

    assert_includes published, "```ruby\ndef hello\n"
    assert_includes published, "```ruby\ndef tagged\n"
    assert_includes published, "```\n<a href=\"/raw\">plain block</a>"
  end
end
