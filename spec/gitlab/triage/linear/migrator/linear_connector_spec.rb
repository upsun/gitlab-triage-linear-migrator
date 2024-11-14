# frozen_string_literal: true

require "gitlab/triage/network"
require "gitlab/triage/resource/issue"
require "webmock/rspec" # We only need this to disable any outgoing requests during tests.
require "gitlab/triage/linear/migrator/linear_connector"

RSpec.describe Gitlab::Triage::Linear::Migrator::LinearConnector do
  subject(:connector) do
    described_class.new(gitlab_dry_run: false, client: graphql_client, interface: linear_interface)
  end

  let(:graphql_client) do
    instance_double(Gitlab::Triage::Linear::Migrator::GraphqlClient)
  end

  let(:linear_interface) do
    instance_double(Gitlab::Triage::Linear::Migrator::LinearInterface)
  end

  let(:network_mock) do
    instance_double(Gitlab::Triage::Network)
  end

  let(:author_username) { "author_user" }

  let(:team_search_response) do
    {
      "data" => {
        "teams" => {
          "nodes" => [
            {
              "id" => "123",
              "name" => "Team 1",
              "states" => {
                "nodes" => [
                  {
                    "id" => "e6704a82-a7a2-44cb-8fc5-224f99a70dd4",
                    "name" => "Triage"
                  },
                  {
                    "id" => "edc1677f-bf96-4d96-b72c-bb4faf41796a",
                    "name" => "In Progress"
                  },
                  {
                    "id" => "6e027a9b-c6fe-47c9-8432-6f0f4664fddd",
                    "name" => "Todo"
                  },
                  {
                    "id" => "437827c0-e88f-45d0-b2b0-783297e8981e",
                    "name" => "Duplicate"
                  },
                  {
                    "id" => "35feed2f-de1a-4cce-b191-8aad7e9b45f9",
                    "name" => "Backlog"
                  },
                  {
                    "id" => "1e595f67-01b9-4687-9aef-f2189f6c2d41",
                    "name" => "In Review"
                  },
                  {
                    "id" => "18a4c7ff-9966-418b-8fae-3f788e906a44",
                    "name" => "Canceled"
                  },
                  {
                    "id" => "185103b7-2a74-447f-9828-2da250fdd2e0",
                    "name" => "Done"
                  }
                ]
              }
            }
          ]
        }
      }
    }
  end

  let(:issue_label_response) do
    {
      "data" => {
        "issueLabels" => {
          "nodes" => [
            {
              "id" => "b8c6c8cc-6f17-448f-b8f3-e51528ea7880",
              "name" => "Bug2",
              "team" => {
                "name" => "Example A"
              },
              "parent" => nil
            },
            {
              "id" => "072b4e84-1bbc-4062-93ba-f7b10187de0d",
              "name" => "Bug2",
              "team" => {
                "name" => "Team=> Example"
              },
              "parent" => nil
            },
            {
              "id" => "8b1d410b-5317-4a69-9877-9fedfc4abd64",
              "name" => "Bug",
              "team" => nil,
              "parent" => {
                "id" => "c5d0f860-b663-4b31-88b2-e034c9d8274c",
                "name" => "Type"
              }
            }
          ]
        }
      }
    }
  end

  let(:issue_create_response) do
    {
      "data" => {
        "issueCreate" => {
          "lastSyncId" => 2_068_493_908,
          "success" => true,
          "issue" => {
            "id" => "b6b31d09-6561-4a77-a265-79e854086557",
            "url" => "https://linear.app/test/issue/RDT1-35/hello-world-again"
          }
        }
      }
    }
  end

  let(:comment_create_response) do
    {
      "data" => {
        "commentCreate" => {
          "lastSyncId" => 2_068_493_908,
          "success" => true,
          "comment" => {
            "id" => "b6b31d09-6561-4a77-a265-79e854086557"
          }
        }
      }
    }
  end

  let(:user_search_response) do
    {
      "data" => {
        "users" => {
          "nodes" => [
            {
              "id" => "1234"
            }
          ]
        }
      }
    }
  end

  let(:discussions) { [] }

  it "has a version number" do
    expect(Gitlab::Triage::Linear::Migrator::VERSION).not_to be_nil
  end

  describe "#find_state_id_by_name" do
    context "when teams is empty" do
      let(:teams) { [] }

      it "returns nil" do
        expect(connector.send(:find_state_id_by_name, teams, "some state")).to be_nil
      end
    end

    context "when teams is not empty" do
      let(:teams) { team_search_response["data"]["teams"]["nodes"].first }

      it "returns the team ID" do
        expect(connector.send(:find_state_id_by_name, teams,
                              "InProgress")).to eq("edc1677f-bf96-4d96-b72c-bb4faf41796a")
      end

      context "when the state is not found" do
        it "returns nil" do
          expect(connector.send(:find_state_id_by_name, teams, "Something")).to be_nil
        end
      end

      context "when searching for the Inbox state" do
        it "returns nil" do
          expect(connector.send(:find_state_id_by_name, teams, "Inbox")).to be_nil
        end
      end
    end
  end

  describe "#import_issue" do
    before do
      allow(network_mock).to receive(:options)
      allow(issue).to receive(:build_url).with(options: { resource_id: nil, sub_resource_type: "discussions" },
                                               params: {})
                                         .and_return("projects/1/issues/1/discussions")
      allow(issue).to receive(:build_url).with(
        options: { resource_id: nil, sub_resource_type: "related_merge_requests" }, params: {}
      )
                                         .and_return("projects/1/issues/1/related_merge_requests")
      allow(network_mock).to receive(:query_api_cached).with("projects/1/issues/1/discussions").and_return(discussions)
      allow(network_mock).to receive(:query_api_cached).with("projects/1/issues/1/related_merge_requests").and_return([])
      allow(linear_interface).to receive(:get_team_by_name).with("Team: Team 1")
                                                           .and_return(team_search_response["data"]["teams"]["nodes"].first)

      allow(linear_interface).to receive(:find_label).with("Migrating from GitLab - in progress")
      allow(linear_interface).to receive(:find_label).with("Migrating from GitLab")
      allow(linear_interface).to receive(:find_label).with("Migrated from GitLab")
      allow(linear_interface).to receive(:list_labels).with(["Team 1", "other", "Migrating from GitLab - in progress"],
                                                            "123").and_return(issue_label_response)
      allow(linear_interface).to receive(:create_comment)
        .and_return(comment_create_response["data"]["commentCreate"]["comment"])
      allow(linear_interface).to receive(:create_url_link)
      allow(linear_interface).to receive(:update_labels)
    end

    context "when the issue has no assignee" do
      let(:issue) do
        Gitlab::Triage::Resource::Issue.new({ title: "Example", description: "Example desc.", labels: ["Team::Team 1", "other"], author: { username: author_username, name: "Author Full Name" } },
                                            network: network_mock)
      end

      before do
        issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        allow(linear_interface).to receive(:create_issue).and_return(issue_create_response)
      end

      it "sets the assigneeId to null" do
        connector.import_issue(issue)
        expect(linear_interface).to have_received(:create_issue)
      end
    end

    context "when there is one assignee" do
      let(:issue) do
        Gitlab::Triage::Resource::Issue.new(
          { title: "Example", description: "Example desc.", labels: ["Team::Team 1", "other"], author: { username: author_username, name: "Author Full Name" },
            assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
        )
      end

      before do
        issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        allow(linear_interface)
          .to receive_messages(get_user_id_by_email: user_search_response["data"]["users"]["nodes"].first["id"],
                               create_issue: issue_create_response)
      end

      it "searches for the user in Linear" do
        connector.import_issue(issue)
        expect(linear_interface).to have_received(:get_user_id_by_email).with("user@example.com")
      end

      it "sets the user id as assignee" do
        connector.import_issue(issue)
        expect(linear_interface).to have_received(:create_issue)
          .with(hash_including(assignee_id: "1234"))
      end
    end

    context "when we don't want to migrate state" do
      let(:issue) do
        Gitlab::Triage::Resource::Issue.new(
          { title: "Example", description: "Example desc.", labels: ["Team::Team 1", "S::InProgress"], author: { username: author_username, name: "Author Full Name" },
            assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
        )
      end

      before do
        issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        allow(linear_interface).to receive_messages(
          get_user_id_by_email: user_search_response["data"]["users"]["nodes"].first["id"], list_labels: issue_label_response
        )
        allow(linear_interface).to receive(:create_issue)
        connector.import_issue(issue, set_state: false)
      end

      it "sets the stateId to null (nil)" do
        expect(linear_interface).to have_received(:create_issue).with(hash_including(state_id: nil))
      end
    end

    context "when we want to set the state" do
      before do
        issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)

        allow(linear_interface).to receive_messages(
          get_user_id_by_email: user_search_response["data"]["users"]["nodes"].first["id"], list_labels: issue_label_response
        )
        allow(linear_interface).to receive(:create_issue)
        connector.import_issue(issue, set_state: true)
      end

      context "when the issue has S::InProgress label" do
        let(:issue) do
          Gitlab::Triage::Resource::Issue.new(
            { title: "Example", description: "Example desc.", labels: ["Team::Team 1", "S::InProgress"], author: { username: author_username, name: "Author Full Name" },
              assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
          )
        end

        it "sets the stateId" do
          expect(linear_interface).to have_received(:create_issue).with(hash_including(state_id: "edc1677f-bf96-4d96-b72c-bb4faf41796a"))
        end
      end

      context "when the issue has no S:: label" do
        let(:issue) do
          Gitlab::Triage::Resource::Issue.new(
            { title: "Example", description: "Example desc.", labels: ["Team::Team 1"], author: { username: author_username, name: "Author Full Name" },
              assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
          )
        end

        before do
          issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        end

        it "sets the stateId to null (nil)" do
          expect(linear_interface).to have_received(:create_issue).with(hash_including(state_id: nil))
        end
      end

      context "when the issue has an S:: label that is not mapped" do
        let(:issue) do
          Gitlab::Triage::Resource::Issue.new(
            { title: "Example", description: "Example desc.", labels: ["Team::Team 1", "S::Adobe Review"], author: { username: author_username, name: "Author Full Name" },
              assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
          )
        end

        before do
          issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        end

        it "sets the stateId to null (nil)" do
          expect(linear_interface).to have_received(:create_issue).with(hash_including(state_id: nil))
        end
      end

      context "when the issue has S::Inbox label" do
        let(:issue) do
          Gitlab::Triage::Resource::Issue.new(
            { title: "Example", description: "Example desc.", labels: ["Team::Team 1", "S::Inbox"], author: { username: author_username, name: "Author Full Name" },
              assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
          )
        end

        before do
          issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        end

        it "sets the stateId to null (nil)" do
          expect(linear_interface).to have_received(:create_issue).with(hash_including(state_id: nil))
        end
      end

      context "when the issue has an S:: label that is in the map but doesn't exists in Linear" do
        let(:issue) do
          Gitlab::Triage::Resource::Issue.new(
            { title: "Example", description: "Example desc.", labels: ["Team::Team 1", "S::PendingRelease"], author: { username: author_username, name: "Author Full Name" },
              assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
          )
        end

        before do
          issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        end

        it "sets the stateId to null (nil)" do
          expect(linear_interface).to have_received(:create_issue).with(hash_including(state_id: nil))
        end
      end
    end

    context "when there are HTML comment in the issue description" do
      let(:description) do
        'Something
<!--
A comment
-->
# Title
Some content.
'
      end

      let(:filtered_description) do
        'Something

# Title
Some content.
'
      end

      let(:issue) do
        Gitlab::Triage::Resource::Issue.new(
          { title: "Example", description:, labels: ["Team::Team 1", "other"], author: { username: author_username, name: "Author Full Name" },
            assignees: [{ username: author_username, email: "user@example.com" }] }, network: network_mock
        )
      end

      before do
        issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
        allow(linear_interface).to receive_messages(
          get_user_id_by_email: user_search_response["data"]["users"]["nodes"].first["id"], list_labels: issue_label_response
        )
        allow(linear_interface).to receive(:create_issue)
      end

      it "removes the HTML comment from the issue description" do
        connector.import_issue(issue)
        expect(linear_interface).to have_received(:create_issue).with(hash_including(description: filtered_description))
      end
    end
  end

  describe "#import_comments" do
    let(:issue) do
      Gitlab::Triage::Resource::Issue.new({ title: "Example", description: "Example desc.", labels: ["Team::Team 1", "other"], author: { username: author_username, name: "Author Full Name" } },
                                          network: network_mock)
    end

    let(:discussions) { JSON.load_file("spec/fixtures/discussions.json") }

    let(:expected_arguments) do
      [
        { body: discussions[5]["notes"][0]["body"], linear_issue_id: "123456",
          author_name: discussions[5]["notes"][0]["author"]["name"] },
        { body: discussions[6]["notes"][0]["body"], linear_issue_id: "123456",
          author_name: discussions[6]["notes"][0]["author"]["name"] },
        { body: discussions[6]["notes"][1]["body"], linear_issue_id: "123456",
          author_name: discussions[6]["notes"][1]["author"]["name"], parent_id: "b6b31d09-6561-4a77-a265-79e854086557" },
        { body: discussions[7]["notes"][0]["body"], linear_issue_id: "123456",
          author_name: discussions[7]["notes"][0]["author"]["name"] },
        { body: discussions[7]["notes"][1]["body"], linear_issue_id: "123456",
          author_name: discussions[7]["notes"][1]["author"]["name"], parent_id: "b6b31d09-6561-4a77-a265-79e854086557" }
      ]
    end

    before do
      issue.extend(Gitlab::Triage::Linear::Migrator::IssueExtension)
      allow(linear_interface).to receive(:create_comment).and_return(comment_create_response["data"]["commentCreate"]["comment"])
    end

    it "creates all the comments in Linear" do
      connector.import_comments(issue, discussions, "123456")

      expected_arguments.each do |args|
        expect(linear_interface).to have_received(:create_comment).with(hash_including(args))
      end
    end
  end
end
