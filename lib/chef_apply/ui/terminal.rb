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
require "tty-cursor"
require "chef_apply/status_reporter"
require "chef_apply/config"
require "chef_apply/log"
require "chef_apply/ui/plain_text_element"
require "chef_apply/ui/plain_text_header"

module ChefApply
  module UI
    class Terminal
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
          indent_style = { top: "",
                           middle: TTY::Spinner::Multi::DEFAULT_INSET[:middle],
                           bottom: TTY::Spinner::Multi::DEFAULT_INSET[:bottom] }
          # @option options [Hash] :style
          #   keys :top :middle and :bottom can contain Strings that are used to
          #   indent the spinners. Ignored if message is blank
          multispinner = get_multispinner.new("[:spinner] #{header}",
                                              output: @location,
                                              hide_cursor: true,
                                              style: indent_style)
          jobs.each do |job|
            multispinner.register(spinner_prefix(job.prefix), hide_cursor: true) do |spinner|
              reporter = StatusReporter.new(spinner, prefix: job.prefix, key: :status)
              job.run(reporter)
            end
          end
          multispinner.auto_spin
        ensure
          # Spinners hide the cursor for better appearance, so we need to make sure
          # we always bring it back
          show_cursor
        end

        def render_job(initial_msg, job)
          # TODO why do we have to pass prefix to both the spinner and the reporter?
          spinner = get_spinner.new(spinner_prefix(job.prefix), output: @location, hide_cursor: true)
          reporter = StatusReporter.new(spinner, prefix: job.prefix, key: :status)
          reporter.update(initial_msg)
          spinner.auto_spin
          job.run(reporter)
        end

        def spinner_prefix(prefix)
          spinner_msg = "[:spinner] "
          spinner_msg += ":prefix " unless prefix.empty?
          spinner_msg + ":status"
        end

        def get_multispinner
          ChefApply::Config.dev.spinner ? TTY::Spinner::Multi : PlainTextHeader
        end

        def get_spinner
          ChefApply::Config.dev.spinner ? TTY::Spinner : PlainTextElement
        end

        def show_cursor
          TTY::Cursor.show()
        end
      end
    end
  end
end
