
require 'byebug'
module ChefApply
  class TargetHost
    module Linux
      def omnibus_manifest_path
        # TODO - if habitat install on target, this won't work
        # Note that we can't use File::Join, because that will render for the
        # CURRENT platform - not the platform of the target.
        byebug

        "/opt/chef/version-manifest.json"
      end

      def mkdir(path)
        byebug
        run_command!("mkdir -p #{path}")
      end

      def chown(path, owner)
        byebug
        owner ||= user
        run_command!("chown #{owner} '#{path}'")
        nil
      end

      def make_temp_dir
        byebug
        # We will cache this so that we only
        @tempdir ||= begin
          res = run_command!("bash -c '#{MKTEMP_COMMAND}'")
          res.stdout.chomp.strip
        end
      end

      def install_package(target_package_path)
        byebug
        install_cmd = case File.extname(target_package_path)
                      when ".rpm"
                        "rpm -Uvh #{target_package_path}"
                      when ".deb"
                        "dpkg -i #{target_package_path}"
                      end
        run_command!(install_cmd)
        nil
      end

      def del_file(path)
        byebug
        run_command!("rm -rf #{path}")
      end

      def del_dir(path)
        byebug
        del_file(path)
      end

      def ws_cache_path
        byebug
        "/var/chef-workstation"
      end

      # Nothing to escape in a linux-based path
      def normalize_path(path)
        byebug
        path
      end

      MKTEMP_COMMAND = "d=$(mktemp -d -p${TMPDIR:-/tmp} chef_XXXXXX); echo $d".freeze

    end
  end
end
