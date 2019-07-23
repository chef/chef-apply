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
require "support/matchers/output_to_terminal"

# class << Kernel
#   alias :_require :require
#   def require(*args)
#
#     show = false
#     args.each do |a|
#       if a =~ /chef_apply.*/
#         show = true
#         break
#       end
#     end
#
#     $stderr.puts "from #{File.basename(caller[1])}: require: %s" % [args.inspect] if show
#     _require(*args)
#   end
#
#   alias :_load :load
#   def load(*args)
#     show = false
#     args.each do |a|
#       if a =~ /chef_apply.*/
#         show = true
#         break
#       end
#     end
#     $stderr.puts "from #{File.basename(caller[1])}: load: %s" % [args.inspect] if show
#     _load(*args)
#   end
#
# end
#
# module Kernel
#   def require(*args)
#     Kernel.require(*args)
#   end
#   def load(*args)
#     Kernel.load(*args)
#   end
# end

RemoteExecResult = Struct.new(:exit_status, :stdout, :stderr)

class ChefApply::MockReporter
  def update(msg); ChefApply::UI::Terminal.output msg; end

  def success(msg); ChefApply::UI::Terminal.output "SUCCESS: #{msg}"; end

  def error(msg); ChefApply::UI::Terminal.output "FAILURE: #{msg}"; end
end

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
# TODO would read better to make this a custom matcher.
# Simulates a recursive string lookup on the Text object
#
# assert_string_lookup("tree.tree.tree.leaf", "a returned string")
# TODO this can be more cleanly expressed as a custom matcher...
def assert_string_lookup(key, retval = "testvalue")
  it "should look up string #{key}" do
    top_level_method, *call_seq = key.split(".")
    terminal_method = call_seq.pop
    tmock = double()
    # Because ordering is important
    # (eg calling errors.hello is different from hello.errors),
    # we need to add this individually instead of using
    # `receive_messages`, which doesn't appear to give a way to
    # guarantee ordering
    expect(ChefApply::Text).to receive(top_level_method)
      .and_return(tmock)
    call_seq.each do |m|
      expect(tmock).to receive(m).ordered.and_return(tmock)
    end
    expect(tmock).to receive(terminal_method)
      .ordered.and_return(retval)
    subject.call
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
    ChefApply::Log.setup File::NULL, :error
    ChefApply::UI::Terminal.init(File.open(File::NULL, "w"))
  end
end

if ENV["CIRCLE_ARTIFACTS"]
  dir = File.join(ENV["CIRCLE_ARTIFACTS"], "coverage")
  SimpleCov.coverage_dir(dir)
end
SimpleCov.start
