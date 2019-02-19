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

require "chef_apply/config"
require "chef_core/text"
require "chef_core/cliux/ui/terminal"
require "chef_core/telemeter/sender"
require "chef/log"
require "chef/config"
module ChefApply
  class Startup
    attr_reader :argv
    I18NIZED_GEMS = %w{chef_core-actions chef_core-cliux chef-apply}.freeze
    UI = ChefCore::CLIUX::UI
    def initialize(argv)
      @term_init = false
      @argv = argv.clone
      # Enable CLI output via Terminal. This comes first because other startup steps may
      # need to output to the terminal.
      init_terminal
    end

    def run
      # This component is not supported in ChefDK; an exception will be raised
      # if running in that context.
      verify_not_in_chefdk

      load_localizations

      # Some tasks we do only once in an installation:
      first_run_tasks

      # Call this every time, so that if we add or change ~/.chef-workstation
      # directory structure, we can be sure that it exists. Even with a
      # custom configuration, the .chef-workstation directory and subdirs
      # are required.
      setup_workstation_user_directories

      # Customize behavior of Ruby and any gems around error handling
      setup_error_handling

      # Startup tasks that may change behavior based on configuration value
      # must be run after load_config
      load_config

      # Init logging using log level out of config
      setup_logging

      # Begin upload of previous session telemetry. (If telemetry is not enabled,
      # in config the uploader will clean up previous session(s) without sending)
      start_telemeter

      # Launch the actual Chef Apply behavior
      start_chef_apply

    # NOTE: Because these exceptions occur outside of the
    #       CLI handling, they won't be tracked in telemetry.
    rescue ConfigPathInvalid => e

      UI::Terminal.output(ChefCore::Text.cli.error.bad_config_file(e.path))
    rescue ConfigPathNotProvided
      UI::Terminal.output(ChefCore::Text.cli.error.missing_config_path)
    rescue UnsupportedInstallation
      UI::Terminal.output(ChefCore::Text.cli.error.unsupported_installation)
    rescue Mixlib::Config::UnknownConfigOptionError => e
      # Ideally we'd update the exception in mixlib to include
      # a field with the faulty value, line number, and nested context -
      # it's less fragile than depending on text parsing, which
      # is what we'll do for now.
      if e.message =~ /.*unsupported config value (.*)[.]+$/
        # TODO - levenshteinian distance to figure out
        # what they may have meant instead.
        UI::Terminal.output(ChefCore::Text.cli.error.invalid_config_key($1, Config.location))
      else
        # Safety net in case the error text changes from under us.
        UI::Terminal.output(ChefCore::Text.cli.error.unknown_config_error(e.message, Config.location))
      end
    rescue Tomlrb::ParseError => e
      UI::Terminal.output(ChefCore::Text.cli.error.unknown_config_error(e.message, Config.location))
    end

    def init_terminal
      UI::Terminal.init($stdout)
    end

    # Verify that chef-run gem is not executing out of ChefDK by checking the
    # runtime path of this file.
    #
    # NOTE: This is imperfect - someone could theoretically
    # install chefdk to a path other than the default.
    def verify_not_in_chefdk
      raise UnsupportedInstallation.new if script_path =~ /chefdk/
    end

    def load_localizations
      I18NIZED_GEMS.each do |gem_name|
        ChefCore::Text.add_gem_localization(gem_name)
      end
    end

    def first_run_tasks
      return if Dir.exist?(Config::WS_BASE_PATH)
      create_default_config
      setup_telemetry
    end

    def create_default_config
      UI::Terminal.output ChefCore::Text.cli.creating_config(Config.default_location)
      UI::Terminal.output ""
      FileUtils.mkdir_p(Config::WS_BASE_PATH)
      FileUtils.touch(Config.default_location)
    end

    def setup_telemetry
      require "securerandom"
      installation_id = SecureRandom.uuid
      File.write(Config.telemetry_installation_identifier_file, installation_id)

      # Tell the user we're anonymously tracking, give brief opt-out
      # and a link to detailed information.
      UI::Terminal.output ChefCore::Text.cli.telemetry_enabled(Config.location)
      UI::Terminal.output ""
    end

    def start_telemeter
      telemetry_config = { payload_dir: Config.telemetry_path,
                           session_file: Config.telemetry_session_file,
                           installation_identifier_file: Config.telemetry_installation_identifier_file,
                           enabled: Config.telemetry.enable,
                           dev_mode: Config.telemetry.dev }

      ChefCore::Telemeter.setup(telemetry_config)
    end

    def setup_workstation_user_directories
      # Note that none of  these paths are customizable in config, so
      # it's safe to do before we load config.
      FileUtils.mkdir_p(Config::WS_BASE_PATH)
      FileUtils.mkdir_p(Config.base_log_directory)
      FileUtils.mkdir_p(Config.telemetry_path)
    end

    def setup_error_handling
      # In Ruby 2.5+ threads print out to stdout when they raise an exception. This is an agressive
      # attempt to ensure debugging information is not lost, but in our case it is not necessary
      # because we handle all the errors ourself. So we disable this to keep output clean.
      # See https://ruby-doc.org/core-2.5.0/Thread.html#method-c-report_on_exception
      #
      # We set this globally so that it applies to all threads we create - we never want any non-UI thread
      # to render error output to the terminal.
      Thread.report_on_exception = false
    end

    def load_config
      path = custom_config_path
      Config.custom_location(path) unless path.nil?
      Config.load
    end

    # Look for a user-supplied config path by  manually parsing the option.
    # Note that we can't use Mixlib::CLI for this.
    # To ensure that ChefApply::CLI initializes with correct
    # option defaults, we need to have configuraton loaded before initializing it.
    def custom_config_path
      argv.each_with_index do |arg, index|
        if arg == "--config-path" || arg == "-c"
          next_arg = argv[index + 1]
          raise ConfigPathNotProvided.new if next_arg.nil?
          raise ConfigPathInvalid.new(next_arg) unless File.file?(next_arg) && File.readable?(next_arg)
          return next_arg
        end
      end
      nil
    end

    def setup_logging
      ChefCore::Log.setup(Config.log.location, Config.log.level.to_sym)
      ChefCore::Log.info("Initialized logger")

      ChefConfig.logger = ChefCore::Log
      # Setting the config isn't enough, we need to ensure the logger is initialized
      # or automatic initialization will still go to stdout
      Chef::Log.init(ChefCore::Log.location)
      Chef::Log.level = ChefCore::Log.level
    end

    def start_chef_apply
      require "chef_apply/cli"
      ChefApply::CLI.new(@argv).run
    end

    private

    def script_path
      File.expand_path File.dirname(__FILE__)
    end

    class ConfigPathNotProvided < StandardError; end
    class ConfigPathInvalid < StandardError
      attr_reader :path
      def initialize(path)
        @path = path
      end
    end
    class UnsupportedInstallation < StandardError; end
  end
end
