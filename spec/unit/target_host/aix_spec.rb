require "spec_helper"
require "chef_apply/target_host"
require "chef_apply/target_host/aix"

RSpec.describe ChefApply::TargetHost::Aix do
  let(:user) { "testuser" }
  let(:host) { "mock://#{user}@example.com" }
  let(:family) { "aix" }
  let(:name) { "aix" }
  let(:path) { "/tmp/blah" }

  subject do
    ChefApply::TargetHost.mock_instance(host, family: family, name: name)
  end

  context "#make_temp_dir" do
    it "creates the directory using a properly formed make_temp_dir" do
      expect(subject).to receive(:run_command!)
        .with("bash -c '#{ChefApply::TargetHost::Aix::MKTEMP_COMMAND}'")
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
    # it "uses a properly formed chown to change owning user to the provided user" do
    #   expect(subject).to receive(:run_command!).with("chown newowner '/tmp/dir'")
    #   subject.chown("/tmp/dir", "newowner")
    # end
    xit "Doing nothing for this right now on aix"
  end

  context "#install_package" do
    context "run the correct pkg run command " do
      let(:expected_command) { "installp -aXYgd chef-12.0.0-rc.0-1.powerpc.bff all" }
      it "should run the correct install command" do
        expect(subject).to receive(:run_command!).with expected_command
        subject.install_package("chef-12.0.0-rc.0-1.powerpc.bff")
      end

    end
  end
end
