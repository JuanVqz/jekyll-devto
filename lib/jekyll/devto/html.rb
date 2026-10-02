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
          .gsub(ROUGE_BLOCK) { plain_code(Regexp.last_match[:body], Regexp.last_match[:attrs][/\blanguage-([\w+-]+)/, 1]) }
          .gsub(HIGHLIGHT_TAG) { plain_code(Regexp.last_match[:body], Regexp.last_match[:attrs][/\bdata-lang="([^"]+)"/, 1]) }
          .gsub(TAG) { |tag| tag.gsub(ROOT_RELATIVE, %(\\1="#{base_url.to_s.chomp('/')}/)) }
      end

      # Forem converts the HTML to Markdown only when block tags outnumber blank
      # lines (Feeds::AssembleArticleMarkdown#html_content?); otherwise it stores
      # the raw HTML, and none of the conversion (fences, languages) happens.
      # Blank lines between tags are only formatting, and a newline inside code
      # written as &#10; is the same character once parsed, so the post reads
      # the same while the count of blank lines drops to zero.
      def without_blank_lines(html)
        html.split(%r{(<pre\b[^>]*>.*?</pre>)}m).map do |part|
          part.start_with?('<pre') ? part.gsub("\n", '&#10;') : part.gsub(/\n\s*\n/, "\n")
        end.join
      end

      def plain_code(body, language)
        body = Regexp.last_match[:code] if body =~ GUTTER
        attribute = language && !NO_LANGUAGE.include?(language) ? %( data-lang="#{language}") : ''

        "<pre#{attribute}><code>#{body.gsub(/<[^>]+>/, '')}</code></pre>"
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
      def devto_html(html, base_url)
        HTML.without_blank_lines(HTML.convert(html, base_url))
      end
    end
  end
end

# The CLI loads this file without Jekyll, only for HTML.code_blocks.
Liquid::Template.register_filter(Jekyll::Devto::Filters) if defined?(Liquid::Template)
