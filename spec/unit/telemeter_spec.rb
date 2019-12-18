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

require "spec_helper"
require "chef_apply/telemeter"

RSpec.describe ChefApply::Telemeter do
  subject { ChefApply::Telemeter }
  let(:host_platform) { "linux" }
  context "#timed_action_capture" do
    context "when a valid target_host is present" do
      it "invokes timed_capture with action and valid target data" do
        target = instance_double("TargetHost",
          base_os: "windows",
          version: "10.0.0",
          architecture: "x86_64",
          hostname: "My_Host",
          transport_type: "winrm")
        action = instance_double("Action::Base", name: "test_action",
                                                 target_host: target)
        expected_data = {
          action: "test_action",
          target: {
            platform: {
              name: "windows",
              version: "10.0.0",
              architecture: "x86_64",
            },
            hostname_sha1: Digest::SHA1.hexdigest("my_host"),
            transport_type: "winrm",
          },
        }
        expect(Chef::Telemeter).to receive(:timed_capture).with(:action, expected_data)
        subject.timed_action_capture(action) { :ok }
      end

      context "when a valid target_host is not present" do
        it "invokes timed_capture with empty target values" do
          expected_data = { action: "Base", target: { platform: {},
                                                      hostname_sha1: nil,
                                                      transport_type: nil } }
          expect(Chef::Telemeter).to receive(:timed_capture)
            .with(:action, expected_data)
          subject.timed_action_capture(
            ChefApply::Action::Base.new(target_host: nil)
          ) { :ok }
        end
      end
    end
  end
end
