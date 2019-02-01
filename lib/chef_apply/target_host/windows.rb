
module ChefApply
  class TargetHost
    module Windows
      def omnibus_manifest_path
        # TODO - use a proper method to query the win installation path -
        #        currently we're assuming the default, but this can be customized
        #        at install time.
        #        A working approach is below - but it runs very slowly (~10s) in testing
        #        on a virtualbox windows vm:
        #        (over winrm) Get-WmiObject Win32_Product | Where {$_.Name -match 'Chef Client'}
        # TODO - if habitat install on target, this won't work
        "c:\\opscode\\chef\\version-manifest.json"
      end

      def mkdir(path)
        run_command!("New-Item -ItemType Directory -Force -Path #{path}")
      end

      def chown(path, owner)
        # This implementation left intentionally blank.
        # To date, we have not needed chown functionality on windows;
        # when/if that changes we'll need to implement it here.
        nil
      end

      def make_temp_dir
        @tmpdir ||= begin
          res = run_command!(MKTEMP_COMMAND)
          res.stdout.chomp.strip
        end
      end

      def install_package(target_package_path)
        # While powershell does not mind the mixed path separators \ and /,
        # 'cmd.exe' definitely does - so we'll make the path cmd-friendly
        # before running the command
        cmd = "cmd /c msiexec /package #{target_package_path.tr("/", "\\")} /quiet"
        run_command!(cmd)
        nil
      end

      def del_file(path)
        run_command!("If (Test-Path #{path}) { Remove-Item -Force -Path #{path} }")
      end

      def del_dir(path)
        run_command!("Remove-Item -Recurse -Force –Path #{path}")
      end

      def ws_cache_path
        '#{ENV[\'APPDATA\']}/chef-workstation'
      end

      MKTEMP_COMMAND = "$parent = [System.IO.Path]::GetTempPath();" +
        "[string] $name = [System.Guid]::NewGuid();" +
        "$tmp = New-Item -ItemType Directory -Path " +
        "(Join-Path $parent $name);" +
        "$tmp.FullName".freeze
    end
  end
end
