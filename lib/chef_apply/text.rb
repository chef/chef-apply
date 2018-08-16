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

require "r18n-desktop"
require "chef_apply/text/text_wrapper"
require "chef_apply/text/error_translation"

# A very thin wrapper around R18n, the idea being that we're likely to replace r18n
# down the road and don't want to have to change all of our commands.
module ChefApply
  module Text
    def self._error_table
      # Though ther may be several translations, en.yml will be the only one with
      # error metadata.
      path = File.join(_translation_path, "errors", "en.yml")
      raw_yaml = File.read(path)
      @error_table ||= YAML.load(raw_yaml, _translation_path, symbolize_names: true)[:errors]
    end

    def self._translation_path
      @translation_path ||= File.join(File.dirname(__FILE__), "..", "..", "i18n")
    end

    def self.load
      R18n.from_env(Text._translation_path)
      R18n.extension_places << File.join(Text._translation_path, "errors")
      t = R18n.get.t
      t.translation_keys.each do |k|
        k = k.to_sym
        define_singleton_method k do |*args|
          TextWrapper.new(t.send(k, *args))
        end
      end
    end

    # Load on class load to ensure our text accessor methods are available from the start.
    load
  end
end
