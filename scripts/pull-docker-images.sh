#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

pushd "/opt" > /dev/null

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or use sudo."
  exit
fi

function run_cmd {
	local command="$@"
	eval $command
	local ret_val=$?
	if [ $ret_val -ne 0 ]; then
		echo "$command returned error code $ret_val"
        exit 1
	fi	
}

function use_laprepos() {
    if [ -z "$TFPLENUM_LABREPO" ]; then
        echo "Select a docker registry to use:"
        select cr in "docker.labrepo.lan" "docker.io"; do
            case $cr in
                docker.labrepo.lan ) export TFPLENUM_LABREPO=true; break;;
                docker.io ) export TFPLENUM_LABREPO=false; break;;
            esac
        done
    fi
}

function get_controller_ip() {
    if [ -z "$TFPLENUM_SERVER_IP" ]; then
        while true; do
            read -p "Enter the controller's ip address: " SERVER_IP
            run_cmd ip a | grep $SERVER_IP > /dev/null
            retVal=$?
            if [ "$retVal" == 0 ]; then
              export TFPLENUM_SERVER_IP=$SERVER_IP
              break
            else
              echo "Error Unable to locate network interface with specified ip address. Verify the interface is configured correctly."
            fi
        done
    fi
}

function execute_playbook(){
    pushd "/opt/tfplenum-deployer/playbooks" > /dev/null
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    if [ "$os_id" == '"centos"' ]; then
        export TFPLENUM_OS_TYPE=Centos
    else
        export TFPLENUM_OS_TYPE=RedHat
    fi 

    make pull-docker-images
    popd > /dev/null
}

use_laprepos
get_controller_ip
execute_playbook
