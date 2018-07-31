#
# Copyright:: Copyright (c) 2017 Chef Software Inc.
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

require "chef_apply/action/base"
require "fileutils"

module ChefApply::Action::InstallChef
  class Base < ChefApply::Action::Base
    MIN_14_VERSION = Gem::Version.new("14.1.1")
    MIN_13_VERSION = Gem::Version.new("13.10.0")

    def perform_action
      if check_minimum_chef_version!(target_host) == :minimum_version_met
        notify(:already_installed)
      else
        perform_local_install
      end
    end

    def name
      # We have subclasses - so this'll take the qualified name
      # eg InstallChef::Windows, etc
      self.class.name.split("::")[-2..-1].join("::")
    end

    def upgrading?
      @upgrading
    end

    def perform_local_install
      package = lookup_artifact()
      notify(:downloading)
      local_path = download_to_workstation(package.url)
      notify(:uploading)
      remote_path = upload_to_target(local_path)
      notify(:installing)
      install_chef_to_target(remote_path)
      notify(:install_complete)
    end

    def perform_remote_install
      raise NotImplementedError
    end

    def lookup_artifact
      return @artifact_info if @artifact_info
      require "mixlib/install"
      c = train_to_mixlib(target_host.platform)
      Mixlib::Install.new(c).artifact_info
    end

    def version_to_install
      lookup_artifact.version
    end

    def train_to_mixlib(platform)
      opts = {
        platform_version: platform.release,
        platform: platform.name,
        architecture: platform.arch,
        product_name: "chef",
        product_version: :latest,
        channel: :stable,
        platform_version_compatibility_mode: true
      }
      case platform.name
      when /windows/
        opts[:platform] = "windows"
      when "redhat", "centos"
        opts[:platform] = "el"
      when "suse"
        opts[:platform] = "sles"
      when "amazon"
        opts[:platform] = "el"
        if platform.release.to_i > 2010 # legacy Amazon version 1
          opts[:platform_version] = "6"
        else
          opts[:platform_version] = "7"
        end
      end
      opts
    end

    def download_to_workstation(url_path)
      require "chef_apply/file_fetcher"
      ChefApply::FileFetcher.fetch(url_path)
    end

    def upload_to_target(local_path)
      installer_dir = setup_remote_temp_path()
      remote_path = File.join(installer_dir, File.basename(local_path))
      target_host.upload_file(local_path, remote_path)
      remote_path
    end

    def check_minimum_chef_version!(target)
      begin
        installed_version = target.installed_chef_version
      rescue ChefApply::TargetHost::ChefNotInstalled
        if config[:check_only]
          raise ClientNotInstalled.new()
        end
        return :client_not_installed
      end

      case
        when installed_version >= Gem::Version.new("14.0.0") && installed_version < MIN_14_VERSION
          raise Client14Outdated.new(installed_version, MIN_14_VERSION)
        when installed_version >= Gem::Version.new("13.0.0") && installed_version < MIN_13_VERSION
          raise Client13Outdated.new(installed_version, MIN_13_VERSION, MIN_14_VERSION)
        when installed_version < Gem::Version.new("13.0.0")
          # If they have Chef < 13.0.0 installed we want to show them the easiest upgrade path -
          # Chef 13 first and then Chef 14 since most customers cannot make the leap directly
          # to 14.
          raise Client13Outdated.new(installed_version, MIN_13_VERSION, MIN_14_VERSION)
      end

      :minimum_version_met
    end

    def setup_remote_temp_path
      raise NotImplementedError
    end

    def install_chef_to_target(remote_path)
      raise NotImplementedError
    end
  end

  class ClientNotInstalled < ChefApply::ErrorNoLogs
    def initialize(); super("CHEFINS002"); end
  end

  class Client13Outdated < ChefApply::ErrorNoLogs
    def initialize(current_version, min_13_version, min_14_version)
      super("CHEFINS003", current_version, min_13_version, min_14_version)
    end
  end

  class Client14Outdated < ChefApply::ErrorNoLogs
    def initialize(current_version, target_version)
      super("CHEFINS004", current_version, target_version)
    end
  end
end
