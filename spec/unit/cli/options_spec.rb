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

require "spec_helper"
require "mixlib/cli"
require "chef_apply/cli/options"
require "chef-config/config"

ChefApply::Config.load

module ChefApply
  module CLIOptions
    class TestClass
      include Mixlib::CLI
      include ChefApply::CLI::Options
    end

    def parse(argv)
      parse_options(argv)
    end
  end
end

RSpec.describe ChefApply::CLIOptions do
  let(:klass) { ChefApply::CLIOptions::TestClass.new }

  it "contains the specified options" do
    expect(klass.options.keys).to eq([
      :version,
      :help,
      :config_path,
      :identity_file,
      :ssl,
      :ssl_verify,
      :protocol,
      :user,
      :password,
      :cookbook_repo_paths,
      :install,
      :sudo,
      :sudo_command,
      :sudo_password,
      :sudo_options
    ])
  end

  it "persists certain CLI options back to the ChefApply::Config" do
    # First we check the default value beforehand
    expect(ChefApply::Config.connection.winrm.ssl).to eq(false)
    expect(ChefApply::Config.connection.winrm.ssl_verify).to eq(true)
    expect(ChefApply::Config.connection.default_protocol).to eq("ssh")
    expect(ChefApply::Config.chef.cookbook_repo_paths).to_not be_empty
    # Then we set the values and check they are changed
    klass.parse_options(["--ssl", "--no-ssl-verify", "--protocol", "winrm", "--cookbook-repo-paths", "a,b"])
    expect(ChefApply::Config.connection.winrm.ssl).to eq(true)
    expect(ChefApply::Config.connection.winrm.ssl_verify).to eq(false)
    expect(ChefApply::Config.connection.default_protocol).to eq("winrm")
    expect(ChefApply::Config.chef.cookbook_repo_paths).to eq(%w{a b})
  end

end
