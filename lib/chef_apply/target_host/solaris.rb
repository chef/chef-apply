

module ChefApply
  class TargetHost
    module Solaris
      def omnibus_manifest_path
        # TODO - if habitat install on target, this won't work
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
        # We will cache this so that we only
        @tempdir ||= begin
          res = run_command!("bash -c '#{MKTEMP_COMMAND}'")
          res.stdout.chomp.strip
        end
      end

      def install_package(name, version)
        logger.trace("#{new_resource} package install options: #{options}")
        if options.nil?
          command = if ::File.directory?(new_resource.source) # CHEF-4469
                      [ "pkgadd", "-n", "-d", new_resource.source, new_resource.package_name ]
                    else
                      [ "pkgadd", "-n", "-d", new_resource.source, "all" ]
                    end
          shell_out!(command)
          logger.trace("#{new_resource} installed version #{new_resource.version} from: #{new_resource.source}")
        else
          command = if ::File.directory?(new_resource.source) # CHEF-4469
                      [ "pkgadd", "-n", options, "-d", new_resource.source, new_resource.package_name ]
                    else
                      [ "pkgadd", "-n", options, "-d", new_resource.source, "all" ]
                    end
          shell_out!(*command)
          logger.trace("#{new_resource} installed version #{new_resource.version} from: #{new_resource.source}")
        end
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

      # Nothing to escape in a linux-based path
      def normalize_path(path)
        path
      end

      MKTEMP_COMMAND = "d=$(mktemp -d -p${TMPDIR:-/tmp} chef_XXXXXX); echo $d".freeze

    end
  end
end
