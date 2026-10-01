# frozen_string_literal: true

module Jekyll
  module Devto
    # Adds the dev.to feed to the site as a page, the same way jekyll-feed adds
    # its own. Posts render before pages, so `post.content` in the template is
    # the final HTML.
    class Generator < Jekyll::Generator
      safe true
      priority :lowest

      DEFAULT_PATH = "devto.xml"
      TEMPLATE = File.expand_path("feed.xml", __dir__)

      def generate(site)
        path = feed_path(site)
        if site.pages.any? { |page| page.url == "/#{path}" }
          Jekyll.logger.warn "jekyll-devto:", "a page already lives at /#{path}, not generating the feed"
          return
        end

        site.pages << feed_page(site, path)
      end

      private

      def feed_path(site)
        config = site.config["devto"]
        path = config.is_a?(Hash) ? config["path"] : nil
        (path || DEFAULT_PATH).sub(%r{\A/}, "")
      end

      def feed_page(site, path)
        PageWithoutAFile.new(site, __dir__, File.dirname(path).sub(/\A\.\z/, ""), File.basename(path)).tap do |page|
          page.content = File.read(TEMPLATE)
          page.data["layout"] = nil
          page.data["sitemap"] = false
          page.data["permalink"] = "/#{path}"
        end
      end
    end
  end
end
