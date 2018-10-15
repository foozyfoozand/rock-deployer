#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PACKAGES="git vim net-tools wget ansible"

# Default to repos for now
export TFPLENUM_BOOTSTRAP_TYPE=repos

pushd "/opt" > /dev/null

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or use sudo."
  exit
fi

REPOS=("tfplenum-frontend" "tfplenum" "tfplenum-deployer" "tfplenum-integration-testing")

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
        echo "Do you want to use labrepo for downloads? (Requires Dev Network)"
        select cr in "YES" "NO"; do
            case $cr in
                YES ) export TFPLENUM_LABREPO=true; break;;
                NO ) export TFPLENUM_LABREPO=false; break;;
            esac
        done
    fi

    if [ "$TFPLENUM_LABREPO" == true ]; then
        local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
        rm -rf /etc/yum.repos.d/*offline* > /dev/null
        rm -rf /etc/yum.repos.d/labrepo* > /dev/null
        if [ "$os_id" == '"centos"' ]; then
            run_cmd curl -m 10 -s -o /etc/yum.repos.d/labrepo-centos.repo http://yum.labrepo.lan/labrepo-centos.repo
        else
            run_cmd curl -m 10 -s -o /etc/yum.repos.d/labrepo-rhel.repo http://yum.labrepo.lan/labrepo-rhel.repo
        fi    
        yum clean all > /dev/null
        rm -rf /var/cache/yum/ > /dev/null
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

#if [ -z "$TFPLENUM_BOOTSTRAP_TYPE" ]; then
#    echo "How do you want to bootstrap your controller?"
#    select cr in "REPOS" "RPMs"; do
#        case $cr in
#            REPOS ) export TFPLENUM_BOOTSTRAP_TYPE=repos; break;;
#            RPMs ) export TFPLENUM_BOOTSTRAP_TYPE=rpms; break;;
#        esac
#    done
#fi

function set_git_variables() {    
    if [ $TFPLENUM_BOOTSTRAP_TYPE == 'repos' ]; then
        if [ -z "$DIEUSERNAME" ]; then
            read -p "DI2E Username: "  DIEUSERNAME
        fi

        if [ -z "$PASSWORD" ]; then
            while true; do
                read -s -p "DI2E Password: " PASSWORD
                echo
                read -s -p "DI2E Password (again): " PASSWORD2
                echo
                [ "$PASSWORD" = "$PASSWORD2" ] && break
                echo "The passwords do not match.  Please try again."
            done
        fi        
    fi

    if [ $TFPLENUM_BOOTSTRAP_TYPE == 'repos' ]; then
        if [ -z "$BRANCH_NAME" ]; then
            echo "WARNING: Any existing tfplenum directories in /opt will be removed."
            echo "Which branch do you want to checkout for all repos?"
            select cr in "Master" "Devel" "Custom"; do
                case $cr in
                    Master ) export BRANCH_NAME=master; break;;
                    Devel ) export BRANCH_NAME=devel; break;;
                    Custom ) export BRANCH_NAME=custom; break;;
                esac
            done

            if [ $BRANCH_NAME == 'custom' ]; then
                echo "Please type the name of the custom branch exactly. It is important to note that this branch will 
                be checked out accross all repos pulled so if the branch doe not exist in each repo pulled, 
                boostraping the system will fail."

                read -p "Branch Name: " BRANCH_NAME
                export BRANCH_NAME=$BRANCH_NAME
            fi
        fi
    fi
}

function clone_repos(){        
    for i in ${REPOS[@]}; do
        local directory="/opt/$i"
        if [ -d "$directory" ]; then
            rm -rf $directory
        fi
        if [ ! -d "$directory" ]; then
            git clone https://$DIEUSERNAME:$PASSWORD@bitbucket.di2e.net/scm/thisiscvah/$i.git
            pushd $directory > /dev/null
            git checkout $BRANCH_NAME
            git remote set-url origin https://bitbucket.di2e.net/scm/thisiscvah/$i.git
            git config --global --unset credential.helper
            popd > /dev/null
        fi
    done
}

function bootstrap_repos(){
    clone_repos
    run_cmd /opt/tfplenum-frontend/setup/setup.sh
}

function _install_and_start_mongo40 {
    if [ "$TFPLENUM_LABREPO" == false ]; then
cat <<EOF > /etc/yum.repos.d/mongodb-org-4.0.repo
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
EOF
    fi

	run_cmd yum install -y mongodb-org
	run_cmd systemctl enable mongod
}

# function bootstrap_rpms(){    
#     _install_and_start_mongo40
#     #run_cmd curl -o tfplenum-3.2.1-23.x86_64.rpm http://yum.labrepo.lan/tfplenum/latest/tfplenum-3.2.1-23.x86_64.rpm
#     #run_cmd curl -o tfplenum-deployer-3.2.1-23.x86_64.rpm http://yum.labrepo.lan/THISISCVAH-RPMS/tfplenum-deployer-3.2.1-23.x86_64.rpm
#     #run_cmd curl -o tfplenum-frontend-3.2.1-23.x86_64.rpm http://yum.labrepo.lan/THISISCVAH-RPMS/tfplenum-frontend-3.2.1-23.x86_64.rpm
#     if [ "$TFPLENUM_LABREPO" == true ]; then
#         run_cmd yum -y install tfplenum*
        
#     fi
# }

function subscription_prompts(){
    if [ "$TFPLENUM_LABREPO" == false ]; then
        subscription_status=`subscription-manager status | grep 'Overall Status:' | awk '{ print $3 }'`
            
        if [ "$subscription_status" != 'Current' ]; then
                    
            if [ -z "$RHEL_ORGANIZATION" ]; then
                read -p 'Please enter your RHEL org number (EX: Its the --org flag for the subscription-manager command): ' orgnumber
                export RHEL_ORGANIZATION=$orgnumber
            fi
                
            if [ -z "$RHEL_ACTIVATIONKEY" ]; then
                read -p 'Please enter your RHEL activation key (EX: Its the --activationkey flag for the subscription-manager command): ' activationkey
                export RHEL_ACTIVATIONKEY=$activationkey
            fi
        fi
    fi
}

function execute_pre(){
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)    

    if [ "$os_id" == '"centos"' ]; then
        echo "Bootstrapping Centos"
        run_cmd yum -y install epel-release
        run_cmd yum -y update
        run_cmd yum -y install $PACKAGES
    else
        echo "Bootstrapping Rhel"
        if [ "$TFPLENUM_LABREPO" == false ]; then        
            subscription-manager register --activationkey=$RHEL_ACTIVATIONKEY --org=$RHEL_ORGANIZATION
        
            run_cmd curl -s -o epel-release-latest-7.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            rpm -ivh epel-release-latest-7.noarch.rpm
        else
            run_cmd curl -s -o epel-release-latest-7.noarch.rpm http://misc.labrepo.lan/epel-release-latest-7.noarch.rpm
            rpm -e epel-release-latest-7.noarch.rpm
            yum remove epel-release -y
        fi
                
        run_cmd yum -y update
        run_cmd yum -y install $PACKAGES
    fi
}

function execute_bootstrap_playbook(){
    pushd "/opt/tfplenum-deployer/playbooks" > /dev/null
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    if [ "$os_id" == '"centos"' ]; then
        export TFPLENUM_OS_TYPE=Centos
    else
        export TFPLENUM_OS_TYPE=RedHat
    fi 

    make bootstrap
    popd > /dev/null
}

function prompts(){
    clear
    echo "---------------------------"
    echo "TFPLENUM DEPLOYER BOOTSTRAP"
    echo "---------------------------"
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    get_controller_ip
    use_laprepos
    if [ "$os_id" == '"rhel"' ]; then
        subscription_prompts
    fi
    if [ $TFPLENUM_BOOTSTRAP_TYPE == 'repos' ]; then
        set_git_variables
    fi

}

prompts
clear
execute_pre

if [ $TFPLENUM_BOOTSTRAP_TYPE == 'repos' ]; then    
    bootstrap_repos
# else
#     bootstrap_rpms
fi
clear
execute_bootstrap_playbook

popd > /dev/null