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

require "chef_apply/action/base"
require "chef_apply/temp_cookbook"
require "chef_apply/error"

module ChefApply::Action
  class GenerateTempCookbook < Base
    attr_reader :generated_cookbook

    def self.from_options(opts)
      if opts.key?(:recipe_spec)
        GenerateCookbookFromRecipe.new(opts)
      elsif opts.key?(:resource_name) &&
          opts.key?(:resource_type) &&
          opts.key?(:resource_properties)
        GenerateCookbookFromResource.new(opts)
      else
        raise MissingOptions.new(opts)
      end
    end

    def initialize(options)
      super(options)
      @generated_cookbook ||= ChefApply::TempCookbook.new
    end

    def perform_action
      notify(:generating)
      generate
      notify(:success)
    end

    def generate
      raise NotImplemented
    end
  end

  class GenerateCookbookFromRecipe < GenerateTempCookbook
    def generate
      recipe_specifier = config.delete :recipe_spec
      repo_paths = config.delete :cookbook_repo_paths
      ChefApply::Log.debug("Beginning to look for recipe specified as #{recipe_specifier}")
      if File.file?(recipe_specifier)
        ChefApply::Log.debug("#{recipe_specifier} is a valid path to a recipe")
        recipe_path = recipe_specifier
      else
        require "chef_apply/recipe_lookup"
        rl = ChefApply::RecipeLookup.new(repo_paths)
        cookbook_path_or_name, optional_recipe_name = rl.split(recipe_specifier)
        cookbook = rl.load_cookbook(cookbook_path_or_name)
        recipe_path = rl.find_recipe(cookbook, optional_recipe_name)
      end
      generated_cookbook.from_existing_recipe(recipe_path)
    end
  end

  class GenerateCookbookFromResource < GenerateTempCookbook
    def generate
      type = config.delete :resource_type
      name = config.delete :resource_name
      props = config.delete :resource_properties
      ChefApply::Log.debug("Generating cookbook for ad-hoc resource #{type}[#{name}]")
      generated_cookbook.from_resource(type, name, props)
    end
  end

  class MissingOptions < ChefApply::APIError
    def initialize(*args); super("CHEFAPI001", *args); end
  end
end
