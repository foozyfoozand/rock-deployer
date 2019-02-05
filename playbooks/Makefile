SHELL=/bin/bash

# Confirm Ansible is installed.
CHECK := $(shell command -v ansible-playbook 2> /dev/null)
INVENTORY ?= 'inventory.yml'
PLAYBOOK ?= 'site.yml'

.PHONY: kickstart profiles setup registry dnsmasq generate-profiles clonerepos-centos clonerepos-rhel

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

registry:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,registry

generate-profiles:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t preflight,kickstart,profiles

pull-docker-images:
	ansible-playbook $(PLAYBOOK) -i $(INVENTORY) -t pull-docker-images

bootstrap:		
	@echo $(TFPLENUM_OS_TYPE)	
	@echo $(TFPLENUM_SERVER_IP)
	@echo $(RHEL_SOURCE_REPO)

	$(if $(filter $(TFPLENUM_OS_TYPE),Centos),\
	ansible-playbook $(PLAYBOOK) -i localhost -e '{ RHEL_SOURCE_REPO: "None" }' -e '{ server_ip: "$(TFPLENUM_SERVER_IP)" }' -t bootstrap,\
	ansible-playbook $(PLAYBOOK) -i localhost -e '{ RHEL_SOURCE_REPO: "$(RHEL_SOURCE_REPO)" }' -e '{ server_ip: "$(TFPLENUM_SERVER_IP)" }' -t bootstrap)
