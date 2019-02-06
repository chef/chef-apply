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
        Telemeter.timed_action_capture(self) do
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

      def notify(action, *args)
        return if @notification_handler.nil?
        ChefApply::Log.debug("[#{self.class.name}] Action: #{action}, Action Data: #{args}")
        @notification_handler.call(action, args) if @notification_handler
      end
    end
  end
end
