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

require "tty-spinner"
require "chef_apply/status_reporter"
require "chef_apply/config"
require "chef_apply/log"
require "chef_apply/ui/plain_text_element"

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

      class << self
        # To support matching in test
        attr_accessor :location

        def init(location)
          @location = location
        end

        def write(msg)
          @location.write(msg)
        end

        def output(msg)
          @location.puts msg
        end

        def render_parallel_jobs(header, jobs)

      # Do not indent the topmost 'parent' spinner, but do indent child spinners
          indent_style = { top: '',
                           middle: TTY::Spinner::Multi::DEFAULT_INSET[:middle],
                           bottom: TTY::Spinner::Multi::DEFAULT_INSET[:bottom] }
      # @option options [Hash] :style
      #   keys :top :middle and :bottom can contain Strings that are used to
      #   indent the spinners. Ignored if message is blank
          multispinner = TTY::Spinner::Multi.new("[:spinner] #{header}", output: @location, hide_cursor: true, style: indent_style)
          jobs.each do |a|
            multispinner.register(spinner_prefix(a.prefix), hide_cursor: true) do |spinner|
              reporter = StatusReporter.new(spinner, prefix: a.prefix, key: :status)
              a.run(reporter)
            end
          end
          multispinner.auto_spin
        end

        # TODO update this to accept a job instead of a block, for consistency of usage
        #      between render_job and render_parallel
        def render_job(msg, prefix: "", &block)
          klass = ChefApply::UI.const_get(ChefApply::Config.dev.spinner)
          spinner = klass.new(spinner_prefix(prefix), output: @location, hide_cursor: true)
          reporter = StatusReporter.new(spinner, prefix: prefix, key: :status)
          reporter.update(msg)
          spinner.run { yield(reporter) }
        end

        def spinner_prefix(prefix)
          spinner_msg = "[:spinner] "
          spinner_msg += ":prefix " unless prefix.empty?
          spinner_msg + ":status"
        end
      end
    end
  end
end
