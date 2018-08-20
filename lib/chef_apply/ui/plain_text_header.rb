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
require "thread"
require "chef_apply/ui/plain_text_element"

module ChefApply
  module UI
    class PlainTextHeader
      def initialize(format, opts)
        @format = format
        @output = opts[:output]
        @children = {}
        @threads = []
      end

      def register(child_format, child_opts, &block)
        child_opts[:output] = @output
        child = PlainTextElement.new(child_format, child_opts)
        @children[child] = block
      end

      def auto_spin
        msg = @format.gsub(/:spinner/, " HEADER ")
        @output.puts(msg)
        @children.each do |child, block|
          @threads << Thread.new { block.call(child) }
        end
        @threads.each { |thr| thr.join }
      end
    end
  end
end
