# frozen_string_literal: true

require_relative "lib/jekyll/devto/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll-devto"
  spec.version = Jekyll::Devto::VERSION
  spec.authors = ["Juan Vásquez"]
  spec.email = ["juan@ombulabs.com"]

  spec.summary = "Cross-post a Jekyll blog to dev.to, complete, through its RSS import."
  spec.description = <<~DESC
    Generates a feed dev.to imports with the full post (code blocks without
    Rouge line numbers, absolute links and images), and a command that
    publishes the imported drafts once their post is live on your site.
  DESC
  spec.homepage = "https://github.com/JuanVqz/jekyll-devto"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "exe/*", "examples/*", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["jekyll-devto"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 4.0", "< 5"
  spec.add_dependency "rexml", "~> 3.2"
end
