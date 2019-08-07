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
require "chef_apply/ui/error_printer"
require "chef_apply/text/error_translation"
require "chef_apply/errors/standard_error_resolver"
require "chef_apply/target_host"

RSpec.describe ChefApply::UI::ErrorPrinter do

  let(:orig_exception) { StandardError.new("test") }
  let(:target_host) { ChefApply::TargetHost.mock_instance("mock://localhost") }
  let(:wrapped_exception) { ChefApply::WrappedError.new(orig_exception, target_host) }

  let(:show_footer) { true }
  let(:show_log) { true }
  let(:show_stack) { true }
  let(:has_decorations) { true }
  let(:show_header) { true }
  let(:translation_mock) do
    instance_double("ChefApply::Errors::ErrorTranslation",
      footer: show_footer,
      log: show_log,
      stack: show_stack,
      header: show_header,
      decorations: has_decorations)
  end
  subject { ChefApply::UI::ErrorPrinter.new(wrapped_exception, nil) }

  before do
    allow(ChefApply::Text::ErrorTranslation).to receive(:new).and_return translation_mock
  end

  context "#format_error" do

    context "and the message has decorations" do
      let(:has_decorations)  { true }
      it "formats the message using the correct method" do
        expect(subject).to receive(:format_decorated).and_return "decorated"
        subject.format_error
      end
    end

    context "and the message does not have decorations" do
      let(:has_decorations)  { false }
      it "formats the message using the correct method" do
        expect(subject).to receive(:format_undecorated).and_return "undecorated"
        subject.format_error
      end
    end
  end

  context "#format_body" do
    RC = ChefApply::TargetHost
    context "when exception is a ChefApply::Error" do
      let(:result) { RemoteExecResult.new(1, "", "failed") }
      let(:orig_exception) { RC::RemoteExecutionFailed.new("localhost", "test", result) }
      it "invokes the right handler" do
        expect(subject).to receive(:format_workstation_exception)
        subject.format_body
      end
    end

    context "when exception is a Train::Error" do
      # These may expand as we find error-specific messaging we can provide to customers
      # for more specific train exceptions
      let(:orig_exception) { Train::Error.new("test") }
      it "invokes the right handler" do
        expect(subject).to receive(:format_train_exception)
        subject.format_body
      end
    end

    context "when exception is something else" do
      # These may expand as we find error-specific messaging we can provide to customers
      # for more specific general exceptions
      it "invokes the right handler" do
        expect(subject).to receive(:format_other_exception)
        subject.format_body
      end
    end
  end

  context ".show_error" do
    subject { ChefApply::UI::ErrorPrinter }
    context "when handling a MultiJobFailure" do
      it "recognizes it and invokes capture_multiple_failures" do
        underlying_error = ChefApply::MultiJobFailure.new([])
        error_to_process = ChefApply::Errors::StandardErrorResolver.wrap_exception(underlying_error)
        expect(subject).to receive(:capture_multiple_failures).with(underlying_error)
        subject.show_error(error_to_process)

      end
    end

    context "when an error occurs in error handling" do
      it "processes the new failure with dump_unexpected_error" do
        error_to_raise = StandardError.new("this will be raised")
        error_to_process = ChefApply::Errors::StandardErrorResolver.wrap_exception(StandardError.new("this is being shown"))
        # Intercept a known call to raise an error
        expect(ChefApply::UI::Terminal).to receive(:output).and_raise error_to_raise
        expect(subject).to receive(:dump_unexpected_error).with(error_to_raise)
        subject.show_error(error_to_process)
      end
    end

  end

  context ".capture_multiple_failures" do
    subject { ChefApply::UI::ErrorPrinter }
    let(:file_content_capture) { StringIO.new }
    before do
      allow(ChefApply::Config).to receive(:error_output_path).and_return "/dev/null"
      allow(File).to receive(:open).with("/dev/null", "w").and_yield(file_content_capture)
    end

    it "should write a properly formatted error file" do
      # TODO - add support for test-only i18n content, so that we don't have
      #        to rely on specific known error IDs that may change or be removed,
      #        and arent' directly relevant to the test at hand.
      job1 = double("Job", target_host: double("TargetHost", hostname: "host1"),
                           exception: ChefApply::Error.new("CHEFUPL005"))
      job2 = double("Job", target_host: double("TargetHost", hostname: "host2"),
                           exception: StandardError.new("Hello World"))

      expected_content = File.read("spec/unit/fixtures/multi-error.out")
      multifailure = ChefApply::MultiJobFailure.new([job1, job2] )
      subject.capture_multiple_failures(multifailure)
      expect(file_content_capture.string).to eq expected_content
    end
  end

  context "#format_footer" do
    let(:formatter) do
      ChefApply::UI::ErrorPrinter.new(wrapped_exception, nil)
    end

    subject do
      lambda { formatter.format_footer }
    end

    context "when both log and stack wanted" do
      let(:show_log) { true }
      let(:show_stack) { true }
      assert_string_lookup("errors.footer.both")
    end

    context "when only log is wanted" do
      let(:show_log) { true }
      let(:show_stack) { false }
      assert_string_lookup("errors.footer.log_only")
    end

    context "when only stack is wanted" do
      let(:show_log) { false }
      let(:show_stack) { true }
      assert_string_lookup("errors.footer.stack_only")
    end

    context "when neither log nor stack wanted" do
      let(:show_log) { false }
      let(:show_stack) { false }
      assert_string_lookup("errors.footer.neither")
    end
  end

  context ".write_backtrace" do
    let(:inst) { double(ChefApply::UI::ErrorPrinter) }
    before do
      allow(ChefApply::UI::ErrorPrinter).to receive(:new).and_return inst
    end

    let(:orig_args) { %w{test} }
    it "formats and saves the backtrace" do
      expect(inst).to receive(:add_backtrace_header).with(anything, orig_args)
      expect(inst).to receive(:add_formatted_backtrace)
      expect(inst).to receive(:save_backtrace)
      ChefApply::UI::ErrorPrinter.write_backtrace(wrapped_exception, orig_args)
    end
  end
end
