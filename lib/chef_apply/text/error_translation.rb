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

module ChefApply
  module Text
    class ErrorTranslation
      ATTRIBUTES = :decorations, :header, :footer, :stack, :log
      attr_reader :message, *ATTRIBUTES

      def initialize(id, params: [])
        # To get access to the metadata we'll go directly through the parsed yaml.
        # Accessing via R18n is unnecessarily complicated
        yml = Text._error_table

        # We'll still use our Text mechanism for the text itself so that
        # parameters, pluralization, etc will still work.
        # This will raise if the key doesn't exist.
        @message = Text.errors.send(id).text(*params)
        options = yml[:display_defaults]

        # Override any defaults if display metadata is given
        display_opts = yml[id.to_sym][:display]
        options = options.merge(display_opts) unless display_opts.nil?

        ATTRIBUTES.each do |attribute|
          instance_variable_set("@#{attribute}", options.delete(attribute))
        end

        if options.length > 0
          # Anything not in ATTRIBUTES is not supported. This will also catch
          # typos in attr names
          raise InvalidDisplayAttributes.new(id, options)
        end
      end

      def inspect
        inspection = "#{self}: "
        ATTRIBUTES.each do |attribute|
          inspection << "#{attribute}: #{send(attribute.to_s)}; "
        end
        inspection << "message: #{message.gsub("\n", "\\n")}"
        inspection
      end

      class InvalidDisplayAttributes < RuntimeError
        attr_reader :invalid_attrs
        def initialize(id, attrs)
          @invalid_attrs = attrs
          super("Invalid display attributes found for #{id}: #{attrs}")
        end
      end

    end
  end
end
