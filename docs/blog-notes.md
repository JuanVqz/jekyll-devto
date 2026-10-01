# Blog post notes: cross-posting a Jekyll blog to dev.to, complete

Raw material for a post on juanvasquez.dev. Everything here was checked during the work on
2026-10-01; sources are next to each claim. Not shipped in the gem.

## The problem

- juanvasquez.dev (Jekyll + Chirpy, GitHub Pages) had been connected to dev.to's "Publishing to DEV
  Community from RSS" for a long time, pointing at `/feed.xml`.
- Every imported post was cut short, so each one had to be re-synced by hand before publishing on
  dev.to. That defeats the point of the integration.
- 41 posts were waiting to go out.

## Root cause

- Chirpy's `feed.xml` (Atom) writes each entry as
  `<content type="text/html" src="https://.../post/" />` plus a `<summary>`. The content element is
  an empty link. The summary in this blog's override was `truncatewords: 90`.
- dev.to runs Forem. `Feeds::AssembleArticleMarkdown#get_content` is `@item.content || @item.summary`.
  Feedjira returns nil for an empty Atom `<content>`, so dev.to used the 90-word summary.
  Source: forem/forem `app/services/feeds/assemble_article_markdown.rb`.
- This is Chirpy upstream behaviour, not something the blog broke.

## Decisions

- **A second feed, not a fuller feed.xml.** feed.xml is read by the GitHub profile README, and its
  final `replace: '&', '&amp;'` would corrupt the escaped entities inside code blocks if it carried
  full HTML. `/devto.xml` is RSS 2.0 with the full post in `<content:encoded>`.
- **RSS, not JSON Feed.** Feedjira 3.2 (Forem's version) can parse JSON Feed, but dev.to only
  documents RSS. No benefit in relying on something undocumented.
- **feed.xml stays a summary.** It is Chirpy's default and common practice: readers see the summary
  and click through. Full content is only needed in the feed dev.to imports.
- **Updated the existing feed source rather than adding a new one.** Duplicate detection is per user
  (`user.articles`), not per source, and the canonical and referential-link options live on the
  source (`feed_source.mark_canonical`, `feed_source.referential_link`). Two sources (feed.xml and
  devto.xml) would race, and if feed.xml won the post would import truncated.
- **Publish window of 7 days.** The feed holds the whole archive (43 posts). Publishing every matching
  draft would push years of old posts at once, "Happy New Year 2023" included.
- **Daily retry, not every 3 hours.** One post a week. The run right after the deploy does the work;
  one daily retry covers a draft dev.to had not imported yet.

## Things dev.to does that are not documented (all from Forem's source)

1. **Imports are always drafts.** `AssembleArticleMarkdown` hardcodes `published: false` in the
   front matter it writes. No setting changes that.
2. **That front matter wins over the API.** `Article#evaluate_front_matter` sets `published` from the
   body's front matter on every save, so `PUT /api/articles/:id` with only `published: true` leaves
   the post a draft. The body itself has to say `published: true`.
3. **The PUT response has no `published` field** (`api/v1/articles/show.json.jbuilder` +
   `_article.json.jbuilder`). To confirm a publish you have to list the drafts again.
4. **Every class attribute is stripped before conversion** (`Feeds::CleanHtml`:
   `doc.xpath("//@class").remove`). ReverseMarkdown reads the code language from a parent
   `highlight-<lang>` class, so the language can never arrive through RSS. Code imports unhighlighted.
5. **Duplicates match on title OR link** (`Feeds::CheckItemPreviouslyImported`). A deleted draft is
   imported again on the next fetch while the post is still in the feed. A renamed post makes a
   second draft.
6. **Only the first 4 tags are kept, stripped to letters and digits** (`get_tags`). `tailwind-css`
   becomes `tailwindcss`.
7. **"Replace self-referential links"** (`find_and_replace_possible_links!`) rewrites links between
   your posts to the dev.to article imported from the target, found by `feed_source_url`, drafts
   included. If the target stays a draft, readers get a link that does not work for them. Five
   posts on this blog link to other posts.
8. **Feeds are only fetched for users active in the last 3 months** (`Feeds::Import#filter_feed_sources`:
   `last_article_at` or `last_presence_at` within 3 months).
9. **The one-time "Import from XML" box** (`Feeds::ImportFromXml`) takes at most 25 entries and
   500 KB, and runs without the feed source, so canonical comes from account settings instead.
   This blog's feed (43 entries, ~428 KB) would be rejected.
10. **API v1 needs** `Accept: application/vnd.forem.api-v1+json`. `GET /api/articles/me/unpublished`
    returns `body_markdown` and `canonical_url`; `per_page` max is 1000 (`API_PER_PAGE_MAX`).

## Jekyll and Chirpy traps hit along the way

- **Rouge line numbers.** Chirpy sets `kramdown.syntax_highlighter_opts.block.line_numbers: true`, so
  every fenced block is a `<table class="rouge-table">` with a gutter. After dev.to's conversion the
  numbers sat inside the code (`1\n2\nbundle add ...`). Fix: rewrite each block to a plain
  `<pre><code>` and drop the highlighting spans.
- **Kramdown block options.** `{: .nolineno }` adds a class and `{: file="..." }` adds an attribute to
  the wrapper `<div>`, so a regex expecting exactly `class="language-x highlighter-rouge"` skipped
  those blocks. Caught in review, reproduced with a probe post.
- **Rewriting URLs inside code.** A naive `replace: 'src="/'` also rewrote code samples like
  `` `<img src="/logo.png">` `` because Kramdown leaves quotes unescaped inside code. Code reaches the
  HTML with `<` escaped as `&lt;`, so rewriting only inside real tags (`<[a-zA-Z][^>]*>`) leaves
  samples untouched. Caught in review.
- **Liquid's `replace` cannot do regex**, hence a small Ruby filter in `_plugins/`.
- **The cron is not when you think.** The deploy cron is 13:00 UTC, but GitHub ran it between 17:30
  and 18:45 UTC. Posts are dated 09:00 -0600 (15:00 UTC), and Jekyll excludes future posts
  (`Jekyll::Publisher#hidden_in_the_future?`), so a punctual cron would have missed the post that day.
  It works by accident of GitHub's delay.
- **A push cancels the running deploy** (`concurrency: cancel-in-progress`). The first deploy of the
  feed was cancelled by an unrelated push minutes later; the newer run shipped both.

## What happened with the first import

- Deleted the truncated drafts on dev.to before devto.xml existed. dev.to refused the new URL while it
  returned 404, so the source stayed on feed.xml for a while.
- dev.to's next fetch (of feed.xml) showed "1 imported, 19 skipped": 20 entries, exactly feed.xml's
  limit. The 19 were posts already on dev.to (title or link match). The one import was truncated.
- The script then reported no draft for that post. The Import History's ARTICLE column was empty:
  the draft no longer existed.
- Dashboard numbers at the time: 22 posts on dev.to, 9 articles imported over the source's
  lifetime, 231 items skipped.

## How it was verified

- Replayed dev.to's pipeline locally: Feedjira parse, Forem's `CleanHtml` (downloaded from
  forem/forem), ReverseMarkdown `github_flavored`. 43 entries, full bodies, 0 code blocks with line
  numbers.
- Probe post with every case (inline code sample, `{: .nolineno }`, `{: file= }`, plain block,
  root-relative link and image), built, inspected, deleted.
- The gem produces the same feed as the in-repo override for all 43 posts; the only difference
  is `lastBuildDate`.
- Fresh `jekyll new` (minima theme) site: valid feed, `{% highlight %}` and links survive the replay.
- The publish script was exercised against a stub API: a 422 on one post, a CRLF draft, a draft
  accepted but left unpublished. Real API: a bad key gives 401, and the first GitHub Actions run with
  the real key listed drafts and skipped correctly.

## Review findings worth telling

- Two rounds of review on the feed, two on the publisher. Real catches: code samples rewritten,
  Chirpy block options skipped, a rejected post aborting the whole run, a CRLF front matter not
  flipped.
- One suggested fix was wrong: checking `result["published"]` after the PUT. That field is not in the
  response, so the check would have failed every post. Verified against the jbuilder view before
  rejecting it.

## Existing tools (searched before building the gem)

- No Jekyll plugin for dev.to on RubyGems or GitHub (`jekyll devto`, `jekyll-devto`, `jekyll forem`).
- `jekyll-feed`: full content, but Chirpy ships its own feed, and no line-number handling.
- `sinedied/publish-devto` + `devto-cli` (★42, last push Jul 2024), `trystan2k/publish-blog-post`:
  push raw Markdown through the API. Jekyll-specific syntax arrives unrendered, they write the
  article `id` back into the post, and they publish on push, not on the post's date.
- `jekyll-crosspost-to-medium` (★262): the closest shape, Medium only.
- The gem's angle: use the HTML Jekyll already rendered, never touch the posts.

## Links

- PRs on the blog: JuanVqz/juanvqz.github.io #533 (feed), #534 (publisher)
- Forem: https://github.com/forem/forem (`app/services/feeds/`, `app/models/article.rb`,
  `app/controllers/concerns/api/articles_controller.rb`)

## Open for the post

- Screenshot of the Import History before and after.
- Before/after of a code block on dev.to.
- Confirm the first automatic publish end to end (canonical link points to juanvasquez.dev).
