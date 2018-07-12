
require "chef_apply/action/base"
require "chef_apply/recipe_lookup"
require "chef_apply/temp_cookbook"

module ChefApply::Action
  class GenerateCookbook < Base
    attr_reader :generated_cookbook

    def perform_action
      @generated_cookbook = ChefApply::TempCookbook.new
      notify(:generating)
      generate
      notify(:success, @generated_cookbook)
    end
  end

  class GenerateCookbookFromRecipe < GenerateCookbook
    def generate
      recipe_specifier = config.delete :recipe_spec
      ChefApply::Log.debug("Beginning to look for recipe specified as #{recipe_specifier}")
      if File.file?(recipe_specifier)
        ChefApply::Log.debug("#{recipe_specifier} is a valid path to a recipe")
        recipe_path = recipe_specifier
      else
        require "chef_apply/recipe_lookup"
        rl = RecipeLookup.new(parsed_options[:cookbook_repo_paths])
        cookbook_path_or_name, optional_recipe_name = rl.split(recipe_specifier)
        cookbook = rl.load_cookbook(cookbook_path_or_name)
        recipe_path = rl.find_recipe(cookbook, optional_recipe_name)
      end
      generated_cookbook.from_existing_recipe(recipe_path)
    end
  end

  class GenerateCookbookFromResource < GenerateCookbook
    def generate
      type = config.delete :resource_type
      name = config.delete :resource_name
      props = config.delete :resource_properties
      ChefApply::Log.debug("Generating cookbook for ad-hoc resource #{type}[#{name}]")
      generated_cookbook.from_resource(type, name, props)
    end
  end
end
