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
require "mixlib/cli"
require "chef/log"
require "chef-config/config"
require "chef-config/logger"

require "chef_apply/cli/help"
require "chef_apply/cli/options"
require "chef_apply/cli/validation"

require "chef_apply/action/converge_target"
require "chef_apply/action/install_chef"
require "chef_apply/config"
require "chef_apply/error"
require "chef_apply/log"
require "chef_apply/recipe_lookup"
require "chef_apply/target_host"
require "chef_apply/target_resolver"
require "chef_apply/telemeter"
require "chef_apply/telemeter/sender"
require "chef_apply/temp_cookbook"
require "chef_apply/ui/error_printer"
require "chef_apply/ui/terminal"
require "chef_apply/version"

module ChefApply
  class CLI
    include Mixlib::CLI
    include ChefApply::CLI::Options
    include ChefApply::CLI::Help
    include ChefApply::CLI::Validation

    RC_OK = 0
    RC_COMMAND_FAILED = 1
    RC_UNHANDLED_ERROR = 32
    RC_ERROR_HANDLING_FAILED = 64

    def initialize(argv)
      @argv = argv.clone
      @rc = RC_OK
      super()
    end

    def run
      # Perform a timing and capture of the run. Individual methods and actions may perform
      # nested Telemeter.timed_*_capture or Telemeter.capture calls in their operation, and
      # they will be captured in the same telemetry session.
      # NOTE: We're not currently sending arguments to telemetry because we have not implemented
      #       pre-parsing of arguments to eliminate potentially sensitive data such as
      #       passwords in host name, or in ad-hoc converge properties.
      Telemeter.timed_run_capture([:redacted]) do
        begin
          perform_run
        rescue Exception => e
          @rc = handle_run_error(e)
        end
      end
    rescue => e
      @rc = handle_run_error(e)
    ensure
      Telemeter.commit
      exit @rc
    end

    def handle_run_error(e)
      case e
      when nil
        RC_OK
      when WrappedError
        UI::ErrorPrinter.show_error(e)
        RC_COMMAND_FAILED
      when SystemExit
        e.status
      when Exception
        UI::ErrorPrinter.dump_unexpected_error(e)
        RC_ERROR_HANDLING_FAILED
      else
        UI::ErrorPrinter.dump_unexpected_error(e)
        RC_UNHANDLED_ERROR
      end
    end

    def perform_run
      parse_options(@argv)
      if @argv.empty? || parsed_options[:help]
        show_help
      elsif parsed_options[:version]
        show_version
      else
        validate_params(cli_arguments)
        configure_chef
        target_hosts = TargetResolver.new(cli_arguments.shift,
                                          parsed_options.delete(:protocol),
                                          parsed_options).targets
        temp_cookbook, initial_status_msg = generate_temp_cookbook(cli_arguments)
        local_policy_path = nil
        UI::Terminal.render_job(TS.generate_policyfile.generating) do |reporter|
          local_policy_path = create_local_policy(temp_cookbook)
          reporter.success(TS.generate_policyfile.success)
        end
        if target_hosts.length == 1
          # Note: UX discussed determined that when running with a single target,
          #       we'll use multiple lines to display status for the target.
          run_single_target(initial_status_msg, target_hosts[0], local_policy_path)
        else
          @multi_target = true
          # Multi-target will use one line per target.
          run_multi_target(initial_status_msg, target_hosts, local_policy_path)
        end
      end
    rescue OptionParser::InvalidOption => e
      # Using nil here is a bit gross but it prevents usage from printing.
      ove = OptionValidationError.new("CHEFVAL010", nil,
                                      e.message.split(":")[1].strip, # only want the flag
                                      format_flags.lines[1..-1].join # remove 'FLAGS:' header
                                     )
      handle_perform_error(ove)
    rescue => e
      handle_perform_error(e)
    ensure
      temp_cookbook.delete unless temp_cookbook.nil?
    end

    # Accepts a target_host and establishes the connection to that host
    # while providing visual feedback via the Terminal API.
    def connect_target(target_host, reporter = nil)
      connect_message = T.status.connecting(target_host.user)
      if reporter.nil?
        UI::Terminal.render_job(connect_message, prefix: "[#{target_host.config[:host]}]") do |rep|
          do_connect(target_host, rep, :success)
        end
      else
        reporter.update(connect_message)
        do_connect(target_host, reporter, :update)
      end
      target_host
    end

    def run_single_target(initial_status_msg, target_host, local_policy_path)
      connect_target(target_host)
      prefix = "[#{target_host.hostname}]"
      UI::Terminal.render_job(TS.install_chef.verifying, prefix: prefix) do |reporter|
        install(target_host, reporter)
      end
      UI::Terminal.render_job(initial_status_msg, prefix: "[#{target_host.hostname}]") do |reporter|
        converge(reporter, local_policy_path, target_host)
      end
    end

    def run_multi_target(initial_status_msg, target_hosts, local_policy_path)
      # Our multi-host UX does not show a line item per action,
      # but rather a line-item per connection.
      jobs = target_hosts.map do |target_host|
        # This block will run in its own thread during render.
        UI::Terminal::Job.new("[#{target_host.hostname}]", target_host) do |reporter|
          connect_target(target_host, reporter)
          reporter.update(TS.install_chef.verifying)
          install(target_host, reporter)
          reporter.update(initial_status_msg)
          converge(reporter, local_policy_path, target_host)
        end
      end
      UI::Terminal.render_parallel_jobs(TS.converge.multi_header, jobs)
      handle_job_failures(jobs)
    end

    # Now that we are leveraging Chef locally we want to perform some initial setup of it
    def configure_chef
      ChefConfig.logger = ChefApply::Log
      # Setting the config isn't enough, we need to ensure the logger is initialized
      # or automatic initialization will still go to stdout
      Chef::Log.init(ChefApply::Log)
      Chef::Log.level = ChefApply::Log.level
    end

    # The user will either specify a single resource on the command line, or a recipe.
    # We need to parse out those two different situations
    def generate_temp_cookbook(cli_arguments)
      temp_cookbook = TempCookbook.new
      if recipe_strategy?(cli_arguments)
        recipe_specifier = cli_arguments.shift
        ChefApply::Log.debug("Beginning to look for recipe specified as #{recipe_specifier}")
        if File.file?(recipe_specifier)
          ChefApply::Log.debug("#{recipe_specifier} is a valid path to a recipe")
          recipe_path = recipe_specifier
        else
          rl = RecipeLookup.new(parsed_options[:cookbook_repo_paths])
          cookbook_path_or_name, optional_recipe_name = rl.split(recipe_specifier)
          cookbook = rl.load_cookbook(cookbook_path_or_name)
          recipe_path = rl.find_recipe(cookbook, optional_recipe_name)
        end
        temp_cookbook.from_existing_recipe(recipe_path)
        initial_status_msg = TS.converge.converging_recipe(recipe_specifier)
      else
        resource_type = cli_arguments.shift
        resource_name = cli_arguments.shift
        temp_cookbook.from_resource(resource_type, resource_name, properties_from_string(cli_arguments))
        full_rs_name = "#{resource_type}[#{resource_name}]"
        ChefApply::Log.debug("Converging resource #{full_rs_name} on target")
        initial_status_msg = TS.converge.converging_resource(full_rs_name)
      end

      [temp_cookbook, initial_status_msg]
    end

    def recipe_strategy?(cli_arguments)
      cli_arguments.size == 1
    end

    def create_local_policy(local_cookbook)
      require "chef-dk/ui"
      require "chef-dk/policyfile_services/export_repo"
      require "chef-dk/policyfile_services/install"
      policyfile_installer = ChefDK::PolicyfileServices::Install.new(
        ui: ChefDK::UI.null(),
        root_dir: local_cookbook.path
      )
      begin
        policyfile_installer.run
      rescue ChefDK::PolicyfileInstallError => e
        raise PolicyfileInstallError.new(e)
      end
      lock_path = File.join(local_cookbook.path, "Policyfile.lock.json")
      es = ChefDK::PolicyfileServices::ExportRepo.new(policyfile: lock_path,
                                                      root_dir: local_cookbook.path,
                                                      export_dir: File.join(local_cookbook.path, "export"),
                                                      archive: true,
                                                      force: true)
      es.run
      es.archive_file_location
    end

    # Runs the InstallChef action and renders UI updates as
    # the action reports back
    def install(target_host, reporter)
      installer = Action::InstallChef.instance_for_target(target_host, check_only: !parsed_options[:install])
      context = TS.install_chef
      installer.run do |event, data|
        case event
        when :installing
          if installer.upgrading?
            message = context.upgrading(target_host.installed_chef_version, installer.version_to_install)
          else
            message = context.installing(installer.version_to_install)
          end
          reporter.update(message)
        when :uploading
          reporter.update(context.uploading)
        when :downloading
          reporter.update(context.downloading)
        when :already_installed
          meth = @multi_target ? :update : :success
          reporter.send(meth, context.already_present(target_host.installed_chef_version))
        when :install_complete
          meth = @multi_target ? :update : :success
          if installer.upgrading?
            message = context.upgrade_success(target_host.installed_chef_version, installer.version_to_install)
          else
            message = context.install_success(installer.version_to_install)
          end
          reporter.send(meth, message)
        else
          handle_message(event, data, reporter)
        end
      end
    end

    # Runs the Converge action and renders UI updates as
    # the action reports back
    def converge(reporter, local_policy_path, target_host)
      converge_args = { local_policy_path: local_policy_path, target_host: target_host }
      converger = Action::ConvergeTarget.new(converge_args)
      converger.run do |event, data|
        case event
        when :success
          reporter.success(TS.converge.success)
        when :converge_error
          reporter.error(TS.converge.failure)
        when :creating_remote_policy
          reporter.update(TS.converge.creating_remote_policy)
        when :uploading_trusted_certs
          reporter.update(TS.converge.uploading_trusted_certs)
        when :running_chef
          reporter.update(TS.converge.running_chef)
        when :reboot
          reporter.success(TS.converge.reboot)
        else
          handle_message(event, data, reporter)
        end
      end
    end

    def handle_perform_error(e)
      id = e.respond_to?(:id) ? e.id : e.class.to_s
      # TODO: This is currently sending host information for certain ssh errors
      #       post release we need to scrub this data. For now I'm redacting the
      #       whole message.
      # message = e.respond_to?(:message) ? e.message : e.to_s
      Telemeter.capture(:error, exception: { id: id, message: "redacted" })
      wrapper = ChefApply::StandardErrorResolver.wrap_exception(e)
      capture_exception_backtrace(wrapper)
      # Now that our housekeeping is done, allow user-facing handling/formatting
      # in `run` to execute by re-raising
      raise wrapper
    end

    # When running multiple jobs, exceptions are captured to the
    # job to avoid interrupting other jobs in process.  This function
    # collects them and raises a MultiJobFailure if failure has occurred;
    # we do *not* differentiate between one failed jobs and multiple failed jobs
    # - if you're in the 'multi-job' path (eg, multiple targets) we handle
    # all errors the same to provide a consistent UX when running with mulitiple targets.
    def handle_job_failures(jobs)
      failed_jobs = jobs.select { |j| !j.exception.nil? }
      return if failed_jobs.empty?
      raise ChefApply::MultiJobFailure.new(failed_jobs)
    end

    # A handler for common action messages
    def handle_message(message, data, reporter)
      if message == :error # data[0] = exception
        # Mark the current task as failed with whatever data is available to us
        reporter.error(ChefApply::UI::ErrorPrinter.error_summary(data[0]))
      end
    end

    def capture_exception_backtrace(e)
      UI::ErrorPrinter.write_backtrace(e, @argv)
    end

    def do_connect(target_host, reporter, update_method)
      target_host.connect!
      reporter.send(update_method, T.status.connected)
    rescue StandardError => e
      message = ChefApply::UI::ErrorPrinter.error_summary(e)
      reporter.error(message)
      raise
    end

    class OptionValidationError < ChefApply::ErrorNoLogs
      attr_reader :command
      def initialize(id, calling_command, *args)
        super(id, *args)
        # TODO - this is getting cumbersome - move them to constructor options hash in base
        @decorate = false
        @command = calling_command
      end
    end

    class PolicyfileInstallError < ChefApply::Error
      def initialize(cause_err); super("CHEFPOLICY001", cause_err.message); end
    end
  end
end
