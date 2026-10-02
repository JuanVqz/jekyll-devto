# jekyll-devto

[![Gem Version](https://badge.fury.io/rb/jekyll-devto.svg)](https://badge.fury.io/rb/jekyll-devto)
[![CI](https://github.com/JuanVqz/jekyll-devto/actions/workflows/ci.yml/badge.svg)](https://github.com/JuanVqz/jekyll-devto/actions/workflows/ci.yml)

Cross-post a Jekyll blog to [dev.to](https://dev.to), complete, through dev.to's own RSS import.

dev.to can import posts from your feed, but with a typical Jekyll feed you get:

- **Cut-off posts.** Feeds that carry a summary, or an empty `<content src="...">` link (the
  [Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) theme's feed does this), import as the
  summary only.
- **Line numbers inside the code.** Rouge with `line_numbers: true`, or a `{% highlight ruby linenos %}` tag, renders the code as a table with a gutter, and dev.to's HTML to Markdown conversion keeps the numbers as code.
- **Broken links and images.** Root-relative URLs point nowhere once the post lives on dev.to.
- **Drafts you publish by hand.** dev.to always imports as drafts.

This gem fixes all four:

1. A generator that adds `/devto.xml`, an RSS feed with the full rendered post, plain code blocks and absolute URLs.
2. A `jekyll-devto publish` command that publishes the imported drafts once their post is live on your site.

It works from the HTML Jekyll already rendered, so anything your theme and Kramdown support comes through. It never edits your posts.

## Install

```ruby
# Gemfile
gem 'jekyll-devto'
```

```yaml
# _config.yml
url: "https://example.com" # required: links in the feed are absolute
plugins:
  - jekyll-devto
```

Build, and the feed is at `https://example.com/devto.xml`.

On dev.to, go to **Settings → Extensions → Publishing to DEV Community from RSS**, set the feed URL
to your `devto.xml`, and turn on **Mark the RSS source as canonical URL by default** so search
engines treat your site as the original.

## Configuration

All optional.

```yaml
devto:
  path: "/devto.xml" # where the feed is written
  limit: 20          # newest posts to include (default: all)
  cover: image       # use each post's image as its dev.to cover (default: no cover)
```

To keep a post off dev.to, set `devto: false` in its front matter.

**Cover image.** No cover by default. Many Open Graph images, including the ones [jekyll-og-image](https://github.com/igor-alexandrov/jekyll-og-image) and Chirpy produce, already carry the post title, which dev.to shows right under the cover, and without a cover dev.to generates its own share image. To add one:

- `devto_cover:` on a post sets that post's cover, and always wins. `devto_cover: true` uses the post's `image`, and `devto_cover: false` turns the cover off for that post.
- `cover: image` under `devto:` in `_config.yml` uses each post's `image` (a path, a URL, or `{ path: ... }`) for every post, for sites whose images have no title on them.

```yaml
devto_cover: /assets/img/devto-cover.png # optional, per post
```

`jekyll-devto publish` adds the cover to the draft; a cover already set on the dev.to draft is kept. dev.to crops covers to 1000×420.

**Tags and series.** dev.to keeps only the first four tags, as lowercase letters and digits (`tailwind-css` becomes `tailwindcss`). `devto_tags` picks them for dev.to; it is used for the import and also replaces the tags of a draft that was already imported. `devto_series` puts the post in a dev.to series, created if it does not exist; a series already set on the draft is kept.

```yaml
devto_tags: [ruby, rails, jekyll, opensource]
devto_series: "Rails upgrades"
```

## Publishing the drafts

```sh
export DEVTO_API_KEY=... # https://dev.to/settings/extensions, "DEV Community API Keys"

bundle exec jekyll-devto publish             # dry run: prints what it would publish
bundle exec jekyll-devto publish --publish   # publishes
bundle exec jekyll-devto publish --days 14 --feed https://example.com/devto.xml
```

It reads your **live** feed (`url` + `devto.path` from `_config.yml`, or `--feed`), keeps the posts
published in the last `--days` days (7 by default, never future-dated ones), finds the draft dev.to
imported from each one, and publishes it.

- Drafts are matched by `canonical_url` first, then by title.
- Older drafts are left alone on purpose. The feed carries your whole archive, and publishing every
  match would push years of old posts to dev.to at once.
- A post dev.to rejects is reported and the run moves on. Afterwards the drafts are listed again, and
  any post still among them fails the run. The command exits 1 if anything failed.

### On a schedule with GitHub Actions

[`examples/devto-publish.yml`](examples/devto-publish.yml) runs it after each deploy and once a day.
Add the key as a repository secret:

```sh
gh secret set DEVTO_API_KEY
```

## dev.to behaviour worth knowing

Checked against [Forem's source](https://github.com/forem/forem), the software dev.to runs:

- **Drafts match on title or link.** dev.to skips a feed entry when you already have an article with
  the same title or link (`Feeds::CheckItemPreviouslyImported`). A deleted draft is imported again on
  the next fetch while its post is still in the feed.
- **The imported body says `published: false` in its own front matter**, and that wins over the
  API's `published` field (`Article#evaluate_front_matter`). The publish command flips it inside the
  body. A plain `published: true` request leaves the post a draft.
- **The import drops the language of every code block.** dev.to removes every `class` attribute before converting (`Feeds::CleanHtml`), so a fence never gets a language from the feed. The feed marks each block with `data-lang`, which survives, and `jekyll-devto publish` writes that language into the draft's fences, matching blocks by their first line of code.
- **Sometimes the import keeps the raw HTML instead of Markdown.** dev.to converts the feed only when block tags outnumber blank lines (`Feeds::AssembleArticleMarkdown#html_content?`). The feed removes blank lines between tags and writes newlines inside code as `&#10;`, so every post takes the Markdown path. Drafts imported before this change may still be raw HTML; their code keeps no language.
- **Only the first four tags are kept**, stripped to letters and digits and lowercased. Use `devto_tags` to choose them.
- **"Replace self-referential links with DEV-specific links"** rewrites links between your posts to
  their dev.to articles at import time, drafts included. Publish the linked post first, or leave
  that option off.
- **The one-time "Import from XML" box** takes at most 25 entries and 500 KB
  (`Feeds::ImportFromXml`). Use `devto.limit` if you need it.

## Development

```sh
bundle install
bundle exec rake test
```

The feed tests build a fixture site and replay dev.to's import (Feedjira, Forem's class stripping,
ReverseMarkdown) to check what dev.to would store.

## Releases

`jekyll-devto` follows [Semantic Versioning](https://semver.org), and releases are automated with [release-please](https://github.com/googleapis/release-please) from [Conventional Commits](https://www.conventionalcommits.org):

- `fix:` bumps the **PATCH** version, and so do `perf:`, `refactor:` and `docs:`
- `feat:` bumps the **MINOR** version
- `BREAKING CHANGE:` in the commit footer bumps the **MAJOR** version (the MINOR one while the version is `0.x`)
- `test:`, `ci:` and `chore:` are left out of the CHANGELOG and do not trigger a release on their own

### Steps to release a new version

1. Merge pull requests to `main` with Conventional Commit titles (`fix(html): ...`, `feat(publisher): ...`)
2. release-please keeps a `chore(main): release x.y.z` pull request open with the version bump in `lib/jekyll/devto/version.rb` and the new `CHANGELOG.md` entries
3. Review and merge that pull request
4. The `Release` workflow tags `vx.y.z`, creates the GitHub release, runs the tests, and pushes the gem to RubyGems with [trusted publishing](https://guides.rubygems.org/trusted-publishing/), so no API key or MFA code is needed

## License

MIT
