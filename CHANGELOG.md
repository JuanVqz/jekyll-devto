# main [(unreleased)](https://github.com/JuanVqz/jekyll-devto/commits/main)

- FEATURE: `/devto.xml`, an RSS feed with the full rendered post for dev.to's import: Rouge line numbers removed from fenced blocks and `{% highlight %}` tags, and root-relative links and images made absolute
- FEATURE: `jekyll-devto publish` publishes the imported dev.to drafts of posts published in the last N days, flipping the `published: false` that dev.to writes into the draft's own front matter
- FEATURE: Reading the feed follows redirects; network, SSL and timeout errors are reported instead of crashing
- DOC: An example GitHub Actions workflow and release steps in the README
