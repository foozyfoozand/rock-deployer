SHELL=/bin/bash

# Confirm Ansible is installed.
CHECK := $(shell command -v ansible-playbook 2> /dev/null)
INVENTORY ?= 'inventory.yml'
PLAYBOOK ?= 'site.yml'

.PHONY: kickstart profiles setup harbor harbor-online-sync dnsmasq generate-profiles clonerepos-centos clonerepos-rhel

# Default target, build *and* run tests
all:
ifndef CHECK
	$(error Ansible is not installed. Install Ansible with 'yum update -y && yum install -y ansible')
endif
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,setup,dnsmasq,kickstart,profiles

dnsmasq:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,dnsmasq

kickstart:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,kickstart

profiles:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,profiles

setup:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,setup

harbor:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,harbor

harbor-online-sync:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,harbor

generate-profiles:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,kickstart,profiles

bootstrap:		
	@echo $(TFPLENUM_OS_TYPE)
	@echo $(TFPLENUM_REDHAT_SUBSCRIPTION)

	$(if $(filter $(TFPLENUM_OS_TYPE),Centos),\
	ansible-playbook $(PLAYBOOK) -i localhost -e '{ pull_centos_repos: true }' -e '{ pull_rhel_repos: false }' -e '{ server_ip: "$(TFPLENUM_SERVER_IP)" }' -t bootstrap,\
	ansible-playbook $(PLAYBOOK) -i localhost -e '{ pull_centos_repos: false }' -e '{ pull_rhel_repos: true }' -e '{ server_ip: "$(TFPLENUM_SERVER_IP)" }' -t bootstrap)
