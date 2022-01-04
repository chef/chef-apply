#
# Copyright:: Copyright (c) 2017-2019 Chef Software Inc.
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

require_relative "log"
require_relative "error"
require "train"
module ChefApply
  class TargetHost
    attr_reader :config, :reporter, :backend, :transport_type
    # These values may exist in .ssh/config but will be ignored by train
    # in favor of its defaults unless we specify them explicitly.
    # See #apply_ssh_config
    SSH_CONFIG_OVERRIDE_KEYS = %i{user port proxy}.freeze

    # We're borrowing a page from train here - because setting up a
    # reliable connection for testing is a multi-step process,
    # we'll provide this method which instantiates a TargetHost connected
    # to a train mock backend. If the family/name provided resolves to a supported
    # OS, this instance will mix-in the supporting methods for the given platform;
    # otherwise those methods will raise NotImplementedError.
    def self.mock_instance(url, family: "unknown", name: "unknown",
      release: "unknown", arch: "x86_64")
      # Specifying sudo: false ensures that attempted operations
      # don't fail because the mock platform doesn't support sudo
      target_host = TargetHost.new(url, { sudo: false })

      # Don't pull in the platform-specific mixins automatically during connect
      # Otherwise, it will raise since it can't resolve the OS without the mock.
      target_host.instance_variable_set(:@mocked_connection, true)
      target_host.connect!

      # We need to provide this mock before invoking mix_in_target_platform,
      # otherwise it will fail with an unknown OS (since we don't have a real connection).
      target_host.backend.mock_os(
        family: family,
        name: name,
        release: release,
        arch: arch
      )

      # Only mix-in if we can identify the platform.  This
      # prevents mix_in_target_platform! from raising on unknown platform during
      # tests that validate unsupported platform behaviors.
      if target_host.base_os != :other
        target_host.mix_in_target_platform!
      end

      target_host
    end

    def initialize(host_url, opts = {}, logger = nil)
      @config = connection_config(host_url, opts, logger)
      @transport_type = Train.validate_backend(@config)
      apply_ssh_config(@config, opts) if @transport_type == "ssh"
      @train_connection = Train.create(@transport_type, config)
    end

    def connection_config(host_url, opts_in, logger)
      connection_opts = { target: host_url,
                          sudo: opts_in[:sudo] === false ? false : true,
                          www_form_encoded_password: true,
                          key_files: opts_in[:identity_file],
                          non_interactive: true,
                          # Prevent long delays due to retries on auth failure.
                          # This does reduce the number of attempts we'll make for transient conditions as well, but
                          # train does not currently exposes these as separate controls. Ideally I'd like to see a 'retry_on_auth_failure' option.
                          connection_retries: 2,
                          connection_retry_sleep: 0.15,
                          logger: ChefApply::Log }
      if opts_in.key? :ssl
        connection_opts[:ssl] = opts_in[:ssl]
        connection_opts[:self_signed] = (opts_in[:ssl_verify] === false ? true : false)
      end

      %i{sudo_password sudo sudo_command password user}.each do |key|
        connection_opts[key] = opts_in[key] if opts_in.key? key
      end

      Train.target_config(connection_opts)
    end

    def apply_ssh_config(config, opts_in)
      # If we don't provide certain options, they will be defaulted
      # within train - in the case of ssh, this will prevent the .ssh/config
      # values from being picked up.
      # Here we'll modify the returned @config to specify
      # values that we get out of .ssh/config if present and if they haven't
      # been explicitly given.
      host_cfg = ssh_config_for_host(config[:host])
      SSH_CONFIG_OVERRIDE_KEYS.each do |key|
        if host_cfg.key?(key) && opts_in[key].nil?
          config[key] = host_cfg[key]
        end
      end
    end

    # Establish connection to configured target.
    #
    def connect!
      # Keep existing connections
      return unless @backend.nil?

      @backend = train_connection.connection
      @backend.wait_until_ready

      # When the testing function `mock_instance` is used, it will set
      # this instance variable to false and handle this function call
      # after the platform data is mocked; this will allow binding
      # of mixin functions based on the mocked platform.
      mix_in_target_platform! unless @mocked_connection
    rescue Train::UserError => e
      raise ConnectionFailure.new(e, config)
    rescue Train::Error => e
      # These are typically wrapper errors for other problems,
      # so we'll prefer to use e.cause over e if available.
      raise ConnectionFailure.new(e.cause || e, config)
    end

    def mix_in_target_platform!
      case base_os
      when :linux
        require_relative "target_host/linux"
        class << self; include ChefApply::TargetHost::Linux; end
      when :windows
        require_relative "target_host/windows"
        class << self; include ChefApply::TargetHost::Windows; end
      when :macos
        require_relative "target_host/macos"
        class << self; include ChefApply::TargetHost::MacOS; end
      when :solaris
        require_relative "target_host/solaris"
        class << self; include ChefApply::TargetHost::Solaris; end
      when :aix
        require_relative "target_host/aix"
        class << self; include ChefApply::TargetHost::Aix; end
      when :other
        raise ChefApply::TargetHost::UnsupportedTargetOS.new(platform.name)
      end
    end

    # Returns the user being used to connect. Defaults to train's default user if not specified
    def user
      return config[:user] unless config[:user].nil?

      require "train/transports/ssh"
      Train::Transports::SSH.default_options[:user][:default]
    end

    def hostname
      config[:host]
    end

    def architecture
      platform.arch
    end

    def version
      platform.release
    end

    def base_os
      if platform.windows?
        :windows
      elsif platform.linux?
        :linux
      elsif platform.darwin?
        :macos
      elsif platform.solaris?
        :solaris
      elsif platform.aix?
        :aix
      else
        :other
      end
    end

    # TODO 2019-01-29  not expose this, it's internal implementation. Same with #backend.
    def platform
      backend.platform
    end

    def run_command!(command)
      result = run_command(command)
      if result.exit_status != 0
        raise RemoteExecutionFailed.new(@config[:host], command, result)
      end

      result
    end

    def run_command(command)
      backend.run_command command
    end

    def upload_file(local_path, remote_path)
      backend.upload(local_path, remote_path)
    end

    # Retrieve the contents of a remote file. Returns nil
    # if the file didn't exist or couldn't be read.
    def fetch_file_contents(remote_path)
      result = backend.file(remote_path)
      if result.exist? && result.file?
        result.content
      else
        nil
      end
    end

    # Returns the installed chef version as a Gem::Version,
    # or raised ChefNotInstalled if chef client version manifest can't
    # be found.
    def installed_chef_version
      return @installed_chef_version if @installed_chef_version

      # Note: In the case of a very old version of chef (that has no manifest - pre 12.0?)
      #       this will report as not installed.
      manifest = read_chef_version_manifest

      # We split the version here because  unstable builds install from)
      # are in the form "Major.Minor.Build+HASH" which is not a valid
      # version string.
      @installed_chef_version = Gem::Version.new(manifest["build_version"].split("+")[0])
    end

    def read_chef_version_manifest
      manifest = fetch_file_contents(omnibus_manifest_path)
      raise ChefNotInstalled.new if manifest.nil?

      JSON.parse(manifest)
    end

    # Creates and caches location of temporary directory on the remote host
    # using platform-specific implementations of make_temp_dir
    # This will also set ownership to the connecting user instead of default of
    # root when sudo'd, so that the dir can be used to upload files using scp
    # as the connecting user.
    #
    # The base temp dir is cached and will only be created once per connection lifetime.
    def temp_dir
      dir = make_temp_dir
      chown(dir, user)
      dir
    end

    # create a directory.  because we run all commands as root, this will also set group:owner
    # to the connecting user if host isn't windows so that scp -- which uses the connecting user --
    # will have permissions to upload into it.
    def make_directory(path)
      mkdir(path)
      chown(path, user)
      path
    end

    # normalizes path across OS's
    def normalize_path(p) # NOTE BOOTSTRAP: was action::base::escape_windows_path
      p.tr("\\", "/")
    end

    # Simplified chown - just sets user, defaults to connection user. Does not touch
    # group.  Only has effect on non-windows targets
    def chown(path, owner); raise NotImplementedError; end

    # Platform-specific installation of packages
    def install_package(target_package_path); raise NotImplementedError; end

    def ws_cache_path; raise NotImplementedError; end

    # Recursively delete directory
    def del_dir(path); raise NotImplementedError; end

    def del_file(path); raise NotImplementedError; end

    def omnibus_manifest_path(); raise NotImplementedError; end

    private

    def train_connection
      @train_connection
    end

    def ssh_config_for_host(host)
      require "net/ssh" unless defined?(Net::SSH)
      Net::SSH::Config.for(host)
    end

    class RemoteExecutionFailed < ChefApply::ErrorNoLogs
      attr_reader :stdout, :stderr
      def initialize(host, command, result)
        super("CHEFRMT001",
              command,
              result.exit_status,
              host,
              result.stderr.empty? ? result.stdout : result.stderr)
      end
    end

    class ConnectionFailure < ChefApply::ErrorNoLogs
      # TODO: Currently this only handles sudo-related errors;
      # we should also look at e.cause for underlying connection errors
      # which are presently only visible in log files.
      def initialize(original_exception, connection_opts)
        sudo_command = connection_opts[:sudo_command]
        init_params =
          #  Comments below show the original_exception.reason values to check for instead of strings,
          #  after train 1.4.12 is consumable.
          case original_exception.message # original_exception.reason
          when /Sudo requires a password/ # :sudo_password_required
            "CHEFTRN003"
          when /Wrong sudo password/ # :bad_sudo_password
            "CHEFTRN004"
          when /Can't find sudo command/, /No such file/, /command not found/ # :sudo_command_not_found
            # NOTE: In the /No such file/ case, reason will be nil - we still have
            # to check message text. (Or PR to train to handle this case)
            ["CHEFTRN005", sudo_command] # :sudo_command_not_found
          when /Sudo requires a TTY.*/   # :sudo_no_tty
            "CHEFTRN006"
          when /has no keys added/
            "CHEFTRN007"
          else
            ["CHEFTRN999", original_exception.message]
          end
        super(*(Array(init_params).flatten))
      end
    end

    class ChefNotInstalled < StandardError; end

    class UnsupportedTargetOS < ChefApply::ErrorNoLogs
      def initialize(os_name); super("CHEFTARG001", os_name); end
    end
  end
end
