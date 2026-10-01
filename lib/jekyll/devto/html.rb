# frozen_string_literal: true

module Jekyll
  module Devto
    # Turns a rendered post body into HTML that survives dev.to's RSS import.
    #
    # dev.to strips every class attribute and converts the HTML to Markdown
    # (Forem's Feeds::CleanHtml, then ReverseMarkdown). Two things break on the
    # way:
    #
    # - Rouge with `line_numbers: true` renders each fenced block as a table
    #   with a gutter, and the gutter numbers end up inside the code.
    # - Root-relative links and images point nowhere once the post lives on
    #   dev.to.
    module HTML
      # Kramdown block options such as {: .nolineno } or {: file="..." } add
      # classes and attributes to the wrapper, so the class is matched anywhere
      # in the tag.
      ROUGE_BLOCK = %r{
        <div\b[^>]*\bclass="[^"]*\bhighlighter-rouge\b[^"]*"[^>]*>\s*
        <div\ class="highlight">\s*<pre\ class="highlight"><code>
        (?<body>.*?)
        </code></pre>\s*</div>\s*</div>
      }mx

      GUTTER = %r{<table class="rouge-table">.*?<td class="rouge-code"><pre>(?<code>.*?)</pre>}m

      # Real tags only. Code samples reach the HTML escaped (&lt;img src="/x"&gt;),
      # so they never match and are left exactly as written.
      TAG = /<[a-zA-Z][^>]*>/
      ROOT_RELATIVE = %r{\b(src|href)="/(?!/)}

      module_function

      def convert(html, base_url)
        html.to_s
          .gsub(ROUGE_BLOCK) { plain_code(Regexp.last_match[:body]) }
          .gsub(TAG) { |tag| tag.gsub(ROOT_RELATIVE, %(\\1="#{base_url.to_s.chomp('/')}/)) }
      end

      # The language is not kept: dev.to strips every class before converting,
      # so it would never arrive.
      def plain_code(body)
        body = Regexp.last_match[:code] if body =~ GUTTER

        "<pre><code>#{body.gsub(/<[^>]+>/, '')}</code></pre>"
      end
    end

    # Liquid filter for the feed template.
    module Filters
      def devto_html(html, base_url)
        HTML.convert(html, base_url)
      end
    end
  end
end

Liquid::Template.register_filter(Jekyll::Devto::Filters)
