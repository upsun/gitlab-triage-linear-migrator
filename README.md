<p style="text-align: center">
<a href="https://www.upsun.com/">
<img src="https://github.com/upsun/.github/blob/main/profile/logo.svg?raw=true" width="500px" alt="Upsun logo">
</a>
<br />
<br />
<a href="https://devcenter.upsun.com"><strong>Developer Center</strong></a>&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp
<a href="https://upsun.com/"><strong>Website</strong></a>&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp
<a href="https://docs.upsun.com"><strong>Documentation</strong></a>&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp
<a href="https://upsun.com/blog/"><strong>Blog</strong></a>&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp
<br /><br />
</p>

# Gitlab::Triage::Linear::Migrator

Extends Gitlab Triage with an action that migrates issues and epics to Linear (https://linear.app).

Initial version was developed by Platform.sh (https://platform.sh).

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after
releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section
with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

### Preparation

1. Create a policy file. You can use `support/triage_policies.example.yml` as a start/example. Read more about policy
   files in the Triage Bot documentation: https://www.rubydoc.info/gems/gitlab-triage. This migrator provides an extra
   `create_issue_in_linear()` action that can be used in a comment.
2. Extend Triage Bot with the Linear Migrator
    1. If you already have some extensions and using the --require option, simply add the below lines to the file
    2. If not, create a new file e.g. `triage_plugins.rb` and paste the code below (you can also copy the file
       `support/triage_plugins.example.rb`)
3. Set the required environment variables. On top of the standard Triage Bot command line arguments, we need extra
   options to
   pass over to the Migrator. See the list below.

#### Example policy

```yml
resource_rules:
  issues:
    rules:
      - name: Create issue in Linear
        limits:
          most_recent: 500
        conditions:
          labels:
            - "Linear::To Migrate"  # Remove this line if you want all issues to be migrated.
          #state: opened # Remove this if you want closed issues to be migrated as well.
          forbidden_labels:
            - "Linear::Migrated"
            - "Linear::Migration Failed"
          ruby: "!labels.map(&:name).grep(/^Guild::.+$/).empty?" # Change this to match team_label_prefix parameter below!
        actions:
          comment: |
            #{create_issue_in_linear(set_state: true, prepend_project_name: false, team_label_prefix: "Guild")}

```

Change the parameters as you wish:
  - `set_state`: set to true if you want your imported issues reflect the current state (group label `S::` in GitLab).
    Please note: issues in `S::Inbox` will be migrated to Triage if your team has Triage turned on in Linear.
    If Triage is turned off, issues will have the default issue state, which is indicated (and can be set) on your
    team's Workflow settings page in Linear.
  - `prepend_project_name`: true means all imported issues will have their titles starting with the GitLab project name.
    Set to false to simply copy the issue title as is.
  - `team_label_prefix`: The migration requires a label in Gitlab that can be used to set the team name in Linear.
    By default this label needs to be in this format `Team::Name of the team`. The team in Linear must be `Team: Name of the team`.
    You can change the `Team:` prefix by setting this parameter to anything you want (e.g. Guild as in the example above).
  
This comment action will post a comment with a link to the new issue in Linear, add Linear::Migrated label and close the issue.
  If the migration fails, it will add Linear::Migration Failed label and also some error debug information into the comment.

#### Migrating epics

If you want to migrate epics, you can add an Epics rule. Epics will be migrated as issues into Linear. Issues under epics
will be migrated as sub-issues below the issue.

```yml
resource_rules:
  epics:
   rules:
      - name: Create epic in Linear
        # ...
  issues:
    rules:
      - name: Create issue in Linear
        # ...
```

Note that epics in Gitlab only exist in the group level, so `--source` should be `group` when running the Triage Bot.

#### Extend the Triage Bot

```ruby
require "gitlab/triage/linear/migrator/issue_extension"
Gitlab::Triage::Resource::Context.include Gitlab::Triage::Linear::Migrator::IssueExtension
```

#### Environment variables

| Variable             | Description                                                                                                                                                                                          | Example                                   |
|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------|
| LINEAR_API_TOKEN     | API token to access Linear. See https://developers.linear.app/docs/oauth/authentication                                                                                                              | `Bearer lin_oauth_ssdjw23242349020492342` |
| IGNORE_LINEAR_DRYRUN | If this is set to anything, real Linear calls will be made when running Triage Bot with --dry-run. This is to test the migration on a test worspace without changing the opriginal issues in Gitlab. | `true`                                    |

### Run from your local (testing)

1. Simply run Triage Bot from the command line. 

Migrate a group:
` gitlab-triage --dry-run --token $GITLAB_API_TOKEN --source group --source-id gitlab-group --host-url https://your-gitlab-url.example.com --require ./triage-plugins.rb --policies-file 'triage-policies.yml'`

Migrate a project:
` gitlab-triage --dry-run --token $GITLAB_API_TOKEN --source project --source-id gitlab-group/project --host-url https://your-gitlab-url.example.com --require ./triage-plugins.rb --policies-file 'triage-policies.yml'`

Migrate an entire instance:
` gitlab-triage --dry-run --token $GITLAB_API_TOKEN --all --host-url https://your-gitlab-url.example.com --require ./triage-plugins.rb --policies-file 'triage-policies.yml'`


See https://gitlab.com/gitlab-org/ruby/gems/gitlab-triage/#running-with-the-installed-gem for more.

### Run from the CI (recommended)

See https://gitlab.com/gitlab-org/ruby/gems/gitlab-triage/#running-on-gitlab-ci-pipeline.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can
also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version,
push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/upsun/gitlab-triage-linear-migrator.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
