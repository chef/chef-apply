#
# Copyright:: Copyright (c) 2018-2019 Chef Software Inc.
# Author:: Marc A. Paradise <marc.paradise@gmail.com>
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

require "chef/telemeter"
# Monkey patch the telemetry lib to respect our config.toml
# entry for telemetry.
require "chef_apply/telemeter/patch"
module ChefApply
  class Telemeter
    def self.timed_action_capture(action, &block)
      # Note: we do not directly capture hostname for privacy concerns, but
      # using a sha1 digest will allow us to anonymously see
      # unique hosts to derive number of hosts affected by a command
      target = action.target_host
      target_data = { platform: {}, hostname_sha1: nil, transport_type: nil }
      if target
        target_data[:platform][:name] = target.base_os # :windows, :linux, eventually :macos
        target_data[:platform][:version] = target.version
        target_data[:platform][:architecture] = target.architecture
        target_data[:hostname_sha1] = Digest::SHA1.hexdigest(target.hostname.downcase)
        target_data[:transport_type] = target.transport_type
      end
      Chef::Telemeter.timed_capture(:action, { action: action.name, target: target_data }, &block)
    end
  end
end
