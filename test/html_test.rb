# frozen_string_literal: true

require 'test_helper'
require 'nokogiri'

class HTMLTest < Minitest::Test
  BASE = 'https://example.com'

  def convert(html) = Jekyll::Devto::HTML.convert(html, BASE)

  def test_strips_the_rouge_gutter
    html = <<~HTML.chomp
      <div class="language-ruby highlighter-rouge"><div class="highlight"><pre class="highlight"><code><table class="rouge-table"><tbody><tr><td class="rouge-gutter gl"><pre class="lineno">1
      2
      </pre></td><td class="rouge-code"><pre><span class="k">def</span> <span class="nf">x</span>
      <span class="k">end</span>
      </pre></td></tr></tbody></table></code></pre></div></div>
    HTML

    assert_equal %(<pre data-lang="ruby"><code>def x\nend\n</code></pre>), convert(html)
  end

  def test_unwraps_a_block_without_a_gutter
    html = %(<div class="language-git highlighter-rouge"><div class="highlight"><pre class="highlight"><code>git log\n</code></pre></div></div>)

    assert_equal %(<pre data-lang="git"><code>git log\n</code></pre>), convert(html)
  end

  def test_matches_a_wrapper_with_extra_classes_attributes_and_whitespace
    html = %(<div file="a.rb" class="language-ruby nolineno highlighter-rouge"><div class="highlight"><pre class="highlight"><code>x\n</code></pre></div>    </div>)

    assert_equal %(<pre data-lang="ruby"><code>x\n</code></pre>), convert(html)
  end

  def test_keeps_escaped_entities_in_code
    html = %(<div class="language-html highlighter-rouge"><div class="highlight"><pre class="highlight"><code><span class="nt">&lt;a</span> <span class="na">href=</span><span class="s">"/x"</span><span class="nt">&gt;</span>\n</code></pre></div></div>)

    assert_equal %(<pre data-lang="html"><code>&lt;a href="/x"&gt;\n</code></pre>), convert(html)
  end

  def test_makes_root_relative_links_and_images_absolute
    html = %(<a href="/about/">a</a> <img src="/pic.png" alt="p" />)

    assert_equal %(<a href="https://example.com/about/">a</a> <img src="https://example.com/pic.png" alt="p" />), convert(html)
  end

  def test_leaves_protocol_relative_absolute_and_fragment_links_alone
    html = %(<a href="//cdn.example.com/x">a</a> <a href="https://other.com/">b</a> <a href="#top">c</a>)

    assert_equal html, convert(html)
  end

  def test_leaves_code_samples_that_look_like_links_alone
    html = %(<code>&lt;img src="/logo.png"&gt;</code>)

    assert_equal html, convert(html)
  end

  def test_strips_the_gutter_of_a_highlight_tag_with_linenos
    html = <<~HTML.chomp
      <figure class="highlight"><pre><code class="language-ruby" data-lang="ruby"><table class="rouge-table"><tbody><tr><td class="gutter gl"><pre class="lineno">1
      2
      </pre></td><td class="code"><pre><span class="k">def</span> <span class="nf">x</span>
      <span class="k">end</span>
      </pre></td></tr></tbody></table></code></pre></figure>
    HTML

    assert_equal %(<pre data-lang="ruby"><code>def x\nend\n</code></pre>), convert(html)
  end

  def test_unwraps_a_highlight_tag_without_linenos
    html = %(<figure class="highlight"><pre><code class="language-ruby" data-lang="ruby"><span class="nb">puts</span> <span class="s2">"x"</span></code></pre></figure>)

    assert_equal %(<pre data-lang="ruby"><code>puts "x"</code></pre>), convert(html)
  end

  # plaintext is what Kramdown calls a fence with no language.
  def test_plaintext_blocks_get_no_language
    html = %(<div class="language-plaintext highlighter-rouge"><div class="highlight"><pre class="highlight"><code>x\n</code></pre></div></div>)

    assert_equal "<pre><code>x\n</code></pre>", convert(html)
  end

  def test_language_keeps_any_non_space_character
    html = %(<div class="language-c# highlighter-rouge"><div class="highlight"><pre class="highlight"><code>x\n</code></pre></div></div>)
  
    assert_equal %(<pre data-lang="c#"><code>x\n</code></pre>), convert(html)
  end
  
  def test_language_comes_from_the_class_attribute_only
    html = %(<div file="docs/language-notes.md" class="language-ruby highlighter-rouge"><div class="highlight"><pre class="highlight"><code>x\n</code></pre></div></div>)
  
    assert_equal %(<pre data-lang="ruby"><code>x\n</code></pre>), convert(html)
  end
  
  def test_code_blocks_list_language_and_first_line_in_order
    html = %(<pre data-lang="ruby"><code>\n  a = 1&#10;b</code></pre><p>x</p><pre><code>c &amp;&amp; d&#10;</code></pre><pre data-lang="bash"><code>echo &quot;hi&quot; &gt; f</code></pre>)

    assert_equal [['ruby', 'a = 1'], [nil, 'c && d'], ['bash', 'echo "hi" > f']], Jekyll::Devto::HTML.code_blocks(html)
  end

  # Forem converts the feed HTML to Markdown only when block tags outnumber
  # blank lines (Feeds::AssembleArticleMarkdown#html_content?); otherwise it
  # stores the raw HTML and skips CleanHtml and the code conversion.
  def forem_converts?(content)
    block_tags = content.scan(/<\s*(p|div|h[1-6]|ul|ol|li|blockquote|pre|table|section|figure)[\s>]/i).size
    block_tags.positive? && block_tags > content.scan(/\n\s*\n/).size
  end

  def test_output_always_takes_forems_markdown_path
    html = "<p>One</p>\n\n<p>Two</p>\n\n<pre><code>a\n\n\nb\n</code></pre>\n\n<p>Three</p>\n"

    refute forem_converts?(html)
    assert forem_converts?(Jekyll::Devto::HTML.without_blank_lines(convert(html)))
  end

  def test_code_keeps_its_blank_lines_once_parsed
    html = %(<div class="language-ruby highlighter-rouge"><div class="highlight"><pre class="highlight"><code>a\n\nb\n</code></pre></div></div>)

    assert_equal "a\n\nb\n", Nokogiri::HTML(Jekyll::Devto::HTML.without_blank_lines(convert(html))).at('code').text
  end

  def test_absolute_url_takes_a_string_a_hash_or_nothing
    assert_equal 'https://example.com/a.png', Jekyll::Devto::HTML.absolute_url('/a.png', BASE)
    assert_equal 'https://example.com/b.png', Jekyll::Devto::HTML.absolute_url({ 'path' => '/b.png' }, BASE)
    assert_equal 'https://cdn.example.com/c.png', Jekyll::Devto::HTML.absolute_url('https://cdn.example.com/c.png', BASE)
    assert_equal 'https://example.com/d.png', Jekyll::Devto::HTML.absolute_url('d.png', "#{BASE}/")
    assert_equal 'https://cdn.example.com/e.png', Jekyll::Devto::HTML.absolute_url('//cdn.example.com/e.png', BASE)
    assert_nil Jekyll::Devto::HTML.absolute_url(nil, BASE)
    assert_nil Jekyll::Devto::HTML.absolute_url({ 'alt' => 'no path' }, BASE)
  end

  def test_devto_list_accepts_a_list_or_a_string
    filters = Object.new.extend(Jekyll::Devto::Filters)

    assert_equal %w[ruby rails], filters.devto_list(['ruby', ' rails '])
    assert_equal %w[ruby rails jekyll], filters.devto_list('ruby, rails jekyll')
    assert_nil filters.devto_list(nil)
    assert_nil filters.devto_list([])
    assert_nil filters.devto_list(' , ')
  end

  def test_adjacent_code_blocks_get_an_invisible_separator
    html = %(<pre><code>a</code></pre>\n\n<pre data-lang="yaml"><code>b</code></pre><p>x</p><pre><code>c</code></pre>)

    assert_equal %(<pre><code>a</code></pre>\n<p>&#8203;</p>\n<pre data-lang="yaml"><code>b</code></pre><p>x</p><pre><code>c</code></pre>),
                 Jekyll::Devto::HTML.separate_code_blocks(html)
  end

  def test_base_url_with_a_trailing_slash
    assert_equal %(<a href="https://example.com/x">x</a>), Jekyll::Devto::HTML.convert(%(<a href="/x">x</a>), "#{BASE}/")
  end
end
