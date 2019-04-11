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

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "chef_apply/version"

Gem::Specification.new do |spec|
  spec.name          = "chef-apply"
  spec.version       = ChefApply::VERSION
  spec.authors       = ["Chef Software, Inc"]
  spec.email         = ["workstation@chef.io"]

  spec.summary       = "The ad-hoc execution tool for the Chef ecosystem."
  spec.description   = "Ad-hoc management of individual nodes and devices."
  spec.homepage      = "https://github.com/chef/chef-apply"
  spec.license       = "Apache-2.0"
  spec.required_ruby_version = ">= 2.5.0"

  spec.files = %w{Rakefile LICENSE README.md warning.txt} +
    Dir.glob("Gemfile*") + # Includes Gemfile and locks
    Dir.glob("*.gemspec") +
    Dir.glob("{bin,i18n,lib,spec}/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "mixlib-cli"    # Provides argument handling DSL for CLI applications
  spec.add_dependency "mixlib-config" # shared chef configuration library that
                                      # simplifies managing a configuration file
  spec.add_dependency "toml-rb" # This isn't ideal because mixlib-config uses 'tomlrb'
                                # but that library does not support a dumper
  spec.add_dependency "chef", ">= 14.10" # Cookbook and recipe support
  spec.add_dependency "chef-core" # remote host connectity, logging, i18n
                                  # CLI UX - handles output, formatting, etc.
  spec.add_dependency "chef-core-actions" # actions that can be used to construct UX flows

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "pry-stack_explorer"
  spec.add_development_dependency "rspec_junit_formatter"
  spec.add_development_dependency "chefstyle"

  spec.post_install_message = File.read(File.expand_path("../warning.txt", __FILE__))
end
