# frozen_string_literal: true

require_relative "graphql_client"

module Gitlab
  module Triage
    module Linear
      module Migrator
        # An interface class that provides functions to get and send data from/to Linear
        class LinearInterface
          FIND_LABEL_QUERY = <<~GRAPHQL
            query($label: String!) {
              issueLabels(
                filter: { name: { eq: $label } }
              ) {
                nodes {
                  id
                  name
                }
              }
            }
          GRAPHQL

          UPDATE_LABELS_MUTATION = <<~GRAPHQL
            mutation($issueId: String!, $labels: [String!]!) {
              issueUpdate(input: { labelIds: $labels }, id: $issueId) {
                lastSyncId
                success
              }
            }
          GRAPHQL

          LIST_LABELS_QUERY = <<~GRAPHQL
            query($labels: [String!], $teamId: ID) {
              issueLabels(
                filter: {
                  name: { in: $labels }
                  or: [
                    { team: { id: { eq: $teamId } } }
                    { team: { null: true } }
                  ]
                }
              ) {
                nodes {
                  id
                  name
                }
              }
            }
          GRAPHQL

          GET_USER_ID_BY_EMAIL_QUERY = <<~GRAPHQL
            query($email: String!) {
              users(filter: { email: { eq: $email } }) {
                nodes {
                  id
                }
              }
            }
          GRAPHQL

          GET_TEAM_BY_NAME_QUERY = <<~GRAPHQL
            query($name: String!) {
              teams(filter: { name: { eq: $name } }) {
                nodes {
                  id
                  name
                  states {
                    nodes {
                      id
                      name
                    }
                  }
                }
              }
            }
          GRAPHQL

          FIND_LINEAR_ISSUE_BY_GITLAB_URL_QUERY = <<~GRAPHQL
            query($gitlabUrl: String!) {
              issueSearch(
                filter: {
                  comments: {
                    body: {
                      contains: "Original issue: $gitlabUrl"
                    }
                  }
                }
              ) {
                nodes {
                  id
                }
              }
            }
          GRAPHQL

          def initialize(graphql_client: GraphqlClient)
            @graphql_client = graphql_client
          end

          def find_label(label)
            response = @graphql_client.query(FIND_LABEL_QUERY, { label: })
            response["data"]["issueLabels"]["nodes"].first["id"]
          end

          def update_labels(issue_id, labels)
            @graphql_client.mutation(UPDATE_LABELS_MUTATION, { issueId: issue_id, labels: })
          end

          def list_labels(labels, team_id)
            @graphql_client.query(LIST_LABELS_QUERY, { labels:, teamId: team_id })
          end

          def get_user_id_by_email(email)
            return nil if email.nil? || email.empty?

            response = @graphql_client.query(GET_USER_ID_BY_EMAIL_QUERY, { email: })
            response["data"]["users"]["nodes"].first["id"]
          end

          def get_team_by_name(name)
            response = @graphql_client.query(GET_TEAM_BY_NAME_QUERY, { name: })
            raise StandardError, "Team #{name} not found in Linear." if response["data"]["teams"]["nodes"].empty?

            response["data"]["teams"]["nodes"].first
          end

          def find_linear_issue_by_gitlab_url(gitlab_url)
            response = @graphql_client.query(FIND_LINEAR_ISSUE_BY_GITLAB_URL_QUERY, { gitlabUrl: gitlab_url })
            response["data"]["issueSearch"]["nodes"].first["id"]
          end

          def create_issue(issue_data)
            query = build_graphql_mutation("issueCreate", {
                                             input: {
                                               title: issue_data[:title],
                                               teamId: issue_data[:team_id],
                                               description: issue_data[:description],
                                               createAsUser: issue_data[:create_as_user],
                                               assigneeId: issue_data[:assignee_id],
                                               stateId: issue_data[:state_id],
                                               parentId: issue_data[:parent_id],
                                               createdAt: issue_data[:created_at],
                                               labelIds: issue_data[:label_ids],
                                               dueDate: issue_data[:due_date],
                                               sortOrder: issue_data[:sort_order]
                                             }
                                           }, ["lastSyncId", "success", "issue { id, url }"])

            linear_issue = @graphql_client.mutation(query)
            linear_issue&.dig("data", "issueCreate", "issue")
          end

          def create_comment(body: "", linear_issue_id: nil, author_name: nil, parent_id: nil, created_at: Time.now)
            query = build_graphql_mutation("commentCreate", {
                                             input: {
                                               body: body.gsub("...", ". . . "),
                                               issueId: linear_issue_id,
                                               parentId: parent_id,
                                               createAsUser: author_name,
                                               createdAt: created_at
                                             }
                                           }, ["lastSyncId", "success", "comment { id }"])

            response = @graphql_client.mutation(query)
            response["data"]["commentCreate"]["comment"]
          end

          def create_mr_link(linear_id, url, path, number, title)
            query = build_graphql_mutation("attachmentLinkGitLabMR", {
                                             issueId: linear_id,
                                             url:,
                                             projectPathWithNamespace: path,
                                             number:,
                                             title:
                                           }, %w[lastSyncId success])

            @graphql_client.mutation(query)
          end

          def create_url_link(linear_id, url, title = nil)
            query = build_graphql_mutation("attachmentLinkURL", {
                                             issueId: linear_id,
                                             url:,
                                             title:
                                           }, %w[lastSyncId success])

            @graphql_client.mutation(query)
          end

          private

          def process_variables(vars)
            vars.map do |key, value|
              if value.is_a?(Hash)
                inner_vars = process_variables(value)
                "#{key}: { #{inner_vars} }"
              else
                "#{key}: #{value.to_json}"
              end
            end.join("\n")
          end

          def build_graphql_mutation(field, variables, return_fields)
            variables_str = process_variables(variables)
            return_fields_str = return_fields.join("\n")

            <<~GRAPHQL
              mutation {
                #{field}(
                  #{variables_str}
                ) {
                  #{return_fields_str}
                }
              }
            GRAPHQL
          end
        end
      end
    end
  end
end
