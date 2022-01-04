module ChefApply
  class TargetHost
    module Aix

      def omnibus_manifest_path
        # Note that we can't use File::Join, because that will render for the
        # CURRENT platform - not the platform of the target.
        "/opt/chef/version-manifest.json"
      end

      def mkdir(path)
        run_command!("mkdir -p #{path}")
      end

      def chown(path, owner)
        owner ||= user
        run_command!("chown #{owner} '#{path}'")
        nil
      end

      def make_temp_dir
        # We will cache this so that we only run this once
        @tempdir ||= begin
          res = run_command!("bash -c '#{MKTEMP_COMMAND}'")
          res.stdout.chomp.strip
        end
      end

      def install_package(target_package_path)
        # command = "pkg install -g #{target_package_path} chef"
        #  command = "installp -ld #{target_package_path}"
        command = "installp -aXYgd #{target_package_path} all"
        run_command!(command)
      end

      def del_file(path)
        run_command!("rm -rf #{path}")
      end

      def del_dir(path)
        del_file(path)
      end

      def ws_cache_path
        "/var/chef-workstation"
      end

      # Nothing to escape in a unix-based path
      def normalize_path(path)
        path
      end

      MKTEMP_COMMAND = "d=$(mktemp -d -p${TMPDIR:-/tmp} chef_XXXXXX); echo $d".freeze

    end
  end
end
