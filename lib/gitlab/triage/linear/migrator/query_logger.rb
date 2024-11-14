# frozen_string_literal: true

require "rainbow"

module Gitlab
  module Triage
    module Linear
      module Migrator
        # Provides functions to log a query or result to the output.
        module QueryLogger
          def log_query(query_string, variables)
            puts Rainbow("Query: #{query_string}").cyan
            puts Rainbow("Variables: #{variables}").yellow
          end

          def log_response(response)
            puts Rainbow("Response: #{response}").green
          end

          def log_cache_hit(cache_key)
            puts Rainbow("Cache hit for key: #{cache_key}").green
          end

          def log_dry_run(mutation_string, variables)
            puts Rainbow("DRY-RUN:").blue
            puts Rainbow(mutation_string).blue
            puts Rainbow(variables).blue
          end

          def log_error(errors)
            puts Rainbow("GraphQL Error: #{errors}").red
          end
        end
      end
    end
  end
end
