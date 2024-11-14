# frozen_string_literal: true

require "gitlab/triage/linear/migrator/issue_extension"
Gitlab::Triage::Resource::Context.include Gitlab::Triage::Linear::Migrator::IssueExtension
