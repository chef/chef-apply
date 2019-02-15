#
# Copyright:: Copyright (c) 2018 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "bundler/setup"
require "simplecov"
require "rspec/expectations"

# Unit tests hit paths which expect i18n localizations
# to have been loaded.
require "chef_core/cliux/ui/terminal"
require "chef_apply/startup"

ChefApply::Startup.new([]).load_localizations

RSpec::Matchers.define :exit_with_code do |expected_code|
  actual_code = nil
  match do |block|
    begin
      block.call
    rescue SystemExit => e
      actual_code = e.status
    end
    actual_code && actual_code == expected_code
  end

  failure_message do |block|
    result = actual.nil? ? " did not call exit" : " called exit(#{actual_code})"
    "expected exit(#{expected_code}) but it #{result}."
  end

  failure_message_when_negated do |block|
    "expected exit(#{expected_code}) but it did."
  end

  description do
    "expect exit(#{expected_code})"
  end

  supports_block_expectations do
    true
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.before(:all) do
    ChefCore::Log.setup "/dev/null", :error
    ChefCore::CLIUX::UI::Terminal.init(File.open("/dev/null", "w"))
  end
end

if ENV["CIRCLE_ARTIFACTS"]
  dir = File.join(ENV["CIRCLE_ARTIFACTS"], "coverage")
  SimpleCov.coverage_dir(dir)
end
SimpleCov.start
