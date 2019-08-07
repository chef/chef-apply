
require "spec_helper"
require "chef_apply/target_host"
require "chef_apply/target_host/windows"

RSpec.describe ChefApply::TargetHost::Windows do
  let(:host) { "mock://user@example.com" }
  let(:family) { "windows" }
  let(:name) { "windows" }
  let(:path) { "C:\\temp\\blah" }

  subject do
    ChefApply::TargetHost.mock_instance(host, family: family, name: name)
  end

  context "#make_temp_dir" do
    it "creates the temporary directory using the correct PowerShell command and returns the path" do
      expect(subject).to receive(:run_command!)
        .with(ChefApply::TargetHost::Windows::MKTEMP_COMMAND)
        .and_return(instance_double("result", stdout: path))
      expect(subject.make_temp_dir).to eq(path)
    end
  end

  context "#mkdir" do
    it "creates the directory using the correct command PowerShell command" do
      expect(subject).to receive(:run_command!).with("New-Item -ItemType Directory -Force -Path C:\\temp\\dir")
      subject.mkdir("C:\\temp\\dir")
    end
  end

  context "#chown" do
    xit "does nothing - this is not implemented on Windows until we need it"
  end

  context "#install_package" do
    it "runs the correct MSI package install command" do
      expected_command = "cmd /c msiexec /package C:\\My\\Package.msi /quiet"
      expect(subject).to receive(:run_command!).with(expected_command)
      subject.install_package("C:/My/Package.msi")
    end
  end
end
