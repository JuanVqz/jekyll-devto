# frozen_string_literal: true

require 'net/http'
require 'rexml/document'
require 'time'
require_relative 'client'

module Jekyll
  module Devto
    # Publishes the dev.to drafts of posts that are live on the site.
    #
    # dev.to's RSS import always creates drafts. This reads the site's dev.to
    # feed, keeps the posts published in the last `days` days, finds the draft
    # imported from each one, and publishes it. Older drafts are left alone on
    # purpose: the feed carries the whole archive, and publishing every match
    # would push years of old posts to dev.to at once.
    class Publisher
      MAX_REDIRECTS = 5

      Post = Struct.new(:title, :link, :date, keyword_init: true)

      def initialize(feed:, client:, days: 7, publish: false, now: Time.now, out: $stdout, err: $stderr)
        @feed = feed
        @client = client
        @days = days
        @publish = publish
        @now = now
        @out = out
        @err = err
      end

      # Returns the number of posts that failed to publish.
      def run
        posts = due_posts
        @out.puts "Posts live in the last #{@days} days: #{posts.size}"
        return 0 if posts.empty?

        drafts = @client.drafts
        @out.puts "Drafts on dev.to: #{drafts.size}"

        sent = {}
        failures = []
        posts.each do |post|
          draft = find_draft(drafts, post)
          next report_missing(post, drafts) unless draft

          unless @publish
            @out.puts "  would publish #{post.title.inspect} -> dev.to draft #{draft['id']}"
            next
          end

          # One rejected post must not stop the rest, or every retry would stop at it.
          begin
            result = @client.update(draft['id'], published: true, body_markdown: self.class.published_body(draft['body_markdown']))
            sent[draft['id']] = post
            @out.puts "  sent    #{post.title.inspect} -> #{result['url']}"
          rescue StandardError => e
            failures << post
            @err.puts "  FAILED  #{post.title.inspect}: #{e.message}"
          end
        end

        failures.concat(still_drafts(sent))
        @err.puts "#{failures.size} post(s) failed to publish" if failures.any?
        failures.size
      end

      # The imported body carries `published: false` in its own front matter,
      # and dev.to applies that over the request's `published` field, so it is
      # flipped inside the body as well.
      def self.published_body(markdown)
        # Only inside the front matter: up to the first closing ---, so a
        # "published: false" line in the post body is left alone.
        markdown.to_s.sub(/\A---\r?\n.*?^---[ \t]*\r?$/m) do |front_matter|
          front_matter.sub(/^published:[ \t]*false[ \t]*(?=\r?$)/, 'published: true')
        end
      end

      def due_posts
        REXML::Document.new(read_feed).get_elements('//item').filter_map do |item|
          date = Time.rfc2822(item.elements['pubDate'].text)
          next if date > @now || date < @now - (@days * 86_400)

          Post.new(title: item.elements['title'].text.to_s.strip, link: item.elements['link'].text.to_s.strip, date: date)
        end
      end

      private

      # Follows redirects (http to https, apex to www), which Net::HTTP does not.
      def read_feed
        return File.read(@feed) unless @feed.match?(%r{\Ahttps?://})

        uri = URI(@feed)
        MAX_REDIRECTS.succ.times do
          res = Net::HTTP.get_response(uri)
          return res.body if res.is_a?(Net::HTTPSuccess)
          raise Client::Error, "could not read #{@feed}: #{res.code}" unless res.is_a?(Net::HTTPRedirection)

          uri = URI.join(uri, res['location'])
        end
        raise Client::Error, "could not read #{@feed}: more than #{MAX_REDIRECTS} redirects"
      rescue *Client::NETWORK_ERRORS => e
        raise Client::Error, "could not read #{@feed}: #{e.message}"
      end

      # canonical_url first: dev.to sets it to the post's link when the feed
      # source has "Mark the RSS source as canonical URL" on. Title otherwise.
      def find_draft(drafts, post)
        drafts.find { |d| d['canonical_url'].to_s.chomp('/') == post.link.chomp('/') } ||
          drafts.find { |d| d['title'].to_s.strip == post.title }
      end

      def report_missing(post, drafts)
        @out.puts "  skip    #{post.title.inspect}: no dev.to draft (not imported yet, or already published)"
        near = drafts.map { |d| d['title'].to_s }.find { |t| t.downcase.include?(post.title.downcase[0, 20]) }
        @out.puts "          closest draft title: #{near.inspect}" if near
      end

      # The PUT response does not say whether the article is published, so ask
      # dev.to again: anything still in the drafts list did not go out.
      def still_drafts(sent)
        return [] if sent.empty?

        ids = @client.drafts.map { |d| d['id'] } & sent.keys
        ids.map { |id| sent[id] }.each { |post| @err.puts "  STILL A DRAFT: #{post.title.inspect}" }
      rescue Client::Error => e
        # The PUTs already went out, so say which posts could not be confirmed
        # rather than losing the summary.
        @err.puts "  could not confirm #{sent.size} post(s) went out: #{e.message}"
        sent.values
      end
    end
  end
end
