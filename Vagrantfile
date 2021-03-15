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

Vagrant.configure("2") do |config|
  config.ssh.forward_agent = true

  1.upto(5).each do |num|
    name = "ubuntu#{num}"
    config.vm.define name do |node|
      node.vm.box = "bento/ubuntu-16.04"
      node.vm.hostname = "#{name}"
      node.vm.network "private_network", ip: "192.168.33.5#{num}"
      node.vm.network :forwarded_port, guest: 22, host: "222#{num}", id: "ssh", auto_correct: true
      # for convenience, use a common key so chef-apply can be run across multiple VMs
      node.ssh.private_key_path = ["~/.vagrant.d/insecure_private_key"]
      node.ssh.insert_key = false
      node.vm.provider "virtualbox" do |v|
        # Keep these light, we're not really using them except to
        # run chef client
        v.memory = 512
        v.cpus = 1
        # Allow host caching - many images don't have it by default but it significantly speeds up
        # disk IO (such as installing chef via dpkg)
        v.customize ["storagectl", :id, "--name", "SATA Controller", "--hostiocache", "on"]
        # disable logging client console on host
        v.customize ["modifyvm", :id, "--uartmode1", "disconnected"]
      end
      node.vm.provision "shell", inline: "echo 'MaxAuthTries 25' >> /etc/ssh/sshd_config"
      node.vm.provision "shell", inline: "service sshd restart"
    end
  end

  config.vm.define "windows1" do |node|
    node.vm.box = "tas50/windows_2016"
    node.vm.communicator = "winrm"

    # Admin user name and password
    node.winrm.username = "vagrant"
    node.winrm.password = "vagrant"

    node.vm.guest = :windows
    node.windows.halt_timeout = 15

    node.vm.network "private_network", ip: "192.168.33.61"
    node.vm.network :forwarded_port, guest: 3389, host: 3389, id: "rdp", auto_correct: true
    node.vm.network :forwarded_port, guest: 22, host: 2231, id: "ssh", auto_correct: true

    node.vm.provider :virtualbox do |v, override|
      # v.gui = true
      v.customize ["modifyvm", :id, "--memory", 2048]
      v.customize ["modifyvm", :id, "--cpus", 2]
      v.customize ["setextradata", "global", "GUI/SuppressMessages", "all" ]
    end
  end

  config.vm.define "macosx-test" do |node|

    # config.vm.define "macosx-test"
    node.vm.box = "yzgyyang/macOS-10.14"
    # config.ssh.private_key_path = ["~/.vagrant.d/insecure_private_key"]
    # Use NFS for the shared folder
    node.vm.synced_folder ".", "/vagrant",
      id: "core",
      nfs: true,
      mount_options: ["nolock,vers=3,udp,noatime,actimeo=1,resvport"],
    export_options: ["async,insecure,no_subtree_check,no_acl,no_root_squash"]

    # NFS needs host-only network
    node.vm.network :private_network, ip: "172.16.2.42"
    # config.vm.network :forwarded_port, guest: 22, host: "2232", id: "ssh", auto_correct: true

    node.vm.provider :virtualbox do |virtualbox|
      virtualbox.name = "macosx-test"
      virtualbox.memory = 4096
      virtualbox.cpus = 2

      # Show gui, incl. some power
      virtualbox.gui = true

      # Some needed OSX configs
      virtualbox.customize ["modifyvm", :id, "--cpuid-set", "00000001", "000106e5", "00100800", "0098e3fd", "bfebfbff"]
      virtualbox.customize ["setextradata", :id, "VBoxInternal/Devices/efi/0/Config/DmiSystemProduct", "MacBookPro11,3"]
      virtualbox.customize ["setextradata", :id, "VBoxInternal/Devices/efi/0/Config/DmiSystemVersion", "1.0"]
      virtualbox.customize ["setextradata", :id, "VBoxInternal/Devices/efi/0/Config/DmiBoardProduct", "Iloveapple"]
      virtualbox.customize ["setextradata", :id, "VBoxInternal/Devices/smc/0/Config/DeviceKey", "ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"]
      virtualbox.customize ["setextradata", :id, "VBoxInternal/Devices/smc/0/Config/GetKeyFromRealSMC", "1"]

      # set resolution on OSX:
      # 0,1,2,3,4,5 :: 640x480, 800x600, 1024x768, 1280x1024, 1440x900, 1920x1200
      virtualbox.customize ["setextradata", :id, "VBoxInternal2/EfiGopMode", "4"]
    end
  end
end
