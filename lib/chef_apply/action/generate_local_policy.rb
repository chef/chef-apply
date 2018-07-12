require "chef_apply/action/base"
require "chef_apply/error"
module ChefApply::Action
  # s/b GenerateTempCookbook?
  class GenerateLocalPolicy < Base
    def perform_action
      require "chef-dk/ui"
      require "chef-dk/policyfile_services/export_repo"
      require "chef-dk/policyfile_services/install"
      cookbook = config.delete :cookbook

      notify(:generating)
      installer = ChefDK::PolicyfileServices::Install.new(ui: ChefDK::UI.null(),
                                                          root_dir: cookbook.path)
      installer.run
      notify(:exporting)
      es = ChefDK::PolicyfileServices::ExportRepo.new(policyfile: cookbook.policyfile_lock_path,
                                                      root_dir: cookbook.path,
                                                      export_dir: cookbook.export_path,
                                                      archive: true, force: true)
      es.run
      notify(:success, es.archive_file_location)
    rescue ChefDK::PolicyfileInstallError => e
      raise PolicyfileInstallError.new(e)
    end
  end
  class PolicyfileInstallError < ChefApply::Error
    def initialize(cause_err); super("CHEFPOLICY001", cause_err.message); end
  end
end

