# AGENTS.md

Guidelines for agentic coding assistants working on `jekyll-devto`, a Jekyll plugin that cross-posts a blog to dev.to, complete, through dev.to's own RSS import.

## What it does

Two parts that work together:

1. **The feed** (`lib/jekyll/devto/generator.rb`, `feed.xml`, `html.rb`). A generator adds `/devto.xml`: RSS 2.0 with the full rendered post in `<content:encoded>`. `HTML.convert` turns Rouge code blocks into plain `<pre><code>` without line-number gutters and makes root-relative `src`/`href` absolute, only inside real tags.
2. **The publisher** (`publisher.rb`, `client.rb`, `exe/jekyll-devto`). `jekyll-devto publish` reads the **live** feed, keeps the posts published in the last N days, finds the draft dev.to imported from each one (by `canonical_url`, then title), and publishes it through the dev.to API. It does a dry run unless you pass `--publish`.

The design rule: work from the HTML Jekyll already rendered, and never edit the user's posts.

## Commands

```bash
bundle install
bundle exec rake test                                          # whole suite
bundle exec ruby -Ilib -Itest test/html_test.rb                # one file
bundle exec ruby -Ilib -Itest test/html_test.rb -n /highlight/ # tests matching a pattern

bundle exec exe/jekyll-devto publish --feed https://example.com/devto.xml   # dry run
gem build jekyll-devto.gemspec
```

The publisher needs `DEVTO_API_KEY` (https://dev.to/settings/extensions). Never paste a real key into a command line, a file or a log.

## File organization

```
lib/
├── jekyll-devto.rb          # entry point Jekyll loads from `plugins:`
└── jekyll/devto/
    ├── generator.rb         # adds the feed page
    ├── feed.xml             # Liquid template for the feed
    ├── html.rb              # HTML transform + the devto_html Liquid filter
    ├── publisher.rb         # finds and publishes drafts
    ├── client.rb            # dev.to API client (two calls)
    └── version.rb
exe/jekyll-devto             # CLI
examples/devto-publish.yml   # GitHub Actions workflow users copy
test/
├── fixtures/site/           # a small Jekyll site the feed tests build
├── html_test.rb             # HTML transform, string in, string out
├── feed_test.rb             # builds the fixture site, replays dev.to's import
├── publisher_test.rb        # publisher against a FakeClient
└── network_test.rb          # redirects (local TCP server), network errors, CLI
docs/blog-notes.md           # research notes for a blog post; not shipped in the gem
.github/workflows/ci.yml     # tests on Ruby 3.1 to 4.0
.github/workflows/release-please.yml  # release PR, tag, and gem publish
release-please-config.json   # release-please settings (initial-version, sections)
.release-please-manifest.json  # current released version, written by release-please
```

## Code style

- `# frozen_string_literal: true` at the top of every Ruby file. Only syntax that Ruby 3.1 parses (see Ruby versions below).
- Single quotes for strings without interpolation or escapes. There is no linter on purpose (the project keeps its dependencies to a minimum), so match the surrounding code.
- Stdlib only at runtime (`net/http`, `rexml`, `json`). The gem's runtime dependencies are `jekyll` and `rexml`; add another only with a strong reason.
- Comments say **why**, especially when behaviour follows from something dev.to does. Name the Forem class or file (`Feeds::CleanHtml`, `Article#evaluate_front_matter`) so the next person can check it.
- Errors a user can hit (network, bad feed, bad option, rejected post) end as a one-line message and exit 1, never a backtrace. Network failures become `Client::Error` (`Client::NETWORK_ERRORS`).
- In docs and comments: no em dashes. Use a comma, a colon or a full stop.

## Ruby versions

- **The minimum is what matters.** The gem runs on the Jekyll site's Ruby, not ours, so `required_ruby_version` (`>= 3.1`) is a promise about syntax and stdlib. Endless methods (`def x = 1`, 3.0+) and anonymous block forwarding (`(&)`, 3.1+) are fine. Not allowed in `lib/` or `exe/`: anonymous argument forwarding `(*)` and `(**)` and `Data.define` (3.2+), `it` (3.4+).
- **CI runs 3.1, 3.2, 3.3, 3.4 and 4.0.** The 3.1 job is the guard for the minimum; keep it in the matrix until the minimum is raised on purpose. `Gemfile.lock` is gitignored so each job resolves gems for its own Ruby.
- **Development uses Ruby 4.0** (`.tool-versions`, `4.0.6`). CI's `4.0` resolves to the newest patch (4.0.7 at the time of writing); bump the pin once asdf's ruby plugin lists it.
- Raising the minimum is a breaking change for users: `feat!:` or a `BREAKING CHANGE:` footer, and update the matrix and the gemspec together.

## Testing

- **Write the failing test first.** Every bug fix comes with a test that fails on `main` and passes with the fix. Check that it really fails before trusting it.
- Feed behaviour is tested by **building the fixture site**, not by testing the template in isolation. Add a case to `test/fixtures/site/_posts/` when markup matters.
- `test_survives_the_dev_to_import` replays dev.to's pipeline: Feedjira, then every `class` attribute removed (what `Feeds::CleanHtml` does), then ReverseMarkdown. Keep that test passing; it is the closest thing to dev.to we can run.
- The publisher never calls the real API in tests. Use `FakeClient` (`reject:` for a refused PUT, `ignore:` for a PUT dev.to accepts but leaves as a draft).
- Before claiming a change works on real sites, build one: the author's blog (Chirpy, `~/code/mine/juanvqz.github.io`) with the gem as a `path:` dependency, and a fresh `jekyll new` (minima) site. Compare `_site/devto.xml`. The only expected difference between runs is `lastBuildDate`.

## dev.to behaviour this code depends on

Checked against [Forem's source](https://github.com/forem/forem); the README lists them for users. The ones that shape the code:

- The import uses `<content:encoded>`, falling back to the summary (`Feeds::AssembleArticleMarkdown#get_content`).
- Imports are always drafts, and the body's own front matter says `published: false`. That front matter wins over the API's `published` field (`Article#evaluate_front_matter`), so the publisher flips it inside the body, **only** within the front matter.
- The PUT response has no `published` field. The publisher confirms by listing the drafts again.
- Every `class` attribute is stripped before conversion, so a code block's language cannot travel as a class. The feed carries it as `data-lang`, and the publisher writes it into the draft's fences, matching blocks by their first line of code (`HTML.code_blocks`, `Publisher.with_code_languages`).
- The feed is converted to Markdown only when block tags outnumber blank lines (`Feeds::AssembleArticleMarkdown#html_content?`); otherwise dev.to stores the raw HTML. `HTML.without_blank_lines` keeps every post on the Markdown path. The feed tests replay that check.
- Duplicates match on title or link, per user.

If a change relies on dev.to behaving some way, read the Forem source first and name the file in the commit or comment.

## Commit messages

Conventional Commits, as in [noko-for-raycast](https://github.com/JuanVqz/noko-for-raycast):

```
type(scope): description
```

- Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `ci`, `chore`.
- Scope is optional and names the area: `feed`, `html`, `publisher`, `client`, `cli`, `examples`.
- Description in the imperative, lower case, no trailing period: `fix(html): strip gutters from highlight tags`.
- The body explains why, wrapped at 72 columns.
- `BREAKING CHANGE:` in the footer for incompatible changes.
- No AI attribution of any kind: no `Co-Authored-By` naming an assistant, no "Generated with" lines.

release-please reads these to version the gem and write the CHANGELOG: `fix`, `perf`, `refactor` and `docs` = patch, `feat` = minor, `BREAKING CHANGE` = major (minor while `0.x`). `test`, `ci` and `chore` stay out of the CHANGELOG. Squash-merge pull requests so the PR title becomes the commit, and give the PR a Conventional Commit title.

## Git workflow

- Never push directly to `main`. Branch off `main` as `<type>/<description>` (`fix/highlight-linenos`, `docs/release-steps`) and open a pull request.
- Never force push to `main`.
- Never `git commit --amend` a commit that was already pushed, unless the maintainer asks for it explicitly.
- Never edit `CHANGELOG.md` or the version in `lib/jekyll/devto/version.rb` by hand: release-please owns both.

## Releases

Automated with release-please (`release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release-please.yml`).

- On every push to `main`, release-please keeps a `chore(main): release x.y.z` pull request open with the bump in `lib/jekyll/devto/version.rb` and the new `CHANGELOG.md` entries.
- Merging that pull request tags `vx.y.z` (no component in the tag), creates the GitHub release, runs the tests on Ruby 4.0, and pushes the gem. **That merge is the publish.** A version number on RubyGems can never be reused, even after a yank, so only the maintainer merges it.
- Nothing else publishes. Never run `gem push` by hand or add another workflow that does.

### Choosing the version

- **The first release is `0.1.0` because of `"initial-version": "0.1.0"`.** Without it, release-please ignores a `0.0.0` manifest when there is no previous release and falls back to `1.0.0` (`initialReleaseVersion()` in `src/strategies/base.ts`). Once a tag exists, `initial-version` is ignored, so it can stay.
- **`bump-minor-pre-major: true`**: while on `0.x`, a breaking change bumps the minor, not the major.
- **To force a specific version** (for example the jump to `1.0.0`), put `Release-As: x.y.z` in the **body** of a commit on `main`, through a pull request:

  ```bash
  git commit --allow-empty -m "chore: release 1.0.0" -m "Release-As: 1.0.0"
  ```

  With a squash merge the line must survive into the squash commit's body (`gh pr merge --squash --body "Release-As: 1.0.0"`); the web UI may replace the body with the commit list.
- **To fix the release notes** of an already merged pull request, edit that pull request's description and add a `BEGIN_COMMIT_OVERRIDE` ... `END_COMMIT_OVERRIDE` block with the corrected Conventional Commit; release-please uses it on its next run.

### Release pull request quirks

- **release-please only rewrites its pull request when the release notes change.** A hidden commit (`chore`, `ci`, `test`) on `main` leaves it as it was ("PR ... remained the same" in the log), including stale file contents and the date in the CHANGELOG header. To regenerate it: close the release pull request with `--delete-branch`, remove its `autorelease: pending` label, and re-run the latest `Release` workflow run (`gh run rerun <id>`). Closing it publishes nothing.
- **The date in the CHANGELOG entry is the day the pull request was built**, not the day it is merged. If it sat open for a while, regenerate it as above before merging.
- **Do not seed `CHANGELOG.md` by hand.** A file with no version header gets appended below release-please's own header with H1 turned into H2 (`src/updaters/changelog.ts`), which is how a stray `## Changelog` appeared once.

### Trusted publishing

The publish job gets a short-lived RubyGems key from the job's OIDC token (`rubygems/configure-rubygems-credentials`, `id-token: write`). There is no RubyGems secret in the repo.

- **MFA is not a problem.** The gemspec sets `rubygems_mfa_required`, but rubygems.org lets trusted publisher keys through: `Pusher#verify_mfa_requirement` passes when the key is not owned by a user, and `ApiKey#mfa_authorized?` returns true for OIDC keys.
- **The publisher is registered on rubygems.org** as the gem's permanent trusted publisher (since the 0.1.0 push; managed under the gem's Trusted Publishers page) with exactly: gem `jekyll-devto`, type GitHub Actions, owner `JuanVqz`, repository `jekyll-devto`, workflow `release-please.yml`, environment empty.
- **Only for a brand-new gem: a pending publisher expires 12 hours after it is created** (`expires_at: 12.hours.from_now` in `OIDC::PendingTrustedPublishersController`; `Pusher` only accepts unexpired ones). This mattered for 0.1.0 only; after the first push the publisher is permanent. If the gem is ever re-registered from scratch, create the pending publisher right before merging the release pull request.
- **If the publish job fails with 401 or "no trusted publisher"**, the registration and the workflow disagree. Usual causes: the workflow file was renamed, the job got an `environment:`, or the repository moved. Change both sides together.

### Repository settings release-please needs

- Settings → Actions → General → Workflow permissions: **"Allow GitHub Actions to create and approve pull requests"** must be on, or release-please cannot open its pull request. Check with `gh api repos/JuanVqz/jekyll-devto/actions/permissions/workflow` (`can_approve_pull_request_reviews: true`).

## Where it runs

The gem was extracted from the author's blog, https://www.juanvasquez.dev (`~/code/mine/juanvqz.github.io`, Jekyll + Chirpy on GitHub Pages).

- The blog uses the gem (`gem 'jekyll-devto'` plus `plugins:`) and runs `bundle exec jekyll-devto publish` from its `.github/workflows/devto-publish.yml`. It used to carry an in-repo copy of the feed, filter and script; those are gone, so fixes go here.
- dev.to's feed source points at `https://www.juanvasquez.dev/devto.xml`, with "Mark the RSS source as canonical URL" and "Replace self-referential links" on. dev.to fetches on its own schedule; Dashboard → RSS Import Feeds → Import History shows each fetch ("N imported, M skipped"; skipped means a title or link already exists on the account).
- The blog's deploy cron is 13:00 UTC, but GitHub has been running it around 17:30 to 18:45 UTC, and posts are dated 09:00 -0600. Keep that delay in mind for any claim about when a post goes out.
- dev.to's one-time "Import from XML" box takes at most 25 entries and 500 KB (`Feeds::ImportFromXml`) and ignores the feed source's settings. It is not the normal path.
