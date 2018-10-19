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
require "ostruct"
require "chef_apply/target_host"

RSpec.describe ChefApply::TargetHost do
  let(:host) { "mock://user@example.com" }
  let(:sudo) { true }
  let(:logger) { nil }
  let(:family) { "windows" }
  let(:is_linux) { false }
  let(:platform_mock) { double("platform", linux?: is_linux, family: family, name: "an os") }
  subject do
    s = ChefApply::TargetHost.new(host, sudo: sudo, logger: logger)
    allow(s).to receive(:platform).and_return(platform_mock)
    s
  end

  context "#base_os" do
    context "for a windows os" do
      it "reports :windows" do
        expect(subject.base_os).to eq :windows
      end
    end

    context "for a linux os" do
      let(:family) { "debian" }
      let(:is_linux) { true }
      it "reports :linux" do
        expect(subject.base_os).to eq :linux
      end
    end

    context "for an unsupported OS" do
      let(:family) { "other" }
      let(:is_linux) { false }
      it "raises UnsupportedTargetOS" do
        expect { subject.base_os }.to raise_error(ChefApply::TargetHost::UnsupportedTargetOS)
      end
    end
  end

  context "#installed_chef_version" do
    let(:manifest) { :not_found }
    before do
      allow(subject).to receive(:get_chef_version_manifest).and_return manifest
    end

    context "when no version manifest is present" do
      it "raises ChefNotInstalled" do
        expect { subject.installed_chef_version }.to raise_error(ChefApply::TargetHost::ChefNotInstalled)
      end
    end

    context "when version manifest is present" do
      let(:manifest) { { "build_version" => "14.0.1" } }
      it "reports version based on the build_version field" do
        expect(subject.installed_chef_version).to eq Gem::Version.new("14.0.1")
      end
    end
  end

  context "connect!" do
    let(:train_connection_mock) { double("train connection") }
    before do
      allow(subject).to receive(:train_connection).and_return(train_connection_mock)
    end
    context "when an Train::UserError occurs" do
      it "raises a ConnectionFailure" do
        allow(train_connection_mock).to receive(:connection).and_raise Train::UserError
        expect { subject.connect! }.to raise_error(ChefApply::TargetHost::ConnectionFailure)
      end
    end
    context "when a Train::Error occurs" do
      it "raises a ConnectionFailure" do
        allow(train_connection_mock).to receive(:connection).and_raise Train::Error
        expect { subject.connect! }.to raise_error(ChefApply::TargetHost::ConnectionFailure)
      end
    end
  end

  context "#user" do
    before do
      allow(subject).to receive(:config).and_return(user: user)
    end
    context "when a user has been configured" do
      let(:user) { "testuser" }
      it "returns that user" do
        expect(subject.user).to eq user
      end
    end
    context "when no user has been configured" do
      let(:user) { nil }
      it "returns the correct default from train" do
        expect(subject.user).to eq Train::Transports::SSH.default_options[:user][:default]
      end
    end
  end

  context "#run_command!" do
    let(:backend) { double("backend") }
    let(:exit_status) { 0 }
    let(:result) { RemoteExecResult.new(exit_status, "", "an error occurred") }
    let(:command) { "cmd" }

    before do
      allow(subject).to receive(:backend).and_return(backend)
      allow(backend).to receive(:run_command).with(command).and_return(result)
    end

    context "when no error occurs" do
      let(:exit_status) { 0 }
      it "returns the result" do
        expect(subject.run_command!(command)).to eq result
      end
    end

    context "when an error occurs" do
      let(:exit_status) { 1 }
      it "raises a RemoteExecutionFailed error" do
        expected_error = ChefApply::TargetHost::RemoteExecutionFailed
        expect { subject.run_command!(command) }.to raise_error(expected_error)
      end
    end
  end

  context "#get_chef_version_manifest" do
    let(:manifest_content) { '{"build_version" : "1.2.3"}' }
    let(:expected_manifest_path) do
      {
        windows: "c:\\opscode\\chef\\version-manifest.json",
        linux: "/opt/chef/version-manifest.json"
      }
    end
    let(:base_os) { :unknown }
    before do
      remote_file_mock = double("remote_file", file?: manifest_exists, content: manifest_content)
      backend_mock = double("backend")
      expect(backend_mock).to receive(:file).
        with(expected_manifest_path[base_os]).
        and_return(remote_file_mock)
      allow(subject).to receive(:backend).and_return backend_mock
      allow(subject).to receive(:base_os).and_return base_os
    end

    context "when manifest is missing" do
      let(:manifest_exists) { false }
      context "on windows" do
        let(:base_os) { :windows }
        it "returns :not_found" do
          expect(subject.get_chef_version_manifest).to eq :not_found
        end

      end
      context "on linux" do
        let(:base_os) { :linux }
        it "returns :not_found" do
          expect(subject.get_chef_version_manifest).to eq :not_found
        end
      end
    end

    context "when manifest is present" do
      let(:manifest_exists) { true }
      context "on windows" do
        let(:base_os) { :windows }
        it "should return the parsed manifest" do
          expect(subject.get_chef_version_manifest).to eq({ "build_version" => "1.2.3" })
        end
      end

      context "on linux" do
        let(:base_os) { :linux }
        it "should return the parsed manifest" do
          expect(subject.get_chef_version_manifest).to eq({ "build_version" => "1.2.3" })
        end
      end
    end
  end

  context "#apply_ssh_config" do
    let(:ssh_host_config) { { user: "testuser", port: 1000, proxy: double("Net:SSH::Proxy::Command") } }
    let(:connection_config) { { user: "user1", port: 8022, proxy: nil } }
    before do
      allow(subject).to receive(:ssh_config_for_host).and_return ssh_host_config
    end

    ChefApply::TargetHost::SSH_CONFIG_OVERRIDE_KEYS.each do |key|
      context "when a value is not explicitly provided in options" do
        it "replaces config config[:#{key}] with the ssh config value" do
          subject.apply_ssh_config(connection_config, key => nil)
          expect(connection_config[key]).to eq(ssh_host_config[key])
        end
      end

      context "when a value is explicitly provided in options" do
        it "the connection configuration isnot updated with a value from ssh config" do
          original_config = connection_config.clone
          subject.apply_ssh_config(connection_config, { key => "testvalue" } )
          expect(connection_config[key]).to eq original_config[key]
        end
      end
    end
  end

  context "target host operations" do
    let(:base_os) { :unknown }
    let(:user) { "testuser" }
    before do
      allow(subject).to receive(:base_os).and_return base_os
      allow(subject).to receive(:user).and_return user
    end
    context "#mkdir" do
      context "when the target is Windows" do
        let(:base_os) { :windows }
        it "creates the directory using the correct command PowerShell command" do
          # TODO - testing command strings always feels a bit like an antipattern. Do we have alternatives?
          expect(subject).to receive(:run_command!).with("New-Item -ItemType Directory -Force -Path C:\\temp\\dir")
          subject.mkdir("C:\\temp\\dir")
        end

      end
      context "when the target is Linux" do
        let(:base_os) { :linux }
        it "uses a properly formed mkdir to create the directory and changes ownership to connected user" do
          expect(subject).to receive(:run_command!).with("mkdir -p /tmp/dir")
          expect(subject).to receive(:run_command!).with("chown testuser '/tmp/dir'")
          subject.mkdir("/tmp/dir")

        end
      end
    end

    context "#chown" do
      context "when the target is Windows" do
        let(:base_os) { :windows }
        xit "does nothing - this is not implemented until we need it"
      end

      context "when the target is Linux" do
        let(:base_os) { :linux }
        let(:path) { "/tmp/blah" }

        context "and an owner is provided" do
          it "uses a properly formed chown to change owning user to the connected user" do
            expect(subject).to receive(:run_command!).with("chown newowner '/tmp/dir'")
            subject.chown("/tmp/dir", "newowner")
          end
        end

        context "and an owner is not provided" do
          it "uses a properly formed chown to change owning user to the connected user" do
            expect(subject).to receive(:run_command!).with("chown #{user} '/tmp/dir'")
            subject.chown("/tmp/dir")
          end
        end
      end
    end

    context "#mktemp" do
      context "when the target is Windows" do
        let(:base_os) { :windows }
        let(:path) { "C:\\temp\\blah" }
        it "creates the temporary directory using the correct PowerShell command and returns the path" do
          expect(subject).to receive(:run_command!).
            with(ChefApply::TargetHost::MKTMP_WIN_CMD).
            and_return(instance_double("result", stdout: path))
          expect(subject.mktemp()).to eq(path)
        end
      end

      context "when the target is Linux" do
        let(:base_os) { :linux }
        let(:path) { "/tmp/blah" }
        it "creates the directory using a properly formed mktemp, changes ownership to connecting user, and returns the path" do
          expect(subject).to receive(:run_command!).
            with("bash -c '#{ChefApply::TargetHost::MKTMP_LINUX_CMD}'").
            and_return(instance_double("result", stdout: "/tmp/blah"))
          expect(subject).to receive(:chown).with(path)
          expect(subject.mktemp()).to eq path
        end
      end
    end
  end
end
