# frozen_string_literal: true

require 'json'
require 'net/http'

module Jekyll
  module Devto
    # Minimal dev.to (Forem) API client: the two calls the publisher needs.
    class Client
      API = URI('https://dev.to/api/')
      PER_PAGE = 1000

      Error = Class.new(StandardError)

      def initialize(api_key)
        raise Error, 'DEVTO_API_KEY is not set' if api_key.to_s.empty?

        @api_key = api_key
      end

      def drafts
        (1..).each_with_object([]) do |page, all|
          batch = request(Net::HTTP::Get, "articles/me/unpublished?per_page=#{PER_PAGE}&page=#{page}")
          all.concat(batch)
          break all if batch.size < PER_PAGE
        end
      end

      def update(id, article)
        request(Net::HTTP::Put, "articles/#{id}", { article: article })
      end

      private

      def request(verb, path, body = nil)
        uri = API + path
        req = verb.new(uri)
        req['api-key'] = @api_key
        req['Accept'] = 'application/vnd.forem.api-v1+json'
        req['Content-Type'] = 'application/json'
        req['User-Agent'] = "jekyll-devto/#{VERSION}"
        req.body = JSON.generate(body) if body

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        raise Error, "#{req.method} #{uri.path} failed: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      end
    end
  end
end
