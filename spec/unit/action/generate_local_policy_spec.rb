#
# Copyright:: Copyright (c) 2017 Chef Software Inc.
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
require "chef_apply/action/generate_local_policy"
require "chef-cli/policyfile_services/install"
require "chef-cli/ui"
require "chef-cli/policyfile_services/export_repo"

RSpec.describe ChefApply::Action::GenerateLocalPolicy do
  subject { ChefApply::Action::GenerateLocalPolicy.new(cookbook: cookbook) }
  let(:cookbook) do
    double("TempCookbook",
      path: "/my/temp/cookbook",
      export_path: "/my/temp/cookbook/export",
      policyfile_lock_path: "/my/temp/cookbook/policyfile.lock")
  end

  let(:installer_double) do
    instance_double(ChefCLI::PolicyfileServices::Install, run: :ok)
  end

  let(:exporter_double) do
    instance_double(ChefCLI::PolicyfileServices::ExportRepo,
      archive_file_location: "/path/to/export",
      run: :ok)
  end

  before do
    allow(subject).to receive(:notify)
  end

  describe "#perform_action" do
    context "in the normal case" do
      it "exports the policy notifying caller of progress, setting archive_file_location" do
        expect(subject).to receive(:notify).ordered.with(:generating)
        expect(subject).to receive(:installer).ordered.and_return installer_double
        expect(installer_double).to receive(:run).ordered
        expect(subject).to receive(:notify).ordered.with(:exporting)
        expect(subject).to receive(:exporter).ordered.and_return exporter_double
        expect(exporter_double).to receive(:run).ordered
        expect(subject).to receive(:exporter).ordered.and_return exporter_double
        expect(subject).to receive(:notify).ordered.with(:success)
        subject.perform_action
        expect(subject.archive_file_location).to eq("/path/to/export")
      end
    end

    context "when PolicyfileServices raises an error" do
      it "reraises as PolicyfileInstallError" do
        expect(subject).to receive(:installer).and_return installer_double
        expect(installer_double).to receive(:run).and_raise(ChefCLI::PolicyfileInstallError.new("", nil))
        expect { subject.perform_action }.to raise_error(ChefApply::Action::PolicyfileInstallError)
      end
    end

    context "when the path name is too long" do
      let(:name) { "THIS_IS_A_REALLY_LONG_STRING111111111111111111111111111111111111111111111111111111" }

      # There is an issue with policyfile generation where, if we have a cookbook with too long
      # of a name or directory name the policyfile will not generate. This is because the tar
      # library that ChefCLI uses comes from the Rubygems package and is meant for packaging
      # gems up, so it can impose a 100 character limit. We attempt to solve this by ensuring
      # that the paths/names we generate with `TempCookbook` are short.
      #
      # This is here for documentation
      # 2018-05-18 mp addendum: this cna take upwards of 15s to run on ci nodes, pending
      # for now since it's not testing any Chef Apply functionality.
      xit "fails to create when there is a long path name" do
        err = ChefCLI::PolicyfileExportRepoError
        expect { subject.perform_action }.to raise_error(err) do |e|
          expect(e.cause.class).to eq(Gem::Package::TooLongFileName)
          expect(e.cause.message).to match(/should be 100 or less/)
        end
      end
    end
  end

  describe "#exporter" do

    it "returns a correctly constructed ExportRepo" do
      expect(ChefCLI::PolicyfileServices::ExportRepo).to receive(:new)
        .with(policyfile: cookbook.policyfile_lock_path,
              root_dir: cookbook.path,
              export_dir:  cookbook.export_path,
              archive: true, force: true)
        .and_return exporter_double
      expect(subject.exporter).to eq exporter_double
    end
  end

  describe "#installer" do
    it "returns a correctly constructed Install service" do
      expect(ChefCLI::PolicyfileServices::Install).to receive(:new)
        .with(ui: ChefCLI::UI, root_dir: cookbook.path)
        .and_return(installer_double)
      expect(subject.installer).to eq installer_double
    end
  end

end
