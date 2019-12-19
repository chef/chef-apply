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

  spec.files = %w{Rakefile LICENSE warning.txt} +
    Dir.glob("Gemfile*") + # Includes Gemfile and locks
    Dir.glob("*.gemspec") +
    Dir.glob("{bin,i18n,lib}/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "mixlib-cli" # Provides argument handling DSL for CLI applications
  spec.add_dependency "mixlib-config", ">= 3.0.5"  # shared chef configuration library that
                                                   # simplifies managing a configuration file
  spec.add_dependency "mixlib-log" # Basis for our traditional logger
  spec.add_dependency "mixlib-install" # URL resolver + install tool for chef products
  spec.add_dependency "r18n-desktop" # easy path to message text management via
                                     # localization gem...
  spec.add_dependency "toml-rb" # This isn't ideal because mixlib-config uses 'tomlrb'
                                # but that library does not support a dumper
  spec.add_dependency "train-core", "~> 3.0" # remote connection management over ssh, winrm
  spec.add_dependency "train-winrm" # winrm transports were pulled out into this plugin
  spec.add_dependency "pastel" # A color library
  spec.add_dependency "tty-spinner" # Pretty output for status updates in the CLI
  spec.add_dependency "chef", ">= 15.0" # Needed to load cookbooks
  spec.add_dependency "chef-cli", ">= 1.0.3 " # Policyfile
  spec.add_dependency "chef-telemetry", "<= 1.0.3" # telemetry, updates required to pull in later versions
  spec.add_dependency "license-acceptance", "~> 1.0", ">= 1.0.11"

  spec.add_development_dependency "bundler"

  spec.post_install_message = File.read(File.expand_path("../warning.txt", __FILE__))
end
