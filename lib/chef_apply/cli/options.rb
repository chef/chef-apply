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

require_relative "../text"

# Moving the options into here so the cli.rb file is smaller and easier to read
# For options that need to be merged back into the global ChefApply::Config object
#   we do that with a proc in the option itself. We decided to do that because it is
#   an easy, straight forward way to merge those options when they do not directly
#   map back to keys in the Config global. IE, we cannot just do
#   `ChefApply::Config.merge!(options)` because the keys do not line up, and we do
#   not want all CLI params merged back into the global config object.
# We know that the config is already loaded from the file (or program defaults)
#   because the `Startup` class was invoked to start the program.
module ChefApply
  class CLI
    module Options

      T = ChefApply::Text.cli
      TS = ChefApply::Text.status

      def self.included(klass)
        klass.banner T.description(ChefApply::Dist::RUN, ChefApply::Dist::SHORT) + "\n" + T.usage_full(ChefApply::Dist::RUNEXEC, ChefApply::Dist::SHORT, ChefApply::Dist::EXEC)

        klass.option :version,
          short: "-v",
          long: "--version",
          description:  T.version.description(ChefApply::Dist::RUN),
          boolean: true

        klass.option :help,
          short: "-h",
          long: "--help",
          description:   T.help.description(ChefApply::Dist::RUNEXEC),
          boolean: true

        # Special note:
        # config_path is pre-processed in startup.rb, and is shown here only
        # for purpoess of rendering help text.
        klass.option :config_path,
          short: "-c PATH",
          long: "--config PATH",
          description: T.default_config_location(ChefApply::Config.default_location),
          default: ChefApply::Config.default_location,
          proc: Proc.new { |path| ChefApply::Config.custom_location(path) }

        klass.option :identity_file,
          long: "--identity-file PATH",
          short: "-i PATH",
          description: T.identity_file,
          proc: (Proc.new do |paths|
            path = paths
            unless File.readable?(path)
              raise OptionValidationError.new("CHEFVAL001", nil, path)
            end

            path
          end)

        klass.option :ssl,
          long: "--[no-]ssl",
          description:  T.ssl.desc(ChefApply::Config.connection.winrm.ssl),
          boolean: true,
          default: ChefApply::Config.connection.winrm.ssl,
          proc: Proc.new { |val| ChefApply::Config.connection.winrm.ssl(val) }

        klass.option :ssl_verify,
          long: "--[no-]ssl-verify",
          description:  T.ssl.verify_desc(ChefApply::Config.connection.winrm.ssl_verify),
          boolean: true,
          default: ChefApply::Config.connection.winrm.ssl_verify,
          proc: Proc.new { |val| ChefApply::Config.connection.winrm.ssl_verify(val) }

        klass.option :protocol,
          long: "--protocol <PROTOCOL>",
          short: "-p",
          description: T.protocol_description(ChefApply::Config::SUPPORTED_PROTOCOLS.join(" "),
            ChefApply::Config.connection.default_protocol),
          default: ChefApply::Config.connection.default_protocol,
          proc: Proc.new { |val| ChefApply::Config.connection.default_protocol(val) }

        klass.option :user,
          long: "--user <USER>",
          description: T.user_description

        klass.option :password,
          long: "--password <PASSWORD>",
          description: T.password_description

        klass.option :cookbook_repo_paths,
          long: "--cookbook-repo-paths PATH",
          description: T.cookbook_repo_paths,
          default: ChefApply::Config.chef.cookbook_repo_paths,
          proc: (Proc.new do |paths|
            paths = paths.split(",")
            ChefApply::Config.chef.cookbook_repo_paths(paths)
            paths
          end)

        klass.option :install,
          long: "--[no-]install",
          default: true,
          boolean: true,
          description:  T.install_description(ChefApply::Dist::CLIENT)

        klass.option :sudo,
          long: "--[no-]sudo",
          description: T.sudo.flag_description.sudo,
          boolean: true,
          default: true

        klass.option :sudo_command,
          long: "--sudo-command <COMMAND>",
          default: "sudo",
          description: T.sudo.flag_description.command

        klass.option :sudo_password,
          long: "--sudo-password <PASSWORD>",
          description: T.sudo.flag_description.password

        klass.option :sudo_options,
          long: "--sudo-options 'OPTIONS...'",
          description: T.sudo.flag_description.options
      end

      # I really don't like that mixlib-cli refers to the parsed command line flags in
      # a hash accesed via the `config` method. Thats just such an overloaded word.
      def parsed_options
        config
      end
    end
  end
end
