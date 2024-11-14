# frozen_string_literal: true

require "rspec"
require "gitlab/triage/network"
require "gitlab/triage/resource/issue"
require "gitlab/triage/linear/migrator/issue_extension"

RSpec.describe Gitlab::Triage::Linear::Migrator::IssueExtension do
  subject(:resource) do
    Gitlab::Triage::Resource::Issue.new({ title: "Example", labels: [], author: { username: author_username } },
                                        network: network_mock)
  end

  let(:network_mock) do
    instance_double(Gitlab::Triage::Network)
  end
  let(:author_username) { "author_user" }

  before do
    resource.extend(described_class)
    allow(resource).to receive(:build_url).and_return("")
  end

  describe "#find_linear_id_in_gitlab" do
    subject(:resource) do
      Gitlab::Triage::Resource::Issue.new(
        { title: "Example", labels: [], author: { username: author_username },
          epic: { id: 2, group_id: 1, url: "groups/1/epics/2" } }, network: network_mock
      )
    end

    let(:discussions) { JSON.load_file("spec/fixtures/discussions.json") }

    before do
      discussions[0]["body"] =
        %(Issue created in Linear: 'https://linear.app/test/IS-1234/issue-title'

Linear issue ID: 358f888c-4d54-4ac0-b91a-2c9a06764356
    )

      allow(resource).to receive(:build_url).with(params: {},
                                                  options: { source: "groups", resource_type: "epics", resource_id: 2, source_id: 1,
                                                             sub_resource_type: "notes" }).and_return("groups/1/epics/2/notes")
      allow(network_mock).to receive(:query_api_cached).with("groups/1/epics/2/notes").and_return(discussions)
    end

    it "returns the Linear issue number" do
      expect(resource.find_linear_id_in_gitlab).to eq("358f888c-4d54-4ac0-b91a-2c9a06764356")
    end
  end

  describe "discussion handling" do
    before do
      allow(resource).to receive(:build_url).with(options: { resource_id: nil, sub_resource_type: "discussions" },
                                                  params: {}).and_return("merge_requests/1/discussions")
      allow(network_mock).to receive(:query_api_cached).with("merge_requests/1/discussions").and_return(discussions)
    end

    let(:discussions) { JSON.load_file("spec/fixtures/discussions.json") }

    describe "#discussions" do
      it "returns all the 8 note items of the issue" do
        expect(resource.discussions.length).to eq(8)
      end
    end

    describe "#human_discussions" do
      it "returns only the 3 human comments of the issue" do
        expect(resource.human_discussions.length).to eq(3)
      end
    end
  end
end
