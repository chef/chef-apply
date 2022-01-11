# Development Docs

chef-run/chef-apply is a tool to execute ad-hoc tasks on one or more target nodes using Chef Infra Client. To start with, familiarize yourself with chef-run’s arguments and flags by running chef-run -h
link <https://docs.chef.io/workstation/chef_run/>

## Development process

1. Fork this repo and clone it to your development system.
1. Create a feature branch for your change.
1. Write code and tests.
1. Push your feature branch to GitHub and open a pull request.

## Development setup

### With Vagrant box

1. This repository contains a Vagrantfile with machines; Ubuntu, Windows, MacOS. You need to have Vagrant and VirtualBox preinstalled
1. Make sure to add machine in host file e.g (in  /etc/hosts add - 127.0.0.1 ubuntu1)
1. `vagrant status` to check status of VirtualBox created
1. `vagrant up MACHINENAME`
1. Once machine is up, run this command format( based on user,port, and machine name)

   ```shell
   bundle exec chef-run ssh://vagrant@ubuntu1:2235 directory /tmp/foo --identity-file ~/.vagrant.d/insecure_private_key
   ```

This will install chef client on desired platform using chef-apply
To suspend a Vagrant machine use

  ```shell
  vagrant suspend MACHINENAME
  ```

### With instance

```shell
bundle exec chef-run ssh://test@ipaddress directory /tmp/foo --password mypassword
```

**Here is some pre-run use cases, and interim statuses that chef-run displays.**

```shell
bundle exec chef-run ssh://my_user@host1:2222 directory /tmp/foo --identity-file ~/.ssh/id_rsa user test1 action=create
```

```shell
[✔] Packaging cookbook... done!
[✔] Generating local policyfile... exporting... done!
[✔] Applying user[test1] from resource to target.
└── [✔] [my_user] Successfully converged user[test1].
```

Valid actions are:

  :nothing, :create, :remove, :modify, :manage, :lock, :unlock

For more information, please consult the documentation for this resource:
  <https://docs.chef.io/resources>

```shell
bundle exec chef-run ssh://my_user@host1:2222 directory /tmp/foo --identity-file ~/.ssh/id_rsa user test1 action=remove
```

```shell
[✔] Packaging cookbook... done!
[✔] Generating local policyfile... exporting... done!
[✔] Applying user[test1] from resource to target.
└── [✔] [my_user] Successfully converged user[test1].
```

* To run test use rspec e.g. ```bundle exec rspec spec/unit/target_host_spec.rb```

* To debug, use byebug
