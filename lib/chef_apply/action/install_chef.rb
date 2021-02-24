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

require_relative "base"
require_relative "install_chef/minimum_chef_version"
require "fileutils" unless defined?(FileUtils)

module ChefApply
  module Action
    class InstallChef < Base
      def initialize(opts = { check_only: false })
        super
      end

      def perform_action
        if InstallChef::MinimumChefVersion.check!(target_host, config[:check_only]) == :minimum_version_met
          notify(:already_installed)
        else
          perform_local_install
        end
      end

      def upgrading?
        @upgrading
      end

      def perform_local_install
        package = lookup_artifact
        notify(:downloading)
        local_path = download_to_workstation(package.url)
        notify(:uploading)
        remote_path = upload_to_target(local_path)
        notify(:installing)
        require 'byebug'
        byebug
        target_host.install_package(remote_path)
        notify(:install_complete)
      end

      def perform_remote_install
        # TODO BOOTSTRAP - we'll need to implement this for both platforms
        # require "mixlib/install"
        # installer = Mixlib::Install.new({
        #   platform: "windows",/etc -
        #   product_name: "chef",
        #   channel: :stable,
        #   shell_type: :ps1,
        #   version: "13",
        # })
        # target_host.run_command! installer.install_command
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
          platform_version_compatibility_mode: true,
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
        require_relative "../file_fetcher"
        ChefApply::FileFetcher.fetch(url_path)
      end

      def upload_to_target(local_path)
        installer_dir = target_host.temp_dir
        remote_path = File.join(installer_dir, File.basename(local_path))
        target_host.upload_file(local_path, remote_path)
        remote_path
      end
    end
  end
end
