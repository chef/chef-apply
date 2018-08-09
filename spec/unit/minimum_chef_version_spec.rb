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

require "chef_apply/minimum_chef_version"
require "chef_apply/target_host"
require "spec_helper"

RSpec.describe ChefApply::MinimumChefVersion do
  let(:base_os) { :linux }
  let(:version) { 14 }
  let(:target) { instance_double(ChefApply::TargetHost, base_os: base_os, installed_chef_version: version) }
  subject(:klass) { ChefApply::MinimumChefVersion }

  context "#check!" do
    context "when chef is not already installed on target" do
      before do
        expect(target).to receive(:installed_chef_version).
          and_raise ChefApply::TargetHost::ChefNotInstalled.new
      end

      it "should return :client_not_installed" do
        actual = klass.check!(target, false)
        expect(:client_not_installed).to eq(actual)
      end

      context "when config is set to check_only" do
        it "raises ClientNotInstalled" do
          expect do
            klass.check!(target, true)
          end.to raise_error(ChefApply::MinimumChefVersion::ClientNotInstalled)
        end
      end
    end

    [:windows, :linux].each do |os|
      context "on #{os}" do
        let(:base_os) { os }
        [13, 14].each do |major_version|
          context "when chef is already installed at the correct minimum Chef #{major_version} version" do
            let(:version) { ChefApply::MinimumChefVersion::CONSTRAINTS[os][major_version] }
            it "should return :minimum_version_met" do
              actual = klass.check!(target, false)
              expect(:minimum_version_met).to eq(actual)
            end
          end
        end
      end
    end

    installed_expected = {
      windows: {
        Gem::Version.new("12.1.1") => ChefApply::MinimumChefVersion::Client13Outdated,
        Gem::Version.new("13.9.0") => ChefApply::MinimumChefVersion::Client13Outdated,
        Gem::Version.new("14.3.37") => ChefApply::MinimumChefVersion::Client14Outdated,
      },
      linux: {
        Gem::Version.new("12.1.1") => ChefApply::MinimumChefVersion::Client13Outdated,
        Gem::Version.new("13.9.0") => ChefApply::MinimumChefVersion::Client13Outdated,
        Gem::Version.new("14.1.0") => ChefApply::MinimumChefVersion::Client14Outdated,
      }
    }
    [:windows, :linux].each do |os|
      context "on #{os}" do
        let(:base_os) { os }
        installed_expected[os].each do |installed, expected|
          context "when chef is already installed on target at version #{installed}" do
            let(:version) { installed }
            it "notifies of failure and takes no further action" do
              expect { klass.check!(target, false) }.to raise_error(expected)
            end
          end
        end
      end
    end
  end
end
