chef-run/chef-apply is a tool to execute ad-hoc tasks on one or more target nodes using Chef Infra Client. To start with, familiarize yourself with chef-run’s arguments and flags by running chef-run -h
link https://docs.chef.io/workstation/chef_run/

## general development process :

1. Fork this repo and clone it to your workstation.
2. Create a feature branch for your change.
3. Write code and tests.
4. Push your feature branch to GitHub and open a pull request against master.

## General development setup

clone from - https://github.com/chef/chef-apply.git

**With vagrant box**
1) repo contains vagrantfile with machines like ubuntu, windows, mac. you need to have vagrant and virtualmachine preinstalled
2) make sure to add machine in host file e.g (in cat /etc/hosts add - 127.0.0.1 ubuntu1)
3) vagrant status to check status of virtual box created
4) vagrant up MACHINENAME
5) once machine is up run this command -- bundle exec chef-run ssh://vagrant@ubuntu1:2235 directory /tmp/foo --identity-file ~/.vagrant.d/insecure_private_key
   bundle exec is ruby command for running from current project rather than installed tool.

this will install chef client on desired platform using chef apply

to suspend vagrant machine use command - vagrant suspend solaris4


**Using instance**

1)bundle exec chef-run ssh://test@ipaddress directory /tmp/foo --password mypassword



Here is some prerunned use case, and interim statuses that chef-run displays.

$ chef-run ssh://my_user@host1:2222 directory /tmp/foo --identity-file ~/.ssh/id_rsa user test1 action=create
[✔] Packaging cookbook... done!
[✔] Generating local policyfile... exporting... done!
[✔] Applying user[test1] from resource to target.
└── [✔] [my_user] Successfully converged user[test1].
%
√ ~ $ chef-run ssh://my_user@host1:2222 directory /tmp/foo --identity-file ~/.ssh/id_rsa user test1 action=delete
[✔] Packaging cookbook... done!
[✔] Generating local policyfile... exporting... done!
[✖] Applying user[test1] from resource to target.
└── [✖] [my_user] Failed to converge user[test1].

The action 'delete' is not valid.

Valid actions are:

  :nothing, :create, :remove, :modify, :manage, :lock, :unlock

For more information, please consult the documentation
for this resource:

  https://docs.chef.io/resource_reference.html
%
?1 ~ $ chef-run ssh://my_user@host1:2222 directory /tmp/foo --identity-file ~/.ssh/id_rsa user test1 action=remove
[✔] Packaging cookbook... done!
[✔] Generating local policyfile... exporting... done!
[✔] Applying user[test1] from resource to target.
└── [✔] [my_user] Successfully converged user[test1].


**To run test use rspec ex- bundle exec rspec spec/unit/target_host_spec.rb**

**To debug, user byebug**

