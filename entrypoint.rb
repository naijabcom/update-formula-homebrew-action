#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler"
Bundler.require

require "base64"
require "logger"
require "optparse"

logger = Logger.new($stdout)
logger.level = Logger::INFO

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: entrypoint.rb [options]"

  opts.on("-r ", "--repository REPOSITORY", "The project repository") do |repository|
    options[:repository] = repository
  end

  opts.on("-t", "--tap REPOSITORY", "The Homebrew tap repository") do |tap|
    options[:tap] = tap
  end

  opts.on("-f", "--formula PATH", "The path to the formula in the tap repository") do |path|
    options[:formula] = path
  end

  opts.on("-d", "--download-url DOWNLOAD-URL", "The download release url") do |download_url|
    options[:download_url] = download_url
  end

  opts.on("-s", "--sha256 DOWNLOAD-URL-SHA256", "The download release url sha256") do |sha|
    options[:sha256] = sha
  end

  opts.on("-m", "--commit-message MESSAGE", "The message of the commit updating the formula") do |message|
    options[:message] = message.strip
  end

  opts.on_tail("-v", "--verbose", "Output more information") do
    logger.level = Logger::DEBUG
  end

  opts.on_tail("-h", "--help", "Display this screen") do
    puts opts
    exit 0
  end
end.parse!

begin
  raise "COMMIT_TOKEN environment variable is not set" unless ENV["COMMIT_TOKEN"]
  raise "missing argument: -r/--repository" unless options[:repository]
  raise "missing argument: -t/--tap" unless options[:tap]
  raise "missing argument: -f/--formula" unless options[:formula]
  raise "missing argument: -d/--download-url" unless options[:download_url]
  raise "missing argument: -s/--sha256" unless options[:sha256]

  client = Octokit::Client.new(access_token: ENV["COMMIT_TOKEN"])

  repo = client.repo(options[:repository])

  releases = repo.rels[:releases].get.data
  raise "No releases found" unless (latest_release = releases.first)

  download_url = options[:download_url]

  tags = repo.rels[:tags].get.data
  unless (tag = tags.find { |t| t.name == latest_release.tag_name })
    raise "Tag #{latest_release.tag_name} not found"
  end

  raw_original_content = client.contents(options[:tap], path: options[:formula]).content
  original_content = Base64.decode64(raw_original_content)

  formula_name = options[:formula]
  formula_name = formula_name.chomp(".rb")
  formula_name = formula_name.gsub("Formula/", "")

  formula_desc = repo[:description]

  formula_proj = repo[:html_url]

  formula_sha = options[:sha256]

  formula_license = repo[:license][:spdx_id]

  formula_release_tag = latest_release.tag_name

  new_content = original_content.dup

  new_content.gsub!(/(url\s+").*(")/, "\\1#{download_url}\\2")
  new_content.gsub!(/(sha256\s+").*(")/, "\\1#{formula_sha}\\2")
  new_content.gsub!(/(version\s+").*(")/, "\\1#{formula_release_tag}\\2")

  logger.info new_content

  blob_sha = client.contents(options[:tap], path: options[:formula]).sha

  commit_message = (options[:message].nil? || options[:message].empty?) ? "Update #{repo.name} to #{latest_release.tag_name}" : options[:message]
  logger.info commit_message

  client.update_contents(options[:tap],
                          options[:formula],
                          commit_message,
                          blob_sha,
                          new_content)

  logger.info "Update formula and push commit completed!"
rescue => e
  logger.fatal(e)
  exit 1
end
