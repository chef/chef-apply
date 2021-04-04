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

module ChefApply
  class TargetHost
    module MacOS
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

      def install_package(remote_path)
        install_cmd = <<-EOS
        hdiutil detach "/Volumes/chef_software" >/dev/null 2>&1 || true
        hdiutil attach #{remote_path} -mountpoint "/Volumes/chef_software"
        cd / && sudo /usr/sbin/installer -pkg `sudo find "/Volumes/chef_software" -name \\*.pkg` -target /
        EOS
        run_command!(install_cmd)
        nil
      end

      def del_file(path)
        run_command!("rm -rf #{path}")
      end

      def del_dir(path)
        del_file(path)
      end

      def make_temp_dir
        installer_dir = "/tmp/chef-installer"
        run_command!("mkdir -p #{installer_dir}")
        run_command!("chmod 777 #{installer_dir}")
        installer_dir
      end

      def ws_cache_path
        "/var/chef-workstation"
      end

    end
  end
end