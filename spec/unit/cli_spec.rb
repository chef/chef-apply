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

require "spec_helper"
require "chef_apply/cli"
require "chef_apply/error"
require "chef_apply/telemeter"
require "chef_apply/telemeter/sender"
require "chef_apply/ui/terminal"
require "chef_apply/action/generate_temp_cookbook"

require "chef-cli/ui"

RSpec.describe ChefApply::CLI do
  subject { ChefApply::CLI.new(argv) }
  let(:argv) { [] }
  # TODO why isn't this mocked?
  let(:telemetry) { ChefApply::Telemeter.instance }

  before do
    # Avoid messy object dumps in failures because subject is an object instance
    allow(subject).to receive(:inspect).and_return("The subject instance")
  end

  describe "run" do
    before do
      # Catch all of the calls by default, to prevent the various
      # startup actions from actually occuring on the workstatoin.
      allow(telemetry).to receive(:timed_run_capture).and_yield
      allow(subject).to receive(:perform_run)
      allow(telemetry).to receive(:commit)
    end

    it "captures and commits the run to telemetry" do
      expect(telemetry).to receive(:timed_run_capture)
      expect(telemetry).to receive(:commit)
      expect { subject.run }.to exit_with_code(0)
    end

    it "calls perform_run" do
      expect(subject).to receive(:perform_run)
      expect { subject.run }.to exit_with_code(0)
    end

    context "perform_run raises WrappedError" do
      let(:e) { ChefApply::WrappedError.new(RuntimeError.new("Test"), "host") }

      it "prints the error and exits" do
        expect(subject).to receive(:perform_run).and_raise(e)
        expect(ChefApply::UI::ErrorPrinter).to receive(:show_error).with(e)
        expect { subject.run }.to exit_with_code(1)
      end
    end

    context "perform_run raises SystemExit" do
      it "exits with same exit code" do
        expect(subject).to receive(:perform_run).and_raise(SystemExit.new(99))
        expect { subject.run }.to exit_with_code(99)
      end
    end

    context "perform_run raises any other exception" do
      let(:e) { Exception.new("test") }

      it "exits with code 64" do
        expect(subject).to receive(:perform_run).and_raise(e)
        expect(ChefApply::UI::ErrorPrinter).to receive(:dump_unexpected_error).with(e)
        expect { subject.run }.to exit_with_code(64)
      end
    end
  end

  describe "#perform_run" do
    it "parses options" do
      expect(subject).to receive(:parse_options).with(argv)
      subject.perform_run
    end

    context "when any error is raised" do
      let(:e) { RuntimeError.new("Test") }
      before do
        allow(subject).to receive(:parse_options).and_raise(e)
      end

      it "calls handle_perform_error" do
        expect(subject).to receive(:handle_perform_error).with(e)
        subject.perform_run
      end
    end

    context "when argv is empty" do
      let(:argv) { [] }
      it "shows the help text" do
        expect(subject).to receive(:show_help)
        subject.perform_run
      end
    end

    context "when help flags are passed" do
      %w{-h --help}.each do |flag|
        context flag do
          let(:argv) { [flag] }
          it "shows the help text" do
            expect(subject).to receive(:show_help)
            subject.perform_run
          end
        end
      end

      %w{-v --version}.each do |flag|
        context flag do
          let(:argv) { [flag] }
          it "shows the help text" do
            expect(subject).to receive(:show_version)
            subject.perform_run
          end
        end
      end
    end

    context "when arguments are provided" do
      let(:argv) { ["hostname", "resourcetype", "resourcename", "someproperty=true"] }
      let(:target_hosts) { [double("TargetHost")] }
      before do
        # parse_options sets `cli_argument` - because we stub out parse_options,
        # later calls that rely on cli_arguments will fail without this.
        allow(subject).to receive(:cli_arguments).and_return argv
      end

      context "and they are valid" do
        it "creates the cookbook locally and converges it" do
          expect(subject).to receive(:parse_options)
          expect(subject).to receive(:check_license_acceptance)
          expect(subject).to receive(:validate_params)
          expect(subject).to receive(:resolve_targets).and_return target_hosts
          expect(subject).to receive(:render_cookbook_setup)
          expect(subject).to receive(:render_converge).with(target_hosts)
          subject.perform_run
        end
      end
    end
  end

  describe "#check_license_acceptance" do
    let(:acceptance_value) { "accept-no-persist" }
    let(:acceptor) { instance_double(LicenseAcceptance::Acceptor) }

    before do
      ChefApply::Config.reset
      expect(LicenseAcceptance::Acceptor).to receive(:new).with(provided: ChefApply::Config.chef.chef_license).and_return(acceptor)
    end

    it "sets the config value to the acceptance value" do
      expect(ChefApply::Config.chef.chef_license).to eq(nil)
      expect(acceptor).to receive(:check_and_persist).with("infra-client", "latest")
      expect(acceptor).to receive(:acceptance_value).and_return(acceptance_value)
      subject.check_license_acceptance
      expect(ChefApply::Config.chef.chef_license).to eq(acceptance_value)
    end

    describe "when the user does not accept the license" do
      it "raises a LicenseCheckFailed error" do
        expect(ChefApply::Config.chef.chef_license).to eq(nil)
        expect(acceptor).to receive(:check_and_persist).with("infra-client", "latest").and_raise(LicenseAcceptance::LicenseNotAcceptedError.new(nil, []))
        expect { subject.check_license_acceptance }.to raise_error(ChefApply::LicenseCheckFailed)
        expect(ChefApply::Config.chef.chef_license).to eq(nil)
      end
    end
  end

  describe "#connect_target" do
    let(:host) { double("TargetHost", config: {}, user: "root" ) }
    let(:reporter) { double("reporter", update: :ok, success: :ok) }
    it "invokes do_connect with correct options" do
      expect(subject).to receive(:do_connect)
        .with(host, reporter)
      subject.connect_target(host, reporter)
    end
  end

  describe "#generate_temp_cookbook" do
    before do
      allow(subject).to receive(:parsed_options).and_return({ cookbook_repo_paths: "/tmp" })
    end
    let(:temp_cookbook) { double("TempCookbook") }
    let(:action) { double("generator", generated_cookbook: temp_cookbook) }

    context "when a resource is provided" do
      it "gets an action via GenerateTemporaryCookbook.from_options and executes it " do
        expect(ChefApply::Action::GenerateTempCookbook)
          .to receive(:from_options)
          .with(resource_type: "user",
                resource_name: "test", resource_properties: {})
          .and_return(action)
        expect(action).to receive(:run)
        expect(subject.generate_temp_cookbook(%w{user test}, nil)).to eq temp_cookbook
      end
    end

    context "when a recipe specifier is provided" do

      it "gets an action via GenerateTemporaryCookbook.from_options and executes it" do
        expect(ChefApply::Action::GenerateTempCookbook)
          .to receive(:from_options)
          .with(recipe_spec: "mycookbook::default", cookbook_repo_paths: "/tmp")
          .and_return(action)
        expect(action).to receive(:run)
        subject.generate_temp_cookbook(["mycookbook::default"], nil)
      end
    end

    context "when generator posts event:" do
      let(:reporter) { double("reporter") }
      before do
        expect(ChefApply::Action::GenerateTempCookbook)
          .to receive(:from_options)
          .and_return(action)
        allow(action).to receive(:run) { |&block| block.call(event, event_args) }
      end

      context ":generating" do
        let(:event) { :generating }
        let(:event_args) { nil }
        it "updates message text via reporter" do
          expected_text = ChefApply::CLI::TS.generate_temp_cookbook.generating
          expect(reporter).to receive(:update).with(expected_text)
          subject.generate_temp_cookbook(%w{user jimbo}, reporter)
        end
      end

      context ":success" do
        let(:event) { :success }
        let(:event_args) { [ temp_cookbook ] }
        it "indicates success via reporter and returns the cookbook" do
          expected_text = ChefApply::CLI::TS.generate_temp_cookbook.success
          expect(reporter).to receive(:success).with(expected_text)
          expect(subject.generate_temp_cookbook(%w{user jimbo}, reporter))
            .to eq temp_cookbook
        end
      end
    end
  end

  describe "#generate_local_policy" do
    let(:reporter) { double("reporter") }
    let(:action) { double("GenerateLocalPolicy") }
    let(:temp_cookbook) { instance_double("TempCookbook") }
    let(:archive_file_location) { "/temp/archive.gz" }

    before do
      allow(subject).to receive(:temp_cookbook).and_return temp_cookbook
      allow(action).to receive(:archive_file_location).and_return archive_file_location
    end
    it "creates a GenerateLocalPolicy action and executes it" do
      expect(ChefApply::Action::GenerateLocalPolicy).to receive(:new)
        .with(cookbook: temp_cookbook)
        .and_return(action)
      expect(action).to receive(:run)
      subject.generate_local_policy(reporter)
    end

    context "when generator posts an event:" do
      before do
        expect(ChefApply::Action::GenerateLocalPolicy).to receive(:new)
          .with(cookbook: temp_cookbook)
          .and_return(action)
        allow(action).to receive(:run) { |&block| block.call(event, event_args) }
      end

      context ":generating" do
        let(:event) { :generating }
        let(:event_args) { nil }
        let(:expected_msg) { ChefApply::CLI::TS.generate_local_policy.generating }
        it "updates message text correctly via reporter" do
          expect(reporter).to receive(:update).with(expected_msg)
          subject.generate_local_policy(reporter)
        end

      end

      context ":exporting" do
        let(:event) { :exporting }
        let(:event_args) { nil }
        let(:expected_msg) { ChefApply::CLI::TS.generate_local_policy.exporting }
        it "updates message text correctly via reporter" do
          expect(reporter).to receive(:update).with(expected_msg)
          subject.generate_local_policy(reporter)
        end
      end

      context ":success" do
        let(:event) { :success }
        let(:expected_msg) { ChefApply::CLI::TS.generate_local_policy.success }
        let(:event_args) { [archive_file_location] }
        it "indicates success via reporter and returns the archive file location" do
          expect(reporter).to receive(:success).with(expected_msg)
          expect(subject.generate_local_policy(reporter)).to eq archive_file_location
        end
      end
    end
  end

  describe "#render_cookbook_setup" do
    let(:reporter) { instance_double(ChefApply::StatusReporter) }
    let(:temp_cookbook) { double(ChefApply::TempCookbook) }
    let(:archive_file_location) { "/path/to/archive" }
    let(:args) { [] }
    # before do
    #   allow(ChefApply::UI::Terminal).to receive(:render_job).and_yield(reporter)
    # end

    it "generates the cookbook and local policy" do
      expect(ChefApply::UI::Terminal).to receive(:render_job) do |initial_msg, job|
        job.run(reporter)
      end
      expect(subject).to receive(:generate_temp_cookbook)
        .with(args, reporter).and_return temp_cookbook
      expect(ChefApply::UI::Terminal).to receive(:render_job) do |initial_msg, job|
        job.run(reporter)
      end
      expect(subject).to receive(:generate_local_policy)
        .with(reporter).and_return archive_file_location
      subject.render_cookbook_setup(args)
    end
  end

  describe "#render_converge" do

    let(:reporter) { instance_double(ChefApply::StatusReporter) }
    let(:host1) { ChefApply::TargetHost.new("ssh://host1") }
    let(:host2) { ChefApply::TargetHost.new("ssh://host2") }
    let(:cookbook_type) { :resource } # || :recipe
    let(:temp_cookbook) do
      instance_double(ChefApply::TempCookbook,
                      descriptor: "resource[name]",
                      from: "resource") end
    let(:archive_file_location) { "/path/to/archive" }

    before do
      allow(subject).to receive(:temp_cookbook).and_return temp_cookbook
      allow(subject).to receive(:archive_file_location).and_return archive_file_location
      expected_header = ChefApply::CLI::TS.converge.header(2, temp_cookbook.descriptor, temp_cookbook.from)
      allow(ChefApply::UI::Terminal).to receive(:render_parallel_jobs) do |header, jobs|
        expect(header).to eq expected_header
        jobs.each { |j| j.run(reporter) }
      end
    end

    let(:target_hosts) { [host1, host2] }
    it "connects, installs chef, and converges for each target" do
      target_hosts.each do |host|
        expect(subject).to receive(:connect_target).with(host, reporter)
        expect(subject).to receive(:install).with(host, reporter)
        expect(subject).to receive(:converge).with(reporter, archive_file_location, host)
      end
      subject.render_converge(target_hosts)
    end
  end

  describe "#install" do
    let(:upgrading) { false }
    let(:target_host) { double("targethost", installed_chef_version: "14.0") }
    let(:reporter) { double("reporter") }
    let(:action) do
      double("ChefApply::Actions::InstallChef",
                          upgrading?: upgrading,
                          version_to_install: "14.0") end

    it "updates status, creates an InstallChef action and executes it" do
      expect(reporter)
        .to receive(:update)
        .with(ChefApply::CLI::TS.install_chef.verifying)
      expect(ChefApply::Action::InstallChef).to receive(:new)
        .with(target_host: target_host, check_only: false)
        .and_return action
      expect(action).to receive(:run)
      subject.install(target_host, reporter)
    end

    context "when generator posts event:" do
      let(:event_args) { nil }
      let(:text_context) { ChefApply::Text.status.install_chef }

      before do
        allow(ChefApply::Action::InstallChef)
          .to receive(:new).and_return action
        allow(action)
          .to receive(:run) { |&block| block.call(event, event_args) }
        allow(reporter)
          .to receive(:update).with(ChefApply::CLI::TS.install_chef.verifying)
      end

      context ":installing" do
        let(:event) { :installing }

        context "when installer is upgrading" do
          let(:upgrading) { true }
          it "reports the update correctly" do
            expect(reporter).to receive(:update).with(text_context.upgrading(target_host.installed_chef_version, action.version_to_install))
            subject.install(target_host, reporter)
          end
        end

        context "when installer is installing clean" do
          let(:upgrading) { false }
          it "reports the update correctly" do
            expect(reporter).to receive(:update).with(text_context.installing(action.version_to_install))
            subject.install(target_host, reporter)
          end
        end
      end

      context ":uploading" do
        let(:event) { :uploading }
        it "reports the update correctly" do
          expect(reporter).to receive(:update).with(text_context.uploading)
          subject.install(target_host, reporter)
        end
      end

      context ":downloading"  do
        let(:event) { :downloading }
        it "reports the update correctly" do
          expect(reporter).to receive(:update).with(text_context.downloading)
          subject.install(target_host, reporter)
        end
      end

      context ":already_installed" do
        let(:event) { :already_installed }
        it "reports the update correctly" do
          expect(reporter).to receive(:update).with(text_context.already_present(target_host.installed_chef_version))
          subject.install(target_host, reporter)
        end
      end

      context ":install_complete" do
        let(:event) { :install_complete }
        context "when installer is upgrading" do
          let(:upgrading) { true }
          it "reports the update correctly" do
            expect(reporter).to receive(:update).with(text_context.upgrade_success(target_host.installed_chef_version,
                                                                                   action.version_to_install))
            subject.install(target_host, reporter)
          end
        end

        context "when installer installing clean" do
          let(:upgrading) { false }
          it "reports the update correctly" do
            expect(reporter).to receive(:update).with(text_context.install_success(target_host.installed_chef_version))
            subject.install(target_host, reporter)
          end
        end
      end
    end
  end
end
