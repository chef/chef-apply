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

require "chef_apply/action/base"
require "chef_apply/error"
module ChefApply::Action
  class GenerateLocalPolicy < Base
    attr_reader :archive_file_location
    def initialize(config)
      super(config)
      @cookbook = config.delete :cookbook
    end

    def perform_action
      notify(:generating)
      installer.run
      notify(:exporting)
      exporter.run
      @archive_file_location = exporter.archive_file_location
      notify(:success)
    rescue ChefDK::PolicyfileInstallError => e
      raise PolicyfileInstallError.new(e)
    end

    def exporter
      require "chef-dk/policyfile_services/export_repo"
      @exporter ||=
       ChefDK::PolicyfileServices::ExportRepo.new(policyfile: @cookbook.policyfile_lock_path,
                                                  root_dir: @cookbook.path,
                                                  export_dir: @cookbook.export_path,
                                                  archive: true, force: true)
    end

    def installer
      require "chef-dk/policyfile_services/install"
      require "chef-dk/ui"
      @installer ||=
        ChefDK::PolicyfileServices::Install.new(ui: ChefDK::UI.null(), root_dir: @cookbook.path)
    end

  end
  class PolicyfileInstallError < ChefApply::Error
    def initialize(cause_err); super("CHEFPOLICY001", cause_err.message); end
  end
end

