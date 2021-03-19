require "spec_helper"
require "chef_apply/target_host"
require "chef_apply/target_host/macos"

RSpec.describe ChefApply::TargetHost::MacOS do
  let(:user) { "testuser" }
  let(:host) { "mock://#{user}@example.com" }
  let(:family) { "darwin" }
  let(:name) { "darwin" }

  subject do
    ChefApply::TargetHost.mock_instance(host, family: family, name: name)
  end

  context "#make_temp_dir" do
    it "creates the directory using a properly formed make_temp_dir" do
        installer_dir = "/tmp/chef-installer"
      expect(subject).to receive(:run_command!)
        .with("mkdir -p #{installer_dir}")
      expect(subject).to receive(:run_command!)
        .with("chmod 777 #{installer_dir}")  
        .and_return(instance_double("result", stdout: "/tmp/blah"))
      expect(subject.make_temp_dir).to eq "/tmp/chef-installer"
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
    it "runs the correct dmg package install command" do
        expected_command = <<-EOS
        hdiutil detach "/Volumes/chef_software" >/dev/null 2>&1 || true
        hdiutil attach /tmp/chef-installer/chef-16.11.7-1.x86_64.dmg -mountpoint "/Volumes/chef_software"
        cd / && sudo /usr/sbin/installer -pkg `sudo find "/Volumes/chef_software" -name \\*.pkg` -target /
        EOS
        expect(subject).to receive(:run_command!).with(expected_command)
        subject.install_package("/tmp/chef-installer/chef-16.11.7-1.x86_64.dmg")
    end
  end
end
