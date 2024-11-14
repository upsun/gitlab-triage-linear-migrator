# frozen_string_literal: true

require "gitlab/triage/linear/migrator/graphql_client"
require "gitlab/triage/linear/migrator/linear_connector"
require "gitlab/triage/linear/migrator/linear_interface"

RSpec.describe Gitlab::Triage::Linear::Migrator::LinearInterface do
  subject(:linear_interface) do
    described_class.new(graphql_client:)
  end

  let(:graphql_client) do
    instance_double(Gitlab::Triage::Linear::Migrator::GraphqlClient)
  end

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

  describe "#get_teams_by_name" do
    before do
      allow(graphql_client).to receive(:query).with(Gitlab::Triage::Linear::Migrator::LinearInterface::GET_TEAM_BY_NAME_QUERY,
                                                    { name: "team name" }).and_return(team_search_response)
    end

    context "when no team has found" do
      let(:team_search_response) do
        {
          "data" => {
            "teams" => {
              "nodes" => []
            }
          }
        }
      end

      it "raises an exception" do
        expect { linear_interface.send(:get_team_by_name, "team name") }.to raise_error(StandardError)
      end
    end

    context "when teams are returned" do
      it "returns the teams array" do
        expect(linear_interface.send(:get_team_by_name,
                                     "team name")).to eq(team_search_response["data"]["teams"]["nodes"].first)
      end
    end
  end
end
