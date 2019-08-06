# frozen_string_literal: true

require 'octokit'

# Various functions for working with GitHub
module GitHubTools
  def self.warn_now(msg)
    $stderr.print msg
    $stderr.flush
  end

  # Writes to stderr only, not stdout, because stdout is only for results
  def self.org_repos_for_topic(org, client, topic)
    warn_now "Retrieving list of #{org} repos with topic #{topic} ... "

    result = client.search_repos "user:#{org} topic:#{topic}"

    warn_now "#{result.items.length} repos found\n"

    # TODO: possible bug in this function: I don’t know whether auto_paginate works for this method.
    # So if there’s more than 100 repos with the given topic this might return only the first 100.
    # This is an edge case so I’m OK with this for now.
    if result.total_count > 100 && result.items.length == 100
      warn "Warning! There may be additional matching repos that weren’t retrieved!\n"
    end

    result.items
  end

  def self.handle_errs(client)
    yield
  rescue Octokit::TooManyRequests
    pp client.rate_limit
    raise
  end

  def self.org_repos(org, client, topic: nil, type: 'all')
    handle_errs(client) do
      if topic.nil? || topic.empty?
        client.org_repos org, type: type
      else
        org_repos_for_topic org, client, topic
      end
    end
  end

  # Accepts a repo and an org name, returns true if org is the owner of the repo.
  # Uses a case-insensitive string comparison, but does not strip any operands so
  # leading or trailing whitespace in the org name could yield a false negative.
  def self.owned_by?(repo, org)
    repo.owner.login.casecmp? org
  end

  ## TODO: need a test for confirming that the org arg (sourced from the GITHUB_ORG env var)
  # is treated case-insensitively.
  def self.subscribed_repos(org, client)
    GitHubTools.handle_errs(client) do
      client.subscriptions.select { |repo| owned_by? repo, org }
    end
  end

  # Returns a commit object as a hash, or nil if no commits are found.
  def self.first_commit(repo_full_name, client)
    # query includes merge:false because a commit search is not allowed to have repo as the only
    # criterion.
    query = "repo:#{repo_full_name} merge:false"
    result = client.search_commits query, sort: 'author-date',
                                          order: 'asc',
                                          per_page: 1 # not working?
    result.items.first
  end

  # When we print a repo that’s in the org specified by ENV['GITHUB_ORG] then we want to
  # print the short unqualified name. When we print one that is not, we want to print the full
  # qualified name.
  def self.printable_name(repo, org)
    owned_by?(repo, org) ? repo.name : repo.full_name
  end

  # Each filter must be a static method that accepts a repo hash and a client.
  # TODO: since Ruby 2.6 added function composition, we should maybe have this module contain
  #       procs rather than static methods.
  module Filters
    def self.codeowners?(repo, client)
      ## TODO: look into a way to have the client return the response object instead of raising
      client.contents repo[:full_name], path: '.github/CODEOWNERS'
      true
    rescue Octokit::NotFound
      false
    end
  end
end
