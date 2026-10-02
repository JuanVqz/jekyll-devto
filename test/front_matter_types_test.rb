# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'stringio'
require 'yaml'

# Front matter is YAML, so a key the gem reads can arrive as any type: an
# author writes `devto_cover: true`, `devto_tags: ruby`, `image: 42` or a
# hash. Every one of those must build the site and produce a feed the
# publisher can read; a value the gem cannot use is ignored, never a crash.
#
# Regression for `devto_cover: true`, which reached a string method and
# raised NoMethodError, failing the whole Jekyll build.
class FrontMatterTypesTest < Minitest::Test
  include SiteBuilder

  VALUES = {
    'true' => true,
    'false' => false,
    'nil' => nil,
    'integer' => 42,
    'float' => 1.5,
    'empty string' => '',
    'string' => 'some text',
    'empty list' => [],
    'list' => ['a', 1, nil, true],
    'nested list' => [['x']],
    'empty hash' => {},
    'hash with path' => { 'path' => '/assets/x.png' },
    'hash without path' => { 'alt' => 'no path' },
    'hash with odd path' => { 'path' => true }
  }.freeze

  POST_KEYS = %w[devto_cover devto_tags devto_series image].freeze
  SITE_COVERS = ['image', true, false, nil, 'yes', 1, [], {}].freeze

  # A site with a single post whose front matter holds exactly this value, so
  # nothing in the shared fixtures can mask it.
  def feed_with_front_matter(front_matter, site = {})
    Dir.mktmpdir do |root|
      source = File.join(root, "site")
      FileUtils.mkdir_p(File.join(source, "_posts"))
      FileUtils.cp(File.join(FIXTURE_SITE, "_config.yml"), source)
      post = { "title" => "Typed" }.merge(front_matter)
      File.write(File.join(source, "_posts", "2026-01-05-typed.md"), "#{post.to_yaml}---\n\nBody with `code`.\n")
      config = Jekyll.configuration({ "source" => source, "destination" => File.join(root, "_site"), "quiet" => true,
                                      "plugins" => ["jekyll-devto"] }.merge(site))
      Jekyll::Site.new(config).process
      File.read(File.join(root, "_site", "devto.xml"))
    end
  end
  
  def feed_with_post_value(key, value, site = {})
    feed_with_front_matter({ key => value }, site)
  end

  def assert_usable(feed, context)
    document = REXML::Document.new(feed)
    refute_empty document.get_elements('//item'), "#{context}: the feed has no items"

    Dir.mktmpdir do |dir|
      File.write(path = File.join(dir, 'devto.xml'), feed)
      publisher = Jekyll::Devto::Publisher.new(feed: path, client: nil, days: 100_000, now: Time.utc(2026, 2, 1),
                                               out: StringIO.new, err: StringIO.new)
      posts = publisher.due_posts
      refute_empty posts, "#{context}: the publisher read no posts"
      posts.each { |post| Jekyll::Devto::Publisher.prepared_body("---\ntitle: X\npublished: false\n---\n\nBody", post) }
    end
  end

  POST_KEYS.each do |key|
    VALUES.each do |label, value|
      define_method("test_#{key}_as_#{label.tr(' ', '_')}") do
        assert_usable(feed_with_post_value(key, value), "#{key}: #{value.inspect}")
      end
    end
  end

  # image is only read for the cover when the site turns covers on.
  VALUES.each do |label, value|
    define_method("test_image_as_#{label.tr(' ', '_')}_with_site_covers_on") do
      feed = feed_with_post_value('image', value, 'devto' => { 'cover' => 'image' })
      assert_usable(feed, "image: #{value.inspect} with cover: image")
    end
  end

  SITE_COVERS.each do |value|
    define_method("test_site_cover_as_#{value.inspect.gsub(/\W/, '_')}") do
      assert_usable(build_feed('devto' => { 'cover' => value }), "devto.cover: #{value.inspect}")
    end
  end

  # The values the gem does use still mean what the README says.
  def test_values_that_mean_something_still_work
    assert_includes feed_with_post_value('devto_cover', '/c.png'), '<devto:cover>https://example.com/c.png</devto:cover>'
    assert_includes feed_with_post_value('devto_tags', 'ruby rails'), '<devto:tags>ruby,rails</devto:tags>'
    assert_includes feed_with_post_value('devto_series', 'Series'), '<devto:series>Series</devto:series>'
  end

  def test_values_the_gem_cannot_use_are_left_out
    refute_includes feed_with_post_value('devto_cover', 42), '<devto:cover>'
    refute_includes feed_with_post_value('devto_cover', { 'path' => true }), '<devto:cover>'
    refute_includes feed_with_post_value('devto_series', { 'a' => 1 }), '<devto:series>'
    refute_includes feed_with_post_value('devto_tags', {}), '<devto:tags>'
    refute_includes feed_with_post_value('devto_series', true), '<devto:series>'
    assert_includes feed_with_post_value('devto_tags', ['ruby', true, 7, nil]), '<devto:tags>ruby,7</devto:tags>'
  end
end
