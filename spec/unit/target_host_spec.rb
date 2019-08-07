#
# Copyright:: Copyright (c) 2018-2019 Chef Software Inc.
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
  let(:family) { "debian" }
  let(:name) { "ubuntu" }

  subject do
    ChefApply::TargetHost.mock_instance(host, family: family, name: name)
  end

  context "#base_os" do
    context "for a windows os" do
      let(:family) { "windows" }
      let(:name) { "windows" }
      it "reports :windows" do
        expect(subject.base_os).to eq :windows
      end
    end

    context "for a linux os" do
      let(:family) { "debian" }
      let(:name) { "ubuntu" }
      it "reports :linux" do
        expect(subject.base_os).to eq :linux
      end
    end

    context "for an unsupported OS" do
      let(:family) { "unknown" }
      let(:name) { "unknown" }
      it "reports :other" do
        expect(subject.base_os).to eq :other
      end
    end
  end

  context "#installed_chef_version" do
    context "when no version manifest is present" do
      it "raises ChefNotInstalled" do
        expect(subject).to receive(:read_chef_version_manifest).and_raise(ChefApply::TargetHost::ChefNotInstalled.new)
        expect { subject.installed_chef_version }.to raise_error(ChefApply::TargetHost::ChefNotInstalled)
      end
    end

    context "when version manifest is present" do
      let(:manifest) { { "build_version" => "14.0.1" } }
      it "reports version based on the build_version field" do
        expect(subject).to receive(:read_chef_version_manifest).and_return manifest
        expect(subject.installed_chef_version).to eq Gem::Version.new("14.0.1")
      end
    end
  end

  context "connect!" do
    # For all other tets, target_host is a mocked instance that is already connected
    # In this case, we want to build a new one that is not yet connected to test connect! itself.
    let(:target_host) { ChefApply::TargetHost.new(host, sudo: false) }
    let(:train_connection_mock) { double("train connection") }
    before do
      allow(target_host).to receive(:train_connection).and_return(train_connection_mock)
    end
    context "when an Train::UserError occurs" do
      it "raises a ConnectionFailure" do
        allow(train_connection_mock).to receive(:connection).and_raise Train::UserError
        expect { target_host.connect! }.to raise_error(ChefApply::TargetHost::ConnectionFailure)
      end
    end
    context "when a Train::Error occurs" do
      it "raises a ConnectionFailure" do
        allow(train_connection_mock).to receive(:connection).and_raise Train::Error
        expect { target_host.connect! }.to raise_error(ChefApply::TargetHost::ConnectionFailure)
      end
    end
  end

  context "#mix_in_target_platform!" do
    let(:base_os) { :none }
    before do
      allow(subject).to receive(:base_os).and_return base_os
    end

    context "when base_os is linux" do
      let(:base_os) { :linux }
      it "mixes in Linux support" do
        expect(subject.class).to receive(:include).with(ChefApply::TargetHost::Linux)
        subject.mix_in_target_platform!
      end
    end

    context "when base_os is windows" do
      let(:base_os) { :windows }
      it "mixes in Windows support" do
        expect(subject.class).to receive(:include).with(ChefApply::TargetHost::Windows)
        subject.mix_in_target_platform!
      end
    end

    context "when base_os is other" do
      let(:base_os) { :other }
      it "raises UnsupportedTargetOS" do
        expect { subject.mix_in_target_platform! }.to raise_error(ChefApply::TargetHost::UnsupportedTargetOS)
      end

    end
    context "after it connects" do
      context "to a Windows host" do
        it "includes the Windows TargetHost mixin" do
        end

      end

      context "and the platform is linux" do
        it "includes the Windows TargetHost mixin" do
        end
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

  context "#read_chef_version_manifest" do
    let(:manifest_content) { '{"build_version" : "1.2.3"}' }
    before do
      allow(subject).to receive(:fetch_file_contents).and_return(manifest_content)
      allow(subject).to receive(:omnibus_manifest_path).and_return("/path/to/manifest.json")
    end

    context "when manifest is missing" do
      let(:manifest_content) { nil }
      it "raises ChefNotInstalled" do
        expect { subject.read_chef_version_manifest }.to raise_error(ChefApply::TargetHost::ChefNotInstalled)
      end
    end

    context "when manifest is present" do
      let(:manifest_content) { '{"build_version" : "1.2.3"}' }
      it "should return the parsed manifest" do
        expect(subject.read_chef_version_manifest).to eq({ "build_version" => "1.2.3" })
      end
    end
  end

  # What we test:
  #   - file contents can be retrieved, and invalid conditions results in no content
  # What we mock:
  #   - the train `backend`
  #   - the backend `file` method
  #   Why?
  #     - in this unit test, we're not testing round-trip behavior of the train API, only
  #       that we are invoking the API and interpreting its results correctly.
  context "#fetch_file_contents" do
    let(:path) { "/path/to/file" }
    let(:sample_content) { "content" }
    let(:backend_mock) { double("backend") }
    let(:path_exists) { true }
    let(:path_is_file) { true }
    let(:remote_file_mock) do
      double("remote_file", exist?: path_exists,
                                    file?: path_is_file, content: sample_content)
    end
    before do
      expect(subject).to receive(:backend).and_return backend_mock
      expect(backend_mock).to receive(:file).with(path).and_return remote_file_mock
    end

    context "when path exists" do
      let(:path_exists) { true }
      before do
      end

      context "but is not a file" do
        let(:path_is_file) { false }
        it "returns nil" do
          expect(subject.fetch_file_contents(path)).to be_nil
        end
      end
      context "and is a file" do
        it "returns the expected file contents" do
          expect(subject.fetch_file_contents(path)).to eq sample_content
        end
      end
    end
    context "when path does not exist" do
      let(:path_exists) { false }
      it "returns nil" do
        expect(subject.fetch_file_contents(path)).to be_nil
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

  context "#temp_dir" do
    it "creates the temp directory and changes ownership" do
      expect(subject).to receive(:make_temp_dir).and_return("/tmp/dir")
      expect(subject).to receive(:chown).with("/tmp/dir", subject.user)
      subject.temp_dir
    end
  end

  context "#make_directory" do
    it "creates the directory and sets ownership to connecting user" do
      expect(subject).to receive(:mkdir).with("/tmp/mkdir")
      expect(subject).to receive(:chown).with("/tmp/mkdir", subject.user)
      subject.make_directory("/tmp/mkdir")
    end
  end

end
