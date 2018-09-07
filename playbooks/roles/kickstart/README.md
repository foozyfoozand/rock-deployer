Role Name
=========

This role is to automate the configuration of a kickstart server for RPM-based (rhel,centos) operating systems.

Requirements
------------

The user of this role will need access to the installation iso file and will need to copy it to the target node.

Role Variables
--------------

The settable variables for this role are in defaults/main.yml
```
The absolute path to the installation .iso file. ex: /root/rhel-7-server-x86_64.iso
iso_path: 

Remove the iso from the system? Override to "true" to keep.
keep_iso: false

Keep local yum repo or delete it? Override to "true" to keep.
keep_repo: false

Keep iso mounted? Override to "true" to keep.
keep_mnt: false
```
If you would like to configure DHCP services, set this to "true"; Please note that the subnet used during DHCP scope creation is the default IPv4 address (eth0) of the target system. For example, if your eth0 network information is 192.168.124.200/24, DHCP will be configured for 192.168.124.0/255.255.255.0. To override you will need to update server_ip, dhcp_net and dhcp_mask variables.
```
dhcp: false

If DHCP is enabled, define the starting IP address of the scope.
dhcp_start:

If DHCP is enabled, define the last IP address of the scope.
dhcp_end:
```
Dependencies
------------

A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: kickstart }

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).
