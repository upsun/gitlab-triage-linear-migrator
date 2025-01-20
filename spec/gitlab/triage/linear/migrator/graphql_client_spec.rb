# frozen_string_literal: true

require "webmock/rspec"
require "net/http"
require "gitlab/triage/linear/migrator/graphql_client"

RSpec.describe Gitlab::Triage::Linear::Migrator::GraphqlClient do
  subject(:client) { described_class.new("https:/example.com") }

  let(:endpoint) { "https:/example.com" }
  let(:query_string) { "query_string" }
  let(:variables) { { var1: "val1", var2: "val2" } }
  let(:cache_key) { [query_string, variables].hash }

  describe "#query" do
    let(:cache_hit) { false }

    before do
      allow(client).to receive(:log_query)
      allow(client).to receive(:cache_hit?).with(cache_key).and_return(cache_hit)
      allow(client).to receive(:cached_result).with(cache_key).and_return("cached result")
      allow(client).to receive(:execute).with(query_string, variables).and_return("fresh result")
      allow(client).to receive(:cache_result)
    end

    context "when the query is in the cache" do
      let(:cache_hit) { true }

      it "returns the cached result" do
        expect(client.query(query_string, variables)).to eq("cached result")
      end

    end

    context "when the query is not in the cache" do
      let(:cache_hit) { false }

      it "returns the result from execution" do
        expect(client.query(query_string, variables)).to eq("fresh result")
      end

      it "caches the result" do
        client.query(query_string, variables)
        expect(client).to have_received(:cache_result).with(cache_key, "fresh result")
      end
    end
  end

  describe "#mutation" do
    let(:mutation_string) { "mutation { something }" }
    let(:variables) { { "key" => "value" } }

    context "when dry run mode" do
      before do
        client.dry_run = true
        allow(client).to receive(:log_dry_run).with(mutation_string, variables)
        client.mutation(mutation_string, variables)
      end

      it "logs the dry run" do
        expect(client).to have_received(:log_dry_run)
      end
    end

    context "when not dry run mode" do
      before do
        client.dry_run = false
        allow(client).to receive(:log_query).with(mutation_string, variables)
        allow(client).to receive(:execute).with(mutation_string, variables)
        client.mutation(mutation_string, variables)
      end

      it "logs the query" do
        expect(client).to have_received(:log_query)
      end

      it "executes the query" do
        expect(client).to have_received(:execute)
      end
    end
  end

  describe "rate limit handling" do
    let(:rate_limit_response) do
      '{
        "errors": [
          {
            "message": "Rate limit exceeded",
            "extensions": {
              "code": "RATELIMITED"
            }
          }
        ]
      }'
    end

    it "raises an error when rate limit exceeded #{Gitlab::Triage::Linear::Migrator::GraphqlClient::THROTTLE_RETRIES} times" do
      response = instance_double(Net::HTTPResponse)
      allow(response).to receive_messages(body: rate_limit_response, code: 400)
      allow(client).to receive(:send_request).and_return(response)
      client.sleep_duration = 0
      expect do
        client.query(query_string,
                     variables)
      end.to raise_error(StandardError,
                         "Rate limit reached after #{Gitlab::Triage::Linear::Migrator::GraphqlClient::THROTTLE_RETRIES} retries")
    end
  end
end
