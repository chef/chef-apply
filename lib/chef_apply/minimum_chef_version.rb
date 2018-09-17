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

require "chef_apply/error"

module ChefApply
  class MinimumChefVersion

    CONSTRAINTS = {
      windows: {
        13 => Gem::Version.new("13.10.4"),
        14 => Gem::Version.new("14.4.22")
      },
      linux: {
        13 => Gem::Version.new("13.10.4"),
        14 => Gem::Version.new("14.1.1")
      },
      macos: {
        13 => Gem::Version.new("13.10.4"),
        14 => Gem::Version.new("14.1.1")
      }
    }

    def self.check!(target, check_only)
      begin
        installed_version = target.installed_chef_version
      rescue ChefApply::TargetHost::ChefNotInstalled
        if check_only
          raise ClientNotInstalled.new()
        end
        return :client_not_installed
      end

      os_constraints = CONSTRAINTS[target.base_os]
      min_14_version = os_constraints[14]
      min_13_version = os_constraints[13]

      case
        when installed_version >= Gem::Version.new("14.0.0") && installed_version < min_14_version
          raise Client14Outdated.new(installed_version, min_14_version)
        when installed_version >= Gem::Version.new("13.0.0") && installed_version < min_13_version
          raise Client13Outdated.new(installed_version, min_13_version, min_14_version)
        when installed_version < Gem::Version.new("13.0.0")
          # If they have Chef < 13.0.0 installed we want to show them the easiest upgrade path -
          # Chef 13 first and then Chef 14 since most customers cannot make the leap directly
          # to 14.
          raise Client13Outdated.new(installed_version, min_13_version, min_14_version)
      end

      :minimum_version_met
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
end
