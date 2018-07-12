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
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY)

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
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -e '{ offline: false }' -t preflight,harbor

generate-profiles:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,kickstart,profiles

clonerepos-centos:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -e '{ offline: false}' -e '{ pull_centos_repos: true }' -e '{ pull_additional_repos: true }' -t preflight,setup,clonerepo 
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -e '{ offline: true }' -t preflight,setup

clonerepos-rhel:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -e '{ offline: false}' -e '{ pull_rhel_repos: true }' -e '{ pull_additional_repos: true }' -t preflight,setup,clonerepo 
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -e '{ offline: true }' -t preflight,setup