require "chef_apply/startup"
require "chef_core/text"
require "chef_core/cliux/ui/terminal"

RSpec.describe ChefApply::Startup do
  let(:argv) { [] }
  let(:telemetry) { ChefCore::Telemeter.instance }
  subject do
    ChefApply::Startup.new(argv)
  end
  before do
    allow(ChefCore::CLIUX::UI::Terminal).to receive(:init)
  end

  after do
    ChefApply::Config.reset
  end

  describe "#initalize" do
    it "initializes the terminal" do
      expect_any_instance_of(ChefApply::Startup).to receive(:init_terminal)
      ChefApply::Startup.new([])
    end
  end

  describe "#run" do
    it "performs ordered startup tasks and invokes the CLI" do
      ordered_messages = [:verify_not_in_chefdk,
                          :load_localizations,
                          :first_run_tasks,
                          :setup_workstation_user_directories,
                          :setup_error_handling,
                          :load_config,
                          :setup_logging,
                          :start_telemeter,
                          :start_chef_apply]
      ordered_messages.each do |msg|
        expect(subject).to receive(msg).ordered
      end
      subject.run()
    end

    context "when errors happen" do
      let(:error) { nil }
      let(:error_text) { ChefCore::Text.cli.error }
      before do
        # Force the error to happen in first_run_tasks, since it's always... well, first.
        expect(subject).to receive(:first_run_tasks).and_raise(error)
      end

      context "when an UnknownConfigOptionError is raised" do
        let(:bad_path) { "bad/path" }
        let(:bad_option) { "bad_option" }

        context "and it matches the expected text form" do
          let(:error) { Mixlib::Config::UnknownConfigOptionError.new("unsupported config value #{bad_option}.") }
          it "shows the correct error" do
            expected_text = error_text.invalid_config_key(bad_option, ChefApply::Config.location)
            expect(ChefCore::CLIUX::UI::Terminal).to receive(:output).with(expected_text)
            subject.run
          end
        end

        context "and it does not match the expeted text form" do
          let(:msg) { "something bad happened" }
          let(:error) { Mixlib::Config::UnknownConfigOptionError.new(msg) }
          it "shows the correct error" do
            expected_text = error_text.unknown_config_error(msg, ChefApply::Config.location)
            expect(ChefCore::CLIUX::UI::Terminal).to receive(:output).with(expected_text)
            subject.run
          end
        end
      end

      context "when a ConfigPathInvalid is raised" do
        let(:bad_path) { "bad/path" }
        let(:error) { ChefApply::Startup::ConfigPathInvalid.new(bad_path) }

        it "shows the correct error" do
          expected_text = error_text.bad_config_file(bad_path)
          expect(ChefCore::CLIUX::UI::Terminal).to receive(:output).with(expected_text)
          subject.run
        end
      end

      context "when a ConfigPathNotProvided is raised" do
        let(:error) { ChefApply::Startup::ConfigPathNotProvided.new }

        it "shows the correct error" do
          expected_text = error_text.missing_config_path
          expect(ChefCore::CLIUX::UI::Terminal).to receive(:output).with(expected_text)
          subject.run
        end
      end

      context "when a UnsupportedInstallation exception is raised" do
        let(:error) { ChefApply::Startup::UnsupportedInstallation.new }

        it "shows the correct error" do
          expected_text = error_text.unsupported_installation
          expect(ChefCore::CLIUX::UI::Terminal).to receive(:output).with(expected_text)
          subject.run
        end
      end

      context "when a Tomlrb::ParserError is raised" do
        let(:msg) { "Parse failed." }
        let(:error) { Tomlrb::ParseError.new(msg) }

        it "shows the correct error" do
          expected_text = error_text.unknown_config_error(msg, ChefApply::Config.location)
          expect(ChefCore::CLIUX::UI::Terminal).to receive(:output).with(expected_text)
          subject.run
        end
      end
    end
  end

  describe "#init_terminal" do
    it "initializees the terminal for stdout" do
      expect(ChefCore::CLIUX::UI::Terminal).to receive(:init).with($stdout)
      subject.init_terminal
    end
  end

  describe "#verify_not_in_chefdk" do
    before do
      allow(subject).to receive(:script_path).and_return script_path
    end

    context "when chef-run has been loaded from a *nix chefdk path" do
      let(:script_path) { "/opt/chefdk/embedded/lib/ruby/gems/2.5.0/gems/chef-apply/startup.rb" }
      it "raises an UnsupportedInstallation error" do
        expect { subject.verify_not_in_chefdk }.to raise_error(ChefApply::Startup::UnsupportedInstallation)
      end
    end
    context "when chef-run has been loaded from a Windows chefdk path" do
      let(:script_path) { "C:\\chefdk\\embedded\\lib\\ruby\\gems\\2.5.0\\gems\\chef-apply\\startup.rb" }
      it "raises an UnsupportedInstallation error" do
        expect { subject.verify_not_in_chefdk }.to raise_error(ChefApply::Startup::UnsupportedInstallation)
      end
    end

    context "when chef-run has been loaded from anywhere else" do
      let(:script_path) { "/home/user1/dev/chef-apply" }
      it "runs without error" do
        subject.verify_not_in_chefdk
      end
    end
  end

  describe "#first_run_tasks" do
    let(:first_run_complete) { true }
    before do
      allow(Dir).to receive(:exist?).with(ChefApply::Config::WS_BASE_PATH).and_return first_run_complete
    end

    context "when first run has already occurred" do
      let(:first_run_complete) { true }
      it "returns without taking action" do
        expect(subject).to_not receive(:create_default_config)
        expect(subject).to_not receive(:setup_telemetry)
        subject.first_run_tasks
      end
    end

    context "when first run has not already occurred" do
      let(:first_run_complete) { false }
      it "Performs required first-run tasks" do
        expect(subject).to receive(:create_default_config)
        expect(subject).to receive(:setup_telemetry)
        subject.first_run_tasks
      end
    end
  end

  describe "#create_default_config" do
    it "touches the configuration file to create it and notifies that it has done so" do
      expected_config_path = ChefApply::Config.default_location
      expected_message = ChefCore::Text.cli.creating_config(expected_config_path)
      expect(ChefCore::CLIUX::UI::Terminal).to receive(:output)
        .with(expected_message)
      expect(ChefCore::CLIUX::UI::Terminal).to receive(:output)
        .with("")
      expect(FileUtils).to receive(:touch)
        .with(expected_config_path)
      subject.create_default_config

    end
  end

  describe "#setup_telemetry" do
    let(:mock_guid) { "1234" }
    it "sets up a telemetry installation id and notifies the operator that telemetry is enabled" do
      expect(SecureRandom).to receive(:uuid).and_return(mock_guid)
      expect(File).to receive(:write)
        .with(ChefApply::Config.telemetry_installation_identifier_file, mock_guid)
      subject.setup_telemetry
    end
  end

  # TODO this now
  describe "#start_telemeter" do
    it "launches telemetry uploads" do
      # TODO 2019-02-07 verify config is sourced
      expect(ChefCore::Telemeter).to receive(:setup)
      subject.start_telemeter
    end
  end

  describe "setup_workstation_user_directories" do
    it "creates the required chef-workstation directories in HOME" do
      expect(FileUtils).to receive(:mkdir_p).with(ChefApply::Config::WS_BASE_PATH)
      expect(FileUtils).to receive(:mkdir_p).with(ChefApply::Config.base_log_directory)
      expect(FileUtils).to receive(:mkdir_p).with(ChefApply::Config.telemetry_path)
      subject.setup_workstation_user_directories
    end
  end

  describe "#custom_config_path" do
    context "when a custom config path is not provided as an option" do
      let(:args) { [] }
      it "returns nil" do
        expect(subject.custom_config_path).to be_nil
      end
    end

    context "when a --config-path is provided" do
      context "but the actual path parameter is not provided" do
        let(:argv) { %w{--config-path} }
        it "raises ConfigPathNotProvided" do
          expect { subject.custom_config_path }.to raise_error(ChefApply::Startup::ConfigPathNotProvided)
        end
      end

      context "and the path is provided" do
        let(:path) { "/mock/file.toml" }
        let(:argv) { ["--config-path", path] }

        context "but the path is not a file" do
          before do
            allow(File).to receive(:file?).with(path).and_return false
          end
          it "raises an error ConfigPathInvalid" do
            expect { subject.custom_config_path }.to raise_error(ChefApply::Startup::ConfigPathInvalid)
          end
        end

        context "and the path exists and is a valid file" do
          before do
            allow(File).to receive(:file?).with(path).and_return true
          end

          context "but it is not readable" do
            before do
              allow(File).to receive(:readable?).with(path).and_return false
            end
            it "raises an error ConfigPathInvalid" do
              expect { subject.custom_config_path }.to raise_error(ChefApply::Startup::ConfigPathInvalid)
            end
          end

          context "and it is readable" do
            before do
              allow(File).to receive(:readable?).with(path).and_return true
            end
            it "returns the custom path" do
              expect(subject.custom_config_path).to eq path
            end
          end
        end
      end
    end
  end

  describe "#load_config" do
    context "when a custom configuraton path is provided" do
      let(:config_path) { nil }
      it "loads the config at the custom path" do
        expect(subject).to receive(:custom_config_path).and_return config_path
        expect(ChefApply::Config).to receive(:custom_location).with config_path
        expect(ChefApply::Config).to receive(:load)
        subject.load_config
      end
      let(:config_path) { "/tmp/workstation-mock-config.toml" }
    end

    context "when no custom configuration path is provided" do
      let(:config_path) { nil }
      it "loads it at the default configuration path" do
        expect(subject).to receive(:custom_config_path).and_return config_path
        expect(ChefApply::Config).not_to receive(:custom_location)
        expect(ChefApply::Config).to receive(:load)
        subject.load_config
      end
    end

  end

  describe "#setup_logging" do
    let(:log_path) { "/tmp/logs" }
    let(:log_level) { :debug }
    before do
      ChefApply::Config.log.location = log_path
      ChefApply::Config.log.level = log_level
    end

    it "sets up the logging for ChefApply and Chef" do
      expect(ChefCore::Log).to receive(:setup)
        .with(log_path, log_level)
      expect(Chef::Log).to receive(:init)
        .with(ChefCore::Log.location)
      subject.setup_logging
      expect(ChefConfig.logger).to eq(ChefCore::Log)
    end
  end

  describe "#start_chef_apply" do
    let(:argv) { %w{some arguments} }
    it "runs ChefApply::CLI and passes along arguments it received" do
      run_double = instance_double(ChefApply::CLI)
      expect(ChefApply::CLI).to receive(:new).with(argv).and_return(run_double)
      expect(run_double).to receive(:run)
      subject.start_chef_apply
    end
  end

  describe "#load_localizations" do
    it "loads localizations for gems that require them" do
      ChefApply::Startup::I18NIZED_GEMS.each do |gem_name|
        expect(ChefCore::Text).to receive(:add_gem_localization).with(gem_name)
      end
      subject.load_localizations
    end

  end
end

