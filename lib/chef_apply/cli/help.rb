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
  module CLIHelp
    T = ChefApply::Text.cli
    def show_help
      UI::Terminal.output format_help
    end

    def format_help
      help_text = banner.clone # This prevents us appending to the banner text
      help_text << "\n"
      help_text << format_flags
    end

    def format_flags
      flag_text = "FLAGS:\n"
      justify_length = 0
      options.each_value do |spec|
        justify_length = [justify_length, spec[:long].length + 4].max
      end
      options.sort.to_h.each_value do |flag_spec|
        short = flag_spec[:short] || "  "
        short = short[0, 2] # We only want the flag portion, not the capture portion (if present)
        if short == "  "
          short = "    "
        else
          short = "#{short}, "
        end
        flags = "#{short}#{flag_spec[:long]}"
        flag_text << "    #{flags.ljust(justify_length)}    "
        ml_padding = " " * (justify_length + 8)
        first = true
        flag_spec[:description].split("\n").each do |d|
          flag_text << ml_padding unless first
          first = false
          flag_text << "#{d}\n"
        end
      end
      flag_text
    end

    def usage
      T.usage
    end

    def show_version
      require "chef_apply/version"
      UI::Terminal.output T.version.show(ChefApply::VERSION)
    end
  end
end

