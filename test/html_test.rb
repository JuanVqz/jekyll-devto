# frozen_string_literal: true

require 'test_helper'

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

    assert_equal "<pre><code>def x\nend\n</code></pre>", convert(html)
  end

  def test_unwraps_a_block_without_a_gutter
    html = %(<div class="language-git highlighter-rouge"><div class="highlight"><pre class="highlight"><code>git log\n</code></pre></div></div>)

    assert_equal "<pre><code>git log\n</code></pre>", convert(html)
  end

  def test_matches_a_wrapper_with_extra_classes_attributes_and_whitespace
    html = %(<div file="a.rb" class="language-ruby nolineno highlighter-rouge"><div class="highlight"><pre class="highlight"><code>x\n</code></pre></div>    </div>)

    assert_equal "<pre><code>x\n</code></pre>", convert(html)
  end

  def test_keeps_escaped_entities_in_code
    html = %(<div class="language-html highlighter-rouge"><div class="highlight"><pre class="highlight"><code><span class="nt">&lt;a</span> <span class="na">href=</span><span class="s">"/x"</span><span class="nt">&gt;</span>\n</code></pre></div></div>)

    assert_equal %(<pre><code>&lt;a href="/x"&gt;\n</code></pre>), convert(html)
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

    assert_equal "<pre><code>def x\nend\n</code></pre>", convert(html)
  end

  def test_unwraps_a_highlight_tag_without_linenos
    html = %(<figure class="highlight"><pre><code class="language-ruby" data-lang="ruby"><span class="nb">puts</span> <span class="s2">"x"</span></code></pre></figure>)

    assert_equal %(<pre><code>puts "x"</code></pre>), convert(html)
  end

  def test_base_url_with_a_trailing_slash
    assert_equal %(<a href="https://example.com/x">x</a>), Jekyll::Devto::HTML.convert(%(<a href="/x">x</a>), "#{BASE}/")
  end
end
