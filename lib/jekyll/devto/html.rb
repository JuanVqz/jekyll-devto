# frozen_string_literal: true

module Jekyll
  module Devto
    # Turns a rendered post body into HTML that survives dev.to's RSS import.
    #
    # dev.to strips every class attribute and converts the HTML to Markdown
    # (Forem's Feeds::CleanHtml, then ReverseMarkdown). Two things break on the
    # way:
    #
    # - Rouge with `line_numbers: true`, or a `{% highlight lang linenos %}` tag,
    #   renders the code as a table with a gutter, and the gutter numbers end
    #   up inside the code.
    # - Root-relative links and images point nowhere once the post lives on
    #   dev.to.
    #
    # The code language cannot travel as a class, so each block carries it as
    # data-lang, which CleanHtml keeps. ReverseMarkdown ignores it; the
    # publisher reads it from the feed and writes it into the draft's fences.
    module HTML
      # Kramdown block options such as {: .nolineno } or {: file="..." } add
      # classes and attributes to the wrapper, so the class is matched anywhere
      # in the tag.
      ROUGE_BLOCK = %r{
        <div\b(?<attrs>[^>]*\bclass="[^"]*\bhighlighter-rouge\b[^"]*"[^>]*)>\s*
        <div\ class="highlight">\s*<pre\ class="highlight"><code>
        (?<body>.*?)
        </code></pre>\s*</div>\s*</div>
      }mx

      # What the {% highlight %} Liquid tag renders.
      HIGHLIGHT_TAG = %r{
        <figure\ class="highlight"><pre><code\b(?<attrs>[^>]*)>
        (?<body>.*?)
        </code></pre></figure>
      }mx

      # Kramdown names the cells rouge-gutter and rouge-code; the highlight tag
      # names them gutter and code.
      GUTTER = %r{<table class="rouge-table">.*?<td class="(?:rouge-)?code"><pre>(?<code>.*?)</pre>}m

      # Real tags only. Code samples reach the HTML escaped (&lt;img src="/x"&gt;),
      # so they never match and are left exactly as written.
      TAG = /<[a-zA-Z][^>]*>/
      ROOT_RELATIVE = %r{\b(src|href)="/(?!/)}

      # Kramdown's name for a fence with no language.
      NO_LANGUAGE = %w[plaintext text].freeze

      module_function

      def convert(html, base_url)
        html.to_s
          .gsub(ROUGE_BLOCK) { plain_code(Regexp.last_match[:body], rouge_language(Regexp.last_match[:attrs])) }
          .gsub(HIGHLIGHT_TAG) { plain_code(Regexp.last_match[:body], Regexp.last_match[:attrs][/\bdata-lang="([^"]+)"/, 1]) }
          .gsub(TAG) { |tag| tag.gsub(ROOT_RELATIVE, %(\\1="#{base_url.to_s.chomp('/')}/)) }
      end

      # Forem converts the HTML to Markdown only when block tags outnumber blank
      # lines (Feeds::AssembleArticleMarkdown#html_content?); otherwise it stores
      # the raw HTML, and none of the conversion (fences, languages) happens.
      # Blank lines between tags are only formatting, and a newline inside code
      # written as &#10; is the same character once parsed, so the post reads
      # the same while the count of blank lines drops to zero.
      ZERO_WIDTH_PARAGRAPH = '<p>&#8203;</p>'

      # dev.to's import deletes every "```\n\n```" after converting
      # (Feeds::AssembleArticleMarkdown), so two code blocks with nothing between
      # them become one block holding both. A paragraph with a zero-width space
      # keeps them apart and does not show.
      def separate_code_blocks(html)
        html.to_s.gsub(%r{</pre>\s*(?=<pre\b)}) { "</pre>\n#{ZERO_WIDTH_PARAGRAPH}\n" }
      end

      def without_blank_lines(html)
        html.split(%r{(<pre\b[^>]*>.*?</pre>)}m).map do |part|
          part.start_with?('<pre') ? part.gsub("\n", '&#10;') : part.gsub(/\n\s*\n/, "\n")
        end.join
      end

      # Kramdown writes the fence's language as a language-* class, and the
      # language can hold any non-space character (c#, shell.session). It is
      # read from the class attribute only, so another attribute such as
      # file="docs/language-notes.md" cannot pass for it.
      def rouge_language(attrs)
        attrs[/\bclass="([^"]*)"/, 1].to_s[/(?:\A|\s)language-(\S+)/, 1]
      end

      def plain_code(body, language)
        body = Regexp.last_match[:code] if body =~ GUTTER
        attribute = language && !NO_LANGUAGE.include?(language) ? %( data-lang="#{language}") : ''

        "<pre#{attribute}><code>#{body.gsub(/<[^>]+>/, '')}</code></pre>"
      end

      # A post image as an absolute URL. Takes a path, a URL, or Chirpy's
      # { "path" => ... } hash; nil when there is nothing to point at.
      def absolute_url(value, base_url)
        path = value.is_a?(Hash) ? value['path'] : value
        # Front matter is YAML, so this can be true, a number or a list; only a
        # string is a path, anything else is ignored rather than crashing the build.
        return unless path.is_a?(String)

        path = path.strip
        return if path.empty?
        return path if path.match?(%r{\Ahttps?://})
        return "#{base_url.to_s[/\A[a-z][a-z0-9+.-]*:/i] || 'https:'}#{path}" if path.start_with?('//')

        "#{base_url.to_s.chomp('/')}/#{path.sub(%r{\A/}, '')}"
      end

      CODE_BLOCK = %r{<pre\b(?<attrs>[^>]*)><code\b[^>]*>(?<code>.*?)</code></pre>}m

      # Every code block in a converted body, in order, as [language, first
      # line of code] (language is nil when the block has none). The first line
      # is what identifies the block in the dev.to draft, whose fences do not
      # always line up one to one with the blocks.
      def code_blocks(html)
        html.to_s.scan(CODE_BLOCK).map do |attrs, code|
          [attrs[/\bdata-lang="([^"]+)"/, 1], first_line(unescape(code))]
        end
      end

      # Whitespace is collapsed for the comparison: some Markdown converters
      # squeeze runs of spaces inside code.
      def first_line(code)
        code.to_s.each_line.map { |line| line.split.join(' ') }.find { |line| !line.empty? }.to_s
      end

      # The entities this HTML can carry inside code; enough to compare it with
      # the Markdown dev.to stores. &amp; goes last so "&amp;lt;" stays "&lt;".
      def unescape(text)
        text.gsub(/&#(\d+);/) { Regexp.last_match(1).to_i.chr(Encoding::UTF_8) }
            .gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"').gsub('&#39;', "'").gsub('&amp;', '&')
      end
    end

    # Liquid filter for the feed template.
    module Filters
      # devto_tags as a list, whether the front matter wrote a YAML list or a
      # string ("ruby, rails" or "ruby rails", as Jekyll accepts for tags), so
      # the import and the publisher see the same tags. nil when there are none.
      def devto_list(value)
        list = case value
               when Array then value.filter_map { |item| devto_text(item) }
               when String, Numeric then value.to_s.split(/[,\s]+/)
               else []
               end
        list = list.map(&:strip).reject(&:empty?)
        list unless list.empty?
      end

      # A front matter value as text when it is one (a string or a number);
      # nil for true, false, lists and hashes, which mean nothing as a name.
      def devto_text(value)
        text = value.to_s.strip if value.is_a?(String) || value.is_a?(Numeric)
        text unless text.to_s.empty?
      end

      def devto_url(value, base_url)
        HTML.absolute_url(value, base_url).to_s
      end

      def devto_html(html, base_url)
        HTML.without_blank_lines(HTML.separate_code_blocks(HTML.convert(html, base_url)))
      end
    end
  end
end

# The CLI loads this file without Jekyll, only for HTML.code_blocks.
Liquid::Template.register_filter(Jekyll::Devto::Filters) if defined?(Liquid::Template)
