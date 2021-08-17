require "spec_helper"
require "chef_apply/target_host"
require "chef_apply/target_host/solaris"

RSpec.describe ChefApply::TargetHost::Linux do
  let(:user) { "testuser" }
  let(:host) { "mock://#{user}@example.com" }
  let(:family) { "solaris" }
  let(:name) { "solaris" }
  let(:path) { "/tmp/blah" }

  subject do
    ChefApply::TargetHost.mock_instance(host, family: family, name: name)
  end

  context "#make_temp_dir" do
    it "creates the directory using a properly formed make_temp_dir" do
      expect(subject).to receive(:run_command!)
        .with("bash -c '#{ChefApply::TargetHost::Solaris::MKTEMP_COMMAND}'")
        .and_return(instance_double("result", stdout: "/tmp/blah"))
      expect(subject.make_temp_dir).to eq "/tmp/blah"
    end
  end

  context "#mkdir" do
    it "uses a properly formed mkdir to create the directory and changes ownership to connected user" do
      expect(subject).to receive(:run_command!).with("mkdir -p /tmp/dir")
      subject.mkdir("/tmp/dir")
    end
  end

  context "#chown" do
    it "uses a properly formed chown to change owning user to the provided user" do
      expect(subject).to receive(:run_command!).with("chown newowner '/tmp/dir'")
      subject.chown("/tmp/dir", "newowner")
    end
  end

  context "#install_package" do
    context "when it receives an RPM package" do
      # solaris packages to be installed here
      let(:expected_command) { "rpm -Uvh /my/package.rpm" }
      it "should run the correct rpm command" do
        expect(subject).to receive(:run_command!).with expected_command
        subject.install_package("/my/package.rpm")

      end

    end
    context "when it receives a DEB package" do
      let(:expected_command) { "dpkg -i /my/package.deb" }
      it "should run the correct dpkg command" do
        expect(subject).to receive(:run_command!).with expected_command
        subject.install_package("/my/package.deb")
      end
    end
  end
end
