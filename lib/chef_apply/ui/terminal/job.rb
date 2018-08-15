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

module ChefApply
  module UI
    class Terminal
      class Job
        attr_reader :proc, :prefix, :target_host, :exception
        def initialize(prefix, target_host, &block)
          @proc = block
          @prefix = prefix
          @target_host = target_host
          @error = nil
        end

        def run(reporter)
          @proc.call(reporter)
        rescue => e
          reporter.error(e.to_s)
          @exception = e
        end
      end
    end
  end
end
