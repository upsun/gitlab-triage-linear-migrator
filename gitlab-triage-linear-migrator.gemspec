# frozen_string_literal: true

require_relative "lib/gitlab/triage/linear/migrator/version"

Gem::Specification.new do |spec|
  spec.name = "gitlab-triage-linear-migrator"
  spec.version = Gitlab::Triage::Linear::Migrator::VERSION
  spec.authors = ["Molnár Roland"]
  spec.email = ["roland.molnar@gmail.com"]

  spec.summary = "Triage Bot extension to migrate GitLab issues to Linear."
  spec.description = "Extends GitLab Triage Bot with actions to import issues into Linear (https://linear.app)"
  spec.homepage = "https://github.com/upsun/gitlab-triage-linear-migrator"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://example.com"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/upsun/gitlab-triage-linear-migrator"
  spec.metadata["changelog_uri"] = "https://github.com/upsun/gitlab-triage-linear-migrator"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .gitlab-ci.yml appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  spec.add_dependency "gitlab", "~> 4.19"
  spec.add_dependency "gitlab-triage", "~> 1.42"
  spec.add_dependency "rainbow"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end
