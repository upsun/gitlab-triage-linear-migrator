# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "query_logger"

module Gitlab
  module Triage
    module Linear
      module Migrator
        # Client class for the GraphQL queries
        class GraphqlClient
          THROTTLE_RETRIES = 3

          attr_reader :endpoint, :headers
          attr_accessor :dry_run, :sleep_duration

          include QueryLogger

          def initialize(endpoint, headers = {}, dry_run: false)
            @sleep_duration = 30
            @endpoint = endpoint
            @headers = headers
            @dry_run = dry_run

            @uri = URI.parse(@endpoint)
            @http = Net::HTTP.new(@uri.host, @uri.port)
            @http.use_ssl = @uri.scheme == "https"
            @cache = {}
          end

          def query(query_string, variables = {})
            log_query(query_string, variables)
            cache_key = [query_string, variables].hash
            return cached_result(cache_key) if cache_hit?(cache_key)

            result = execute(query_string, variables)
            cache_result(cache_key, result)
            result
          end

          def mutation(mutation_string, variables = {})
            if @dry_run
              log_dry_run(mutation_string, variables)
              return nil
            end

            log_query(mutation_string, variables)
            execute(mutation_string, variables)
          end

          private

          def cache_result(cache_key, result)
            @cache[cache_key] = result
          end

          def cached_result(cache_key)
            log_cache_hit(cache_key)
            log_response(@cache[cache_key])
            @cache[cache_key]
          end

          def cache_hit?(cache_key)
            @cache.key?(cache_key)
          end

          def execute(graphql_string, variables)
            retries = 0

            while retries < THROTTLE_RETRIES
              response = send_request(graphql_string, variables)
              parsed_response = JSON.parse(response.body)

              if should_retry?(response, parsed_response)
                retries += 1
                sleep(@sleep_duration)
              elsif parsed_response["errors"]
                errors_string = parsed_response["errors"].map { |error| error["message"] }.join(", ")
                log_error(errors_string)
                raise StandardError, "GraphQL Error: #{errors_string}"
              else
                return parsed_response
              end
            end

            raise StandardError, "Rate limit reached after #{THROTTLE_RETRIES} retries"
          end

          def send_request(graphql_string, variables)
            request = Net::HTTP::Post.new(@uri.request_uri, @headers)
            request["Content-Type"] = "application/json"
            request.body = { query: graphql_string, variables: }.to_json

            response = @http.request(request)
            log_response(response.body)
            response
          end

          def should_retry?(response, parsed_response)
            return false unless parsed_response.is_a?(Hash) && parsed_response["errors"].is_a?(Array)

            response.code.to_i.between?(400, 499) &&
              parsed_response["errors"].any? { |error| error.dig("extensions", "code") == "RATELIMITED" }
          end
        end
      end
    end
  end
end
