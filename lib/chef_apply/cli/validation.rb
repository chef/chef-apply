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
  module CLIValidation
    PROPERTY_MATCHER = /^([a-zA-Z0-9_]+)=(.+)$/
    CB_MATCHER = '[\w\-]+'

    # @doc Convert properties in the form k1=v1,k2=v2,kn=vn
    # into a hash, while validating correct form and format
    def properties_from_string(string_props)
      properties = {}
      string_props.each do |a|
        key, value = PROPERTY_MATCHER.match(a)[1..-1]
        value = transform_property_value(value)
        properties[key] = value
      end
      properties
    end
    #
    # Incoming properties are always read as a string from the command line.
    # Depending on their type we should transform them so we do not try and pass
    # a string to a resource property that expects an integer or boolean.
    def transform_property_value(value)
      case value
      when /^0/
        # when it is a zero leading value like "0777" don't turn
        # it into a number (this is a mode flag)
        value
      when /^\d+$/
        value.to_i
      when /(^(\d+)(\.)?(\d+)?)|(^(\d+)?(\.)(\d+))/
        value.to_f
      when /true/i
        true
      when /false/i
        false
      else
        value
      end
    end
    # The first param is always hostname. Then we either have
    # 1. A recipe designation
    # 2. A resource type and resource name followed by any properties
    def validate_params(params)
      if params.size < 2
        raise OptionValidationError.new("CHEFVAL002", self)
      end
      if params.size == 2
        # Trying to specify a recipe to run remotely, no properties
        cb = params[1]
        if File.exist?(cb)
          # This is a path specification, and we know it is valid
        elsif cb =~ /^#{CB_MATCHER}$/ || cb =~ /^#{CB_MATCHER}::#{CB_MATCHER}$/
          # They are specifying a cookbook as 'cb_name' or 'cb_name::recipe'
        else
          raise OptionValidationError.new("CHEFVAL004", self, cb)
        end
      elsif params.size >= 3
        properties = params[3..-1]
        properties.each do |property|
          unless property =~ PROPERTY_MATCHER
            raise OptionValidationError.new("CHEFVAL003", self, property)
          end
        end
      end
    end
  end
end
