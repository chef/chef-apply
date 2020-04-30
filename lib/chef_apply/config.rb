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

require_relative "log"
require "mixlib/config"
require "fileutils"
require "pathname"
require "chef-config/config"
require "chef-config/workstation_config_loader"

module ChefApply
  class Config
    WS_BASE_PATH = File.join(Dir.home, ".chef-workstation/")
    SUPPORTED_PROTOCOLS = %w{ssh winrm}.freeze

    class << self
      @custom_location = nil

      # Ensure when we extend Mixlib::Config that we load
      # up the workstation config since we will need that
      # to converge later
      def initialize_mixlib_config
        super
      end

      def custom_location(path)
        @custom_location = path
        raise "No config file located at #{path}" unless exist?
      end

      def default_location
        File.join(WS_BASE_PATH, "config.toml")
      end

      def telemetry_path
        File.join(WS_BASE_PATH, "telemetry")
      end

      def telemetry_session_file
        File.join(telemetry_path, "TELEMETRY_SESSION_ID")
      end

      def telemetry_installation_identifier_file
        File.join(WS_BASE_PATH, "installation_id")
      end

      def base_log_directory
        File.dirname(log.location)
      end

      # These paths are relative to the log output path, which is user-configurable.
      def error_output_path
        File.join(base_log_directory, "errors.txt")
      end

      def stack_trace_path
        File.join(base_log_directory, "stack-trace.log")
      end

      def using_default_location?
        @custom_location.nil?
      end

      def location
        using_default_location? ? default_location : @custom_location
      end

      def load
        if exist?
          from_file(location)
        end
      end

      def exist?
        File.exist? location
      end

      def reset
        @custom_location = nil
        super
      end
    end

    extend Mixlib::Config

    # This configuration is shared among many components.
    # While enabling strict mode can provide a better experience
    # around validated config entries, chef-apply won't know about
    # config items that it doesn't own, and we don't want it to
    # fail to start when that happens.
    config_strict_mode false

    # When working on Chef Apply itself,
    # developers should set telemetry.dev to true
    # in their local configuration to ensure that dev usage
    # doesn't skew customer telemetry.
    config_context :telemetry do
      default(:dev_mode, false)
      default(:enabled, true)
    end

    config_context :log do
      default(:level, "warn")
      configurable(:location)
        .defaults_to(File.join(WS_BASE_PATH, "logs/default.log"))
        .writes_value { |p| File.expand_path(p) }
      # set the log level for the target host's chef-client run
      default(:target_level, nil)
    end

    config_context :cache do
      configurable(:path)
        .defaults_to(File.join(WS_BASE_PATH, "cache"))
        .writes_value { |p| File.expand_path(p) }
    end

    config_context :connection do
      default(:default_protocol, "ssh")
      default(:default_user, nil)

      config_context :winrm do
        default(:ssl, false)
        default(:ssl_verify, true)
      end
    end

    config_context :dev do
      default(:spinner, true)
    end

    config_context :chef do
      # We want to use any configured chef repo paths or trusted certs in
      # ~/.chef/knife.rb on the user's workstation. But because they could have
      # config that could mess up our Policyfile creation later we reset the
      # ChefConfig back to default after loading that.
      ChefConfig::WorkstationConfigLoader.new(nil, ChefApply::Log).load
      default(:cookbook_repo_paths, [ChefConfig::Config[:cookbook_path]].flatten)
      default(:trusted_certs_dir, ChefConfig::Config[:trusted_certs_dir])
      default(:chef_license, ChefConfig::Config[:chef_license])
      ChefConfig::Config.reset
    end

    config_context :data_collector do
      default :url, nil
      default :token, nil
    end

    config_context :updates do
      default :channel, nil
      default :interval_minutes, nil
      default :enable, nil
    end
  end
end
