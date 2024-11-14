# frozen_string_literal: true

require_relative "graphql_client"
require_relative "linear_interface"

module Gitlab
  module Triage
    module Linear
      module Migrator
        # Connects to Linear and creates stuff.
        class LinearConnector
          MIGRATION_LABEL_NAME = "Migrated from GitLab"
          MIGRATION_IN_PROGRESS_LABEL_NAME = "Migrating from GitLab - in progress"
          MIGRATION_LABEL_NAME_DRY_RUN = "Migrated from GitLab (DRY-RUN)"
          MIGRATION_IN_PROGRESS_LABEL_NAME_DRY_RUN = "Migrating from GitLab - in progress (DRY-RUN)"

          LINEAR_STATE_MAP =
            {
              "Inbox" => nil,
              "InProgress" => "In Progress",
              "OnHold" => "Blocked",
              "PendingRelease" => "Pending Release",
              "Planned" => "Planned",
              "Review" => "In Review",
              "Candidate" => "Candidate",
              "Blocked" => "Blocked",
              "Closed" => "Done",
              "Testing" => "Testing",
              "NeedsQA" => "Needs QA",
              "DesignReview" => "Design Review",
              "CodeReview" => "Code Review",
              "ReadyForDev" => "Planned"
            }.freeze

          def initialize(gitlab_dry_run: false, linear_dry_run: false, client: nil, interface: nil, team_label_prefix: "Team")
            @gitlab_dry_run = gitlab_dry_run
            @linear_dry_run = linear_dry_run
            @team_label_prefix = team_label_prefix

            # @todo: Find a better solution to set the Linear API token.
            @graphql_client = client || GraphqlClient.new("https://api.linear.app/graphql", {
                                                            "Authorization" => ENV.fetch("LINEAR_API_TOKEN", nil)
                                                          }, dry_run: @linear_dry_run)
            @id_map = []

            @query_count = 0
            @mutation_count = 0
            @query_count_by_function = []

            @linear_interface = interface || LinearInterface.new(graphql_client: @graphql_client)
          end

          attr_accessor :gitlab_dry_run, :team_label_prefix
          attr_reader :linear_dry_run

          def linear_dry_run=(dry_run)
            @linear_dry_run = dry_run
            @graphql_client.dry_run = @linear_dry_run
          end

          def import_issue(gitlab_issue, set_state: false, project_name: nil)
            linear_team_data = fetch_linear_team_data(gitlab_issue)
            linear_label_ids = get_linear_label_ids(gitlab_issue.labels, linear_team_data["id"])

            issue_data = prepare_issue_data(gitlab_issue, linear_label_ids, linear_team_data, project_name, set_state)
            issue_created = @linear_interface.create_issue(issue_data)

            return unless issue_created

            if gitlab_issue.instance_of?(Gitlab::Triage::Resource::Issue)
              import_mr_links(gitlab_issue,
                              issue_created["id"])
            end

            import_comments(gitlab_issue, gitlab_issue.discussions, issue_created["id"])

            if issue_created
              handle_post_creation_tasks(gitlab_issue, issue_created["id"], issue_data["parent_id"], linear_label_ids,
                                         issue_created["url"])
            end

            issue_created
          end

          def import_comments(_gitlab_issue, discussions, linear_id)
            discussions.each do |discussion|
              process_discussion(discussion["notes"], linear_id) if valid_discussion?(discussion["notes"])
            end
          end

          private

          def valid_discussion?(notes)
            notes && !notes.empty? && notes.none? { |note| note["system"] }
          end

          def process_discussion(notes, linear_id)
            return if notes.empty?

            if notes.size > 1
              process_threaded_comments(notes, linear_id)
            else
              create_comment_from_note(notes.first, linear_id)
            end
          end

          def process_threaded_comments(notes, linear_id)
            parent_note = notes.first
            parent_comment = create_comment_from_note(parent_note, linear_id)
            parent_external_id = parent_comment["id"]

            notes[1..].each do |child_note|
              create_comment_from_note(child_note, linear_id, parent_external_id)
            end
          end

          def create_comment_from_note(note, linear_id, parent_id = nil)
            @linear_interface.create_comment(
              body: note["body"],
              linear_issue_id: linear_id,
              author_name: note["author"]["name"],
              parent_id:,
              created_at: note["created_at"]
            )
          end

          def prepare_issue_data(gitlab_issue, linear_label_ids, linear_team_data, project_name, set_state)
            {
              title: format_issue_title(gitlab_issue, project_name),
              description: sanitize_description(gitlab_issue.resource[:description]),
              team_id: linear_team_data["id"],
              create_as_user: gitlab_issue.resource[:author][:name],
              assignee_id: determine_assignee_id(gitlab_issue),
              state_id: determine_state_id(gitlab_issue, linear_team_data, set_state),
              parent_id: determine_epic_id(gitlab_issue),
              created_at: gitlab_issue.resource["created_at"],
              label_ids: linear_label_ids,
              due_date: gitlab_issue.resource["due_date"],
              sort_order: gitlab_issue.resource["weight"]
            }
          end

          def fetch_linear_team_data(gitlab_issue)
            team_name = "#{@team_label_prefix}: #{get_team_label(gitlab_issue.labels)}"
            linear_team_data = @linear_interface.get_team_by_name(team_name)
            unless linear_team_data
              raise StandardError,
                    "Couldn't create issue in Linear, because the team #{linear_team_data["name"]} doesn't exists in Linear."
            end

            linear_team_data
          end

          def format_issue_title(gitlab_issue, project_name)
            project_name.to_s.empty? ? gitlab_issue.resource[:title].to_s : "#{project_name}: #{gitlab_issue.resource[:title]}"
          end

          def sanitize_description(description)
            return nil if description.nil?

            description.gsub(/<!--(.*?)-->/m, "").gsub("...", ". . . ")
          end

          def handle_post_creation_tasks(gitlab_issue, issue_id, parent_id, linear_label_ids, issue_url)
            handle_missing_parent_issue(gitlab_issue, issue_id, parent_id)
            @linear_interface.create_comment(
              body: compile_migration_notes(gitlab_issue.resource["web_url"],
                                            gitlab_issue.labels), linear_issue_id: issue_id, author_name: "Migration"
            )
            @linear_interface.create_url_link(issue_id, gitlab_issue.resource["web_url"],
                                              "Original issue in GitLab: #{gitlab_issue.resource["title"]}")
            write_to_migration_map(gitlab_issue, linear_id: issue_id, linear_url: issue_url)
            update_linear_labels(issue_id, linear_label_ids)
          end

          def handle_missing_parent_issue(gitlab_issue, issue_id, parent_id)
            return unless gitlab_issue.resource["epic"] && parent_id.nil?

            epic_url = gitlab_issue.host_url + gitlab_issue.resource["epic"]["url"]
            @linear_interface.create_comment(body: "The original issue in GitLab has an epic that was not migrated to Linear. Epic in GitLab: #{epic_url}",
                                             linear_issue_id: issue_id, author_name: "Migration")
            @linear_interface.create_url_link(issue_id, epic_url,
                                              "Epic in GitLab: #{gitlab_issue.resource["epic"]["title"]}")
          end

          def update_linear_labels(issue_id, linear_label_ids)
            if @gitlab_dry_run && !@linear_dry_run
              linear_label_ids.delete(@linear_interface.find_label(MIGRATION_IN_PROGRESS_LABEL_NAME_DRY_RUN))
              linear_label_ids.append(@linear_interface.find_label(MIGRATION_LABEL_NAME_DRY_RUN))
            else
              linear_label_ids.delete(@linear_interface.find_label(MIGRATION_IN_PROGRESS_LABEL_NAME))
              linear_label_ids.append(@linear_interface.find_label(MIGRATION_LABEL_NAME))
            end
            @linear_interface.update_labels(issue_id, linear_label_ids)
          end

          def determine_assignee_id(gitlab_issue)
            (return unless gitlab_issue.resource[:assignees]&.length&.positive?

             @linear_interface.get_user_id_by_email(gitlab_issue.resource[:assignees].first[:email])
            )
          end

          def determine_state_id(gitlab_issue, linear_team_data, set_state)
            if gitlab_issue.state == "closed"
              find_state_id_by_name(linear_team_data, "Closed")
            else
              (find_state_id_by_name(linear_team_data, get_s_label(gitlab_issue.labels)) if set_state)
            end
          end

          def determine_epic_id(gitlab_issue)
            epic_id_in_linear = nil
            if gitlab_issue.resource["epic"]
              epic_id = gitlab_issue.resource["epic"]["id"]
              epic_id_in_linear = get_linear_id_from_migration_map(gitlab_type: "epic", gitlab_id: epic_id)
              epic_id_in_linear = @linear_interface.find_linear_issue_by_gitlab_url("#{gitlab_issue.host_url}#{gitlab_issue.resource["epic"]["url"]}") if epic_id_in_linear.nil?
            end
            epic_id_in_linear
          end

          def import_mr_links(gitlab_issue, linear_id)
            gitlab_issue.related_merge_requests.each do |mr|
              @linear_interface.create_mr_link(linear_id, mr.resource["web_url"], mr.project_path, mr.resource["iid"],
                                               mr.resource["title"])
            end
          end

          def get_linear_label_ids(gitlab_labels, team_id)
            # 1. transform the labels ito a flat name list
            # E::Level Easy --> Level Easy
            # T::Bug --> Bug

            gitlab_label_list = gitlab_labels.map { |n| n.name.gsub(/.*::/, "") }

            if @gitlab_dry_run && !@linear_dry_run
              gitlab_label_list.append(MIGRATION_IN_PROGRESS_LABEL_NAME_DRY_RUN)
            else
              gitlab_label_list.append(MIGRATION_IN_PROGRESS_LABEL_NAME)
            end

            # 2. list the labels in Linear

            linear_labels = @linear_interface.list_labels(gitlab_label_list, team_id)

            linear_labels["data"]["issueLabels"]["nodes"].map { |n| n["id"] }
          end

          def get_team_label(labels)
            labels.select { |label| label.name.start_with?("#{@team_label_prefix}::") }
                  .map { |label| label.name.split("::").last }
                  .first
          end

          def get_s_label(labels)
            labels.select { |label| label.name.start_with?("S::") }
                  .map { |label| label.name.split("::").last }
                  .first
          end

          def compile_migration_notes(gitlab_url, labels)
            %(This issue was copied from GitLab by Triage Bot. Original issue: #{gitlab_url}

Original labels: #{labels.map { |label| "'#{label.name}'" }.join(", ")}
)
          end

          def find_state_id_by_name(teams, search_name)
            return nil if teams.empty?

            states = teams["states"]["nodes"]

            # Finding the state with the given name
            state = states.find { |s| s["name"] == LINEAR_STATE_MAP[search_name] }

            # Return the id if state is found, otherwise nil
            state["id"] unless state.nil?
          end

          def write_to_migration_map(gitlab_issue, linear_id: nil, linear_url: "")
            gitlab_type = gitlab_issue.class.name.demodulize.underscore
            gitlab_id = gitlab_issue.resource["id"]
            gitlab_url = gitlab_issue.resource["web_url"]
            linear_type = "issue"

            @id_map.push(gitlab_type, gitlab_id, linear_type, linear_id, gitlab_url, linear_url)
          end

          def get_linear_id_from_migration_map(gitlab_type: "issue", gitlab_id: nil, linear_type: "issue")
            row = @id_map.find do |element|
              element[0] == gitlab_type && element[1] == gitlab_id && element[2] == linear_type
            end
            row[3] if row
          end
        end
      end
    end
  end
end
