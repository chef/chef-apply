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

require "chef_apply/telemeter"
require "chef_apply/error"

module ChefApply
  module Action
    # Derive new Actions from Action::Base
    # "target_host" is a TargetHost that the action is being applied to. May be nil
    #               if the action does not require a target.
    # "config" is hash containing any options that your command may need
    #
    # Implement perform_action to perform whatever action your class is intended to do.
    # Run time will be captured via telemetry and categorized under ":action" with the
    # unqualified class name of your Action.
    class Base
      attr_reader :target_host, :config

      def initialize(config = {})
        c = config.dup
        @target_host = c.delete :target_host
        # Remaining options are for child classes to make use of.
        @config = c
      end

      def run(&block)
        @notification_handler = block
        timed_action_capture(self) do
          begin
            perform_action
          rescue StandardError => e
            # Give the caller a chance to clean up - if an exception is
            # raised it'll otherwise get routed through the executing thread,
            # providing no means of feedback for the caller's current task.
            notify(:error, e)
            @error = e
          end
        end
        # Raise outside the block to ensure that the telemetry cpature completes
        raise @error unless @error.nil?
      end

      def name
        self.class.name.split("::").last
      end

      def perform_action
        raise NotImplemented
      end

      # TODO bootstrap 2019-02-07  - we'll need to find the right way to keep this in telemeter,
      # there are a bunch of exposed details here that the caller shouldn't care about.
      # I've moved it here temporarily to keep things running until we come back to this
      # for telemetry updates.
      def timed_action_capture(action, &block)
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
        timed_capture(:action, { action: action.name, target: target_data }, &block)
      end


      def notify(action, *args)
        return if @notification_handler.nil?
        ChefApply::Log.debug("[#{self.class.name}] Action: #{action}, Action Data: #{args}")
        @notification_handler.call(action, args) if @notification_handler
      end
    end
  end
end
