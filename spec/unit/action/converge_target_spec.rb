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
require "chef_apply/target_host"
require "chef_apply/action/converge_target"
require "chef_apply/action/converge_target/ccr_failure_mapper"

RSpec.describe ChefApply::Action::ConvergeTarget do
  let(:archive) { "archive.tgz" }
  let(:cache_path) { "/var/chef-workstation" }
  let(:platform_family) { "windows" }
  let(:base_os) { :windows }
  let(:target_host) do
    p = double("platform", family: platform_family)
    double(ChefApply::TargetHost,
      platform: p, base_os: base_os, ws_cache_path: cache_path)
  end
  let(:local_policy_path) { "/local/policy/path/archive.tgz" }
  let(:opts) { { target_host: target_host, local_policy_path: local_policy_path } }
  subject { ChefApply::Action::ConvergeTarget.new(opts) }

  before do
    allow(target_host).to receive(:normalize_path) { |arg| arg }
  end
  describe "#create_remote_policy" do
    let(:remote_archive) { File.join(cache_path, File.basename(archive)) }

    it "pushes it to the remote machine" do
      expect(target_host).to receive(:upload_file).with(local_policy_path, remote_archive)
      expect(subject.create_remote_policy(local_policy_path, cache_path)).to eq(remote_archive)
    end

    it "raises an error if the upload fails" do
      expect(target_host).to receive(:upload_file).with(local_policy_path, remote_archive).and_raise("foo")
      err = ChefApply::Action::ConvergeTarget::PolicyUploadFailed
      expect { subject.create_remote_policy(local_policy_path, cache_path) }.to raise_error(err)
    end
  end

  describe "#create_remote_config" do

    @closed = false # tempfile close indicator
    let(:remote_folder) { "/tmp/foo" }
    let(:remote_config_path) { "#{remote_folder}/workstation.rb" }
    # TODO - mock this, I think we're leaving things behind in /tmp in test runs.
    let!(:local_tempfile) { Tempfile.new }

    before do
      allow(Tempfile).to receive(:new).and_return(local_tempfile)
    end

    it "pushes it to the remote machine" do
      expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_config_path)
      expect(subject.create_remote_config(remote_folder)).to eq(remote_config_path)
      # ensure the tempfile is deleted locally
      expect(local_tempfile.closed?).to eq(true)
    end

    it "raises an error if the upload fails" do
      expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_config_path).and_raise("foo")
      err = ChefApply::Action::ConvergeTarget::ConfigUploadFailed
      expect { subject.create_remote_config(remote_folder) }.to raise_error(err)
      # ensure the tempfile is deleted locally
      expect(local_tempfile.closed?).to eq(true)
    end

    describe "when chef_license is configured" do
      before do
        ChefApply::Config.chef.chef_license = "accept-no-persist"
      end

      after do
        ChefApply::Config.reset
      end

      it "creates a config file with chef_license set and quoted" do
        expect(Tempfile).to receive(:new).and_return(local_tempfile)
        expect(local_tempfile).to receive(:write).with(<<~EOM
          local_mode true
          color false
          cache_path "#{cache_path}"
          chef_repo_path "#{cache_path}"
          require_relative "reporter"
          reporter = ChefApply::Reporter.new
          report_handlers << reporter
          exception_handlers << reporter
          chef_license "accept-no-persist"
        EOM
                                                      )
        expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_config_path)
        expect(subject.create_remote_config(remote_folder)).to eq(remote_config_path)
        expect(local_tempfile.closed?).to eq(true)
      end
    end

    describe "when target_level is left default" do
      before do
        ChefApply::Config.reset
      end
      # TODO - this is a windows config, but we don't set windows?
      it "creates a config file without a specific log_level (leaving default for chef-client)" do
        expect(Tempfile).to receive(:new).and_return(local_tempfile)
        expect(local_tempfile).to receive(:write).with(<<~EOM
          local_mode true
          color false
          cache_path "#{cache_path}"
          chef_repo_path "#{cache_path}"
          require_relative "reporter"
          reporter = ChefApply::Reporter.new
          report_handlers << reporter
          exception_handlers << reporter
        EOM
                                                      )
        expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_config_path)
        expect(subject.create_remote_config(remote_folder)).to eq(remote_config_path)
        expect(local_tempfile.closed?).to eq(true)
      end
    end

    describe "when target_level is set to a value" do
      before do
        ChefApply::Config.log.target_level = "info"
      end

      after do
        ChefApply::Config.reset
      end

      it "creates a config file with the log_level set to the right value" do
        expect(Tempfile).to receive(:new).and_return(local_tempfile)
        expect(local_tempfile).to receive(:write).with(<<~EOM
          local_mode true
          color false
          cache_path "#{cache_path}"
          chef_repo_path "#{cache_path}"
          require_relative "reporter"
          reporter = ChefApply::Reporter.new
          report_handlers << reporter
          exception_handlers << reporter
          log_level :info
        EOM
                                                      )
        expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_config_path)
        expect(subject.create_remote_config(remote_folder)).to eq(remote_config_path)
        expect(local_tempfile.closed?).to eq(true)
      end
    end

    describe "when data_collector is set in config" do
      before do
        ChefApply::Config.data_collector.url = "dc.url"
        ChefApply::Config.data_collector.token = "dc.token"
      end

      after do
        ChefApply::Config.reset
      end

      it "creates a config file with data collector config values" do
        expect(Tempfile).to receive(:new).and_return(local_tempfile)
        expect(local_tempfile).to receive(:write).with(<<~EOM
          local_mode true
          color false
          cache_path "#{cache_path}"
          chef_repo_path "#{cache_path}"
          require_relative "reporter"
          reporter = ChefApply::Reporter.new
          report_handlers << reporter
          exception_handlers << reporter
          data_collector.server_url "dc.url"
          data_collector.token "dc.token"
          data_collector.mode :solo
          data_collector.organization "Chef Workstation"
        EOM
                                                      )
        expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_config_path)
        expect(subject.create_remote_config(remote_folder)).to eq(remote_config_path)
        # ensure the tempfile is deleted locally
        expect(local_tempfile.closed?).to eq(true)
      end
    end

    describe "when data_collector is not set" do
      before do
        ChefApply::Config.data_collector.url = nil
        ChefApply::Config.data_collector.token = nil
      end

      it "creates a config file without data collector config values" do
        expect(Tempfile).to receive(:new).and_return(local_tempfile)
        expect(local_tempfile).to receive(:write).with(<<~EOM
          local_mode true
          color false
          cache_path "#{cache_path}"
          chef_repo_path "#{cache_path}"
          require_relative "reporter"
          reporter = ChefApply::Reporter.new
          report_handlers << reporter
          exception_handlers << reporter
        EOM
                                                      )
        expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_config_path)
        expect(subject.create_remote_config(remote_folder)).to eq(remote_config_path)
        # ensure the tempfile is deleted locally
        expect(local_tempfile.closed?).to eq(true)
      end
    end
  end

  describe "#create_remote_handler" do
    let(:remote_folder) { "/tmp/foo" }
    let(:remote_reporter) { "#{remote_folder}/reporter.rb" }
    let!(:local_tempfile) { Tempfile.new }

    it "pushes it to the remote machine" do
      expect(Tempfile).to receive(:new).and_return(local_tempfile)
      expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_reporter)
      expect(subject.create_remote_handler(remote_folder)).to eq(remote_reporter)
      # ensure the tempfile is deleted locally
      expect(local_tempfile.closed?).to eq(true)
    end

    it "raises an error if the upload fails" do
      expect(Tempfile).to receive(:new).and_return(local_tempfile)
      expect(target_host).to receive(:upload_file).with(local_tempfile.path, remote_reporter).and_raise("foo")
      err = ChefApply::Action::ConvergeTarget::HandlerUploadFailed
      expect { subject.create_remote_handler(remote_folder) }.to raise_error(err)
      # ensure the tempfile is deleted locally
      expect(local_tempfile.closed?).to eq(true)
    end
  end

  describe "#upload_trusted_certs" do
    let(:remote_folder) { "/tmp/foo" }
    let(:remote_tcd) { File.join(remote_folder, "trusted_certs") }
    let(:tmpdir) { Dir.mktmpdir }
    let(:certs_dir) { File.join(tmpdir, "weird/glob/chars[/") }

    before do
      ChefApply::Config.chef.trusted_certs_dir = certs_dir
      FileUtils.mkdir_p(certs_dir)
    end

    after do
      ChefApply::Config.reset
      FileUtils.remove_entry tmpdir
    end

    context "when there are local certificates" do
      let!(:cert1) { FileUtils.touch(File.join(certs_dir, "1.crt"))[0] }
      let!(:cert2) { FileUtils.touch(File.join(certs_dir, "2.pem"))[0] }

      it "uploads the local certs" do
        expect(target_host).to receive(:make_directory).with(remote_tcd)
        expect(target_host).to receive(:upload_file).with(cert1, File.join(remote_tcd, File.basename(cert1)))
        expect(target_host).to receive(:upload_file).with(cert2, File.join(remote_tcd, File.basename(cert2)))
        subject.upload_trusted_certs(remote_folder)
      end
    end

    context "when there are no local certificates" do
      it "does not upload any certs" do
        expect(target_host).to_not receive(:run_command)
        expect(target_host).to_not receive(:upload_file)
        subject.upload_trusted_certs(remote_folder)
      end
    end

  end

  describe "#perform_action" do
    let(:remote_folder) { "/tmp/foo" }
    let(:remote_archive) { File.join(remote_folder, File.basename(archive)) }
    let(:remote_config) { "#{remote_folder}/workstation.rb" }
    let(:remote_handler) { "#{remote_folder}/reporter.rb" }
    let(:tmpdir) { remote_folder }
    before do
      expect(target_host).to receive(:temp_dir).and_return(tmpdir)
      expect(subject).to receive(:create_remote_policy).with(local_policy_path, remote_folder).and_return(remote_archive)
      expect(subject).to receive(:create_remote_config).with(remote_folder).and_return(remote_config)
      expect(subject).to receive(:create_remote_handler).with(remote_folder).and_return(remote_handler)
      expect(subject).to receive(:upload_trusted_certs).with(remote_folder)
    end
    let(:result) { double("command result", exit_status: 0, stdout: "") }

    it "runs the converge and reports back success" do
      # Note we're only ensuring the command looks the same as #run_chef_cmd - we verify that run_chef_cmd
      # is correct in its own test elsewhere in this file
      expect(target_host).to receive(:run_command).with(subject.run_chef_cmd(remote_folder,
        "workstation.rb",
        "archive.tgz")).and_return result
      expect(target_host).to receive(:del_dir).with(remote_folder).and_return result

      %i{running_chef success}.each do |n|
        expect(subject).to receive(:notify).with(n)
      end
      subject.perform_action
    end

    context "when chef schedules restart" do
      let(:result) { double("command result", exit_status: 35) }

      it "runs the converge and reports back reboot" do
        expect(target_host).to receive(:run_command).with(subject.run_chef_cmd(remote_folder,
          "workstation.rb",
          "archive.tgz")).and_return result
        expect(target_host).to receive(:del_dir).with(remote_folder).and_return result
        %i{running_chef reboot}.each do |n|
          expect(subject).to receive(:notify).with(n)
        end
        subject.perform_action
      end
    end

    context "when command fails" do
      let(:result) { double("command result", exit_status: 1, stdout: "", stderr: "") }
      let(:report_result) { '{ "exception": "thing" }' }
      let(:exception_mapper) { double("mapper") }
      before do
        expect(ChefApply::Action::ConvergeTarget::CCRFailureMapper).to receive(:new)
          .and_return exception_mapper
      end

      it "reports back failure and reads the remote report" do
        expect(target_host).to receive(:run_command).with(subject.run_chef_cmd(remote_folder,
          "workstation.rb",
          "archive.tgz")).and_return result
        expect(target_host).to receive(:del_dir).with(remote_folder).and_return result
        %i{running_chef converge_error}.each do |n|
          expect(subject).to receive(:notify).with(n)
        end
        expect(target_host).to receive(:fetch_file_contents).with(subject.chef_report_path).and_return(report_result)
        expect(target_host).to receive(:del_file).with(subject.chef_report_path)
        expect(exception_mapper).to receive(:raise_mapped_exception!)
        subject.perform_action
      end

      context "when remote report cannot be read" do
        let(:report_result) { nil }
        it "reports back failure" do
          expect(target_host).to receive(:run_command).with(subject.run_chef_cmd(remote_folder,
            "workstation.rb",
            "archive.tgz")).and_return result
          expect(target_host).to receive(:del_dir).with(remote_folder).and_return result
          %i{running_chef converge_error}.each do |n|
            expect(subject).to receive(:notify).with(n)
          end
          expect(target_host).to receive(:fetch_file_contents).with(subject.chef_report_path).and_return(report_result)
          expect(exception_mapper).to receive(:raise_mapped_exception!)
          subject.perform_action
        end
      end
    end

  end

  context "#run_chef_cmd" do
    describe "when connecting to a windows target" do
      let(:base_os) { :windows }
      # BOOTSTRAP TODO - can't find these examples anywhere - not sure how this was passing
      # include_examples "check path fetching"

      it "correctly returns chef run string" do
        expect(subject.run_chef_cmd("a", "b", "c")).to eq(
          "Set-Location -Path a; " \
          "chef-client -z --config #{File.join("a", "b")} --recipe-url #{File.join("a", "c")} | Out-Null; " \
          "Set-Location C:/; " \
          "exit $LASTEXITCODE"
        )
      end
    end

    describe "when connecting to a non-windows target" do
      let(:base_os) { :linux }
      # BOOTSTRAP TODO - can't find these examples anywhere - not sure how this was passing
      # include_examples "check path fetching"

      it "correctly returns chef run string" do
        expect(subject.run_chef_cmd("a", "b", "c")).to eq("bash -c 'cd a; /opt/chef/bin/chef-client -z --config a/b --recipe-url a/c'")
      end
    end

  end

end
