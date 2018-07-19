#
#p
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

require "chef_apply/config"
require "chef-config/config"
require "chef-config/logger"

require "chef_apply/cli/validation"
require "chef_apply/cli/options"
require "chef_apply/cli/help"
require "chef_apply/action/converge_target"
require "chef_apply/action/generate_local_policy"
require "chef_apply/action/generate_temp_cookbook"
require "chef_apply/action/install_chef"
require "chef_apply/error"
require "chef_apply/log"
require "chef_apply/target_host"
require "chef_apply/target_resolver"
require "chef_apply/telemeter"
require "chef_apply/ui/error_printer"
require "chef_apply/ui/terminal"

module ChefApply
  class CLI
    attr_reader :temp_cookbook, :archive_file_location, :target_hosts

    include Mixlib::CLI
    # Pulls in the CLI options and flags we have defined for this command.
    include ChefApply::CLI::Options
    # Argument validation and parsing behaviors
    include ChefApply::CLI::Validation
    # Help and version formatting
    include ChefApply::CLI::Help

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
        target_hosts = resolve_targets(cli_arguments.shift, parsed_options)
        render_cookbook_setup(cli_arguments)
        render_converge(target_hosts)
      end
    rescue OptionParser::InvalidOption => e # from parse_options
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

    def resolve_targets(host_spec, opts)
      @target_hosts = TargetResolver.new(host_spec,
                                         opts.delete(:protocol),
                                         opts).targets
    end

    def render_cookbook_setup(arguments)
      UI::Terminal.render_job(TS.generate_temp_cookbook.generating) do |reporter|
        @temp_cookbook = generate_temp_cookbook(arguments, reporter)
      end
      UI::Terminal.render_job(TS.generate_temp_cookbook.generating) do |reporter|
        @archive_file_location = generate_local_policy(reporter)
      end
    end

    def render_converge(target_hosts)
      jobs = target_hosts.map do |target_host|
        # Each block will run in its own thread during render.
        UI::Terminal::Job.new("[#{target_host.hostname}]", target_host) do |reporter|
          connect_target(target_host, reporter)
          install(target_host, reporter)
          converge(reporter, archive_file_location, target_host)
        end
      end
      header = TS.converge.header(target_hosts.length, temp_cookbook.descriptor, temp_cookbook.from)
      UI::Terminal.render_parallel_jobs(header, jobs)
      handle_job_failures(jobs)
    end

    # Accepts a target_host and establishes the connection to that host
    # while providing visual feedback via the Terminal API.
    def connect_target(target_host, reporter)
      connect_message = T.status.connecting(target_host.user)
      reporter.update(connect_message)
      do_connect(target_host, reporter)
    end

    def install(target_host, reporter)
      context = TS.install_chef
      reporter.update(context.verifying)
      installer = Action::InstallChef.instance_for_target(target_host, check_only: !parsed_options[:install])
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
          reporter.update(context.already_present(target_host.installed_chef_version))
        when :install_complete
          if installer.upgrading?
            message = context.upgrade_success(target_host.installed_chef_version, installer.version_to_install)
          else
            message = context.install_success(installer.version_to_install)
          end
          reporter.update(message)
        else
          handle_message(event, data, reporter)
        end
      end
    end

    # Runs a GenerateCookbook action based on recipe/resource infoprovided
    # and renders UI updates as the action reports back
    def generate_temp_cookbook(arguments, reporter)
      opts = if arguments.length == 1
               { recipe_spec: arguments.shift,
                 cookbook_repo_paths: parsed_options[:cookbook_repo_paths] }
             else
               { resource_type: arguments.shift,
                 resource_name: arguments.shift,
                 resource_properties: properties_from_string(arguments) }
             end
      action = ChefApply::Action::GenerateTempCookbook.from_options(opts)
      action.run do |event, data|
        case event
        when :generating
          reporter.update(TS.generate_temp_cookbook.generating)
        when :success
          reporter.success(TS.generate_temp_cookbook.success)
        else
          handle_message(event, data, reporter)
        end
      end
      action.generated_cookbook
    end

    # Runs the GenerateLocalPolicy action and renders UI updates
    # as the action reports back
    def generate_local_policy(reporter)
      action = Action::GenerateLocalPolicy.new(cookbook: temp_cookbook)
      action.run do |event, data|
        case event
        when :generating
          reporter.update(TS.generate_local_policy.generating)
        when :exporting
          reporter.update(TS.generate_local_policy.exporting)
        when :success
          reporter.success(TS.generate_local_policy.success)
        else
          handle_message(event, data, reporter)
        end
      end
      action.archive_file_location
    end

    # Runs the Converge action and renders UI updates as
    # the action reports back
    def converge(reporter, local_policy_path, target_host)
      reporter.update(TS.converge.converging(temp_cookbook.descriptor))
      converge_args = { local_policy_path: local_policy_path, target_host: target_host }
      converger = Action::ConvergeTarget.new(converge_args)
      converger.run do |event, data|
        case event
        when :success
          reporter.success(TS.converge.success(temp_cookbook.descriptor))
        when :converge_error
          reporter.error(TS.converge.failure(temp_cookbook.descriptor))
        when :creating_remote_policy
          reporter.update(TS.converge.creating_remote_policy)
        when :uploading_trusted_certs
          reporter.update(TS.converge.uploading_trusted_certs)
        when :running_chef
          reporter.update(TS.converge.converging(temp_cookbook.descriptor))
        when :reboot
          reporter.success(TS.converge.reboot)
        else
          handle_message(event, data, reporter)
        end
      end
    end

    def handle_perform_error(e)
      require "chef_apply/errors/standard_error_resolver"
      id = e.respond_to?(:id) ? e.id : e.class.to_s
      # TODO: This is currently sending host information for certain ssh errors
      #       post release we need to scrub this data. For now I'm redacting the
      #       whole message.
      # message = e.respond_to?(:message) ? e.message : e.to_s
      Telemeter.capture(:error, exception: { id: id, message: "redacted" })
      wrapper = ChefApply::Errors::StandardErrorResolver.wrap_exception(e)
      capture_exception_backtrace(wrapper)
      # Now that our housekeeping is done, allow user-facing handling/formatting
      # in `run` to execute by re-raising
      raise wrapper
    end

    # When running multiple jobs, exceptions are captured to the
    # job to avoid interrupting other jobs in process.  This function
    # collects them and raises directly (in the case of just one job in the list)
    # or raises a MultiJobFailure (when more than one job was being run)
    def handle_job_failures(jobs)
      failed_jobs = jobs.select { |j| !j.exception.nil? }
      return if failed_jobs.empty?
      if jobs.length == 1
        # Don't provide a bad UX by showing a 'one or more jobs has failed'
        # message when there was only one job.
        raise jobs.first.exception
      end
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

    def do_connect(target_host, reporter)
      target_host.connect!
      reporter.update(T.status.connected)
    rescue StandardError => e
      message = ChefApply::UI::ErrorPrinter.error_summary(e)
      reporter.error(message)
      raise
    end

  end
end
