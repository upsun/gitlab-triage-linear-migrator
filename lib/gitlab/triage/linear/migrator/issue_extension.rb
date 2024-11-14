# frozen_string_literal: true

require_relative "linear_connector"

module Gitlab
  module Triage
    module Linear
      module Migrator
        # Extending Gitlab::Triage::Resource::Issue with functions required for Linear migration.
        module IssueExtension
          def discussions
            # Epic discussions GET endpoint weirdly has id instead of iid as param.
            url = if self.class.name.demodulize.underscore.pluralize == "epics"
                    build_url(
                      options: {
                        params: { system: false },
                        resource_id: resource["id"],
                        sub_resource_type: "discussions"
                      }
                    )
                  else
                    resource_url(sub_resource_type: "discussions")
                  end
            network.query_api_cached(url)
          end

          def human_discussions
            discussions.reject do |discussion_item|
              discussion_item["individual_note"] == true && discussion_item["notes"].first["system"] == true
            end
          end

          def extract_issue_id(text)
            # Use a regular expression to match the issue ID pattern within the fixed text
            issue_id_pattern = /Linear issue ID: ([a-f0-9-]{36})/

            # Extract the issue ID using the pattern
            match = text.match(issue_id_pattern)

            # Return the issue ID if found, otherwise return nil
            match ? match[1] : nil
          end

          def find_linear_id_in_gitlab
            return if resource[:epic].empty?

            url = build_url(params: {},
                            options: { source: "groups", resource_type: "epics", resource_id: resource[:epic][:id],
                                       source_id: resource[:epic][:group_id], sub_resource_type: "notes" })
            comments = network.query_api_cached(url)
            comments.each do |comment|
              if (issue_id = process_comment(comment["body"]))
                puts "Parent epic found: #{issue_id}"
                return issue_id
              end
            end
            nil
          end

          def process_comment(comment_body)
            return unless comment_body.start_with?("Issue created in Linear:")

            extract_issue_id(comment_body)
          end

          # @todo: make these configurable
          LABEL_MIGRATION_FAILED = '/label ~"Linear::Migration Failed"'
          LABEL_MIGRATED = '/label ~"Linear::Migrated"'
          CLOSE_ACTON = "/close"

          def create_issue_in_linear(set_state: false, prepend_project_name: false, team_label_prefix: "Team")
            connector = setup_linear_connector
            connector.team_label_prefix = team_label_prefix
            project_name = if prepend_project_name
                             fetch_project_name
                           end.to_s

            begin
              log_processing_issue
              issue = connector.import_issue(self, set_state:, project_name:)
            rescue StandardError => e
              handle_error(e.message, project_name)
              return
            end

            return unless issue

            construct_output(issue)
          end

          private

          def log_processing_issue
            puts Rainbow("Processing issue: #{resource["web_url"]}").yellow
          end

          def handle_error(message, project_name)
            puts Rainbow(message).red
            %(Issue migration failed for issue ##{resource["id"]} in project #{project_name} #{resource["web_url"]}
Error:
#{message[0..100]}
#{LABEL_MIGRATION_FAILED})
          end

          def construct_output(issue)
            %(Issue created in Linear: #{issue["url"]}
Linear issue ID: #{issue["id"]}
#{LABEL_MIGRATED}
#{CLOSE_ACTON})
          end

          def setup_linear_connector
            connector = LinearConnector.new
            connector.gitlab_dry_run = network.options.dry_run
            connector.linear_dry_run = ENV.fetch("IGNORE_LINEAR_DRYRUN", false) ? false : network.options.dry_run
            connector
          end

          def fetch_project_name
            network.query_api_cached(build_url(options: { resource_type: nil })).first["name"]
          end
        end
      end
    end
  end
end
