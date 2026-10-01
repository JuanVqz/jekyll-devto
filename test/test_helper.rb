# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "jekyll-devto"
require "jekyll/devto/client"
require "jekyll/devto/publisher"

FIXTURE_SITE = File.expand_path("fixtures/site", __dir__)

module SiteBuilder
  # Builds the fixture site once per config and returns the generated feed.
  def build_feed(overrides = {})
    @feeds ||= {}
    @feeds[overrides] ||= Dir.mktmpdir do |dest|
      config = Jekyll.configuration(
        { "source" => FIXTURE_SITE, "destination" => dest, "quiet" => true,
          "plugins" => ["jekyll-devto"] }.merge(overrides)
      )
      Jekyll::Site.new(config).process
      path = File.join(dest, (overrides.dig("devto", "path") || "devto.xml").sub(%r{\A/}, ""))
      File.read(path)
    end
  end
end
