#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PACKAGES="vim net-tools wget ansible-2.6.2-1.el7"

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

function labrepo_available() {
    echo "-------"
    echo "Checking if labrepo is available..."    
    labrepo_check=`curl -m 10 -s http://labrepo.lan/check.html`    
    if [ "$labrepo_check" != true ]; then
      echo "Warning: Labrepo not found. Defaulting to public repos."
      echo "Labrepo requires Dev Network.  This is not a fatal error and can be ignored."
      labrepo_check=false
    fi    
}

function prompt_runtype() {
    echo "What type of run you do want to do?"
    echo "Full: A full run will remove tfplenum directories in /opt, reclone tfplenum git repos and runs boostrap ansible role."    
    echo "Boostrap: Only runs boostrap ansible role."
    echo "Docker Images: Repull docker images to controller and upload to controllers docker registry."
    if [ -z "$RUN_TYPE" ]; then
        select cr in "Full" "Bootstrap" "Docker Images"; do
            case $cr in
                Full ) export RUN_TYPE=full; break;;
                Bootstrap ) export RUN_TYPE=bootstrap; break;;
                "Docker Images" ) export RUN_TYPE=dockerimages; break;;
            esac
        done
    fi
}

function use_laprepos() {
    labrepo_available
    if [ "$labrepo_check" == true ]; then
        if [ -z "$TFPLENUM_LABREPO" ]; then
            echo "-------"
            echo "Do you want to use labrepo for downloads? (Requires Dev Network)"
            select cr in "YES" "NO"; do
                case $cr in
                    YES ) export TFPLENUM_LABREPO=true; break;;
                    NO ) export TFPLENUM_LABREPO=false; break;;
                esac
            done
        fi
        if [ "$TFPLENUM_LABREPO" == true ]; then
          sync_repos
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
    else
      echo "-------"
      echo "Warning: Labrepo not found. Defaulting to public repos."
      echo "Labrepo requires Dev Network.  This is not a fatal error and can be ignored."
      export TFPLENUM_LABREPO=false
    fi
}

function sync_repos() {        
    if [ -z "$CLONE_REPOS" ]; then
        echo "-------"
        echo "Do you want to sync or proxy the yum repositories?"
        echo "Sync: Downloading the yum reposities can take about 1-2 hours and requires 200GBs of storage."
        echo "Proxy: Yum reposities will be proxied to labrepo.  The rpms will not be downloaded to the controller."
        
        select cr in "Sync" "Proxy"; do
            case $cr in
                Sync ) export CLONE_REPOS=true; break;;
                Proxy ) export CLONE_REPOS=false; break;;
            esac
        done
    fi
}

function get_controller_ip() {
    if [ -z "$TFPLENUM_SERVER_IP" ]; then
        controller_ips=`ip -o addr | awk '!/^[0-9]*: ?lo|inet6|docker|link\/ether/ {gsub("/", " "); print $4}'`
        choices=( $controller_ips )
        echo "-------"
        echo "Select your controllers ip address:"
        select cr in "${choices[@]}"; do
            case $cr in
                $cr ) export TFPLENUM_SERVER_IP=$cr; break;;
            esac
        done
    fi
}

function set_git_variables() {
    if [ -z "$DIEUSERNAME" ]; then
        echo "-------"
        echo "Bootstrapping a controller requires DI2E credentials."
        read -p "DI2E Username: "  DIEUSERNAME
        export GIT_USERNAME=$DIEUSERNAME
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
        export GIT_PASSWORD=$PASSWORD
    fi

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
}

function clone_repos(){
    for i in ${REPOS[@]}; do
        local directory="/opt/$i"
        if [ -d "$directory" ]; then
            rm -rf $directory
        fi
        if [ ! -d "$directory" ]; then
            git clone https://bitbucket.di2e.net/scm/thisiscvah/$i.git
            pushd $directory > /dev/null
            git checkout $BRANCH_NAME
            git remote set-url origin https://bitbucket.di2e.net/scm/thisiscvah/$i.git

            popd > /dev/null
        fi
    done
}

function setup_frontend(){
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

function subscription_prompts(){
    if [ "$TFPLENUM_LABREPO" == false ]; then
        echo "-------"
        echo "Since you are running a RHEL controller outside the Dev Network and/or not using Labrepo, "
        echo "You will need to subscribe to RHEL repositories."
        echo "-------"
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

function setup_git(){
  if ! rpm -q git > /dev/null 2>&1 ; then
    yum install git -y > /dev/null 2>&1
  fi
git config --global --unset credential.helper
cat <<EOF > ~/credential-helper.sh
#!/bin/bash
echo username="\$GIT_USERNAME"
echo password="\$GIT_PASSWORD"
EOF
  git config --global credential.helper "/bin/bash ~/credential-helper.sh"
}

function check_ansible(){
  if rpm -q ansible > /dev/null 2>&1 ; then
    yum remove ansible -y > /dev/null 2>&1
  fi
}

function execute_pre(){
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)

    if [ "$os_id" == '"centos"' ]; then
        echo "Bootstrapping Centos"
        if [ "$TFPLENUM_LABREPO" == false ]; then
            run_cmd yum -y install epel-release
          else
            run_cmd curl -s -o epel-release-latest-7.noarch.rpm http://misc.labrepo.lan/epel-release-latest-7.noarch.rpm
            rpm -e epel-release-latest-7.noarch.rpm
            yum remove epel-release -y
        fi
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

function set_os_type(){
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    if [ "$os_id" == '"centos"' ]; then
        export TFPLENUM_OS_TYPE=Centos        
    else
        export TFPLENUM_OS_TYPE=RedHat        
    fi 
}

function execute_bootstrap_playbook(){
    pushd "/opt/tfplenum-deployer/playbooks" > /dev/null    
    make bootstrap
    popd > /dev/null
}

function execute_pull_docker_images_playbook(){
    pushd "/opt/tfplenum-deployer/playbooks" > /dev/null
    make pull-docker-images
    popd > /dev/null
}

function prompts(){    
    echo "---------------------------"
    echo "TFPLENUM DEPLOYER BOOTSTRAP"
    echo "---------------------------"
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    prompt_runtype
    get_controller_ip
    use_laprepos
    if [ "$os_id" == '"rhel"' ]; then
        subscription_prompts
    fi
    if [ $RUN_TYPE == 'full' ]; then
        set_git_variables
    fi

}

export BOOTSTRAP=true
prompts
set_os_type

if [ $RUN_TYPE == 'full' ]; then
    setup_git
    check_ansible
    clone_repos
    git config --global --unset credential.helper
    execute_pre    
    setup_frontend
fi

if [ $RUN_TYPE == 'bootstrap' ]; then
    check_ansible
    execute_pre
fi

if [ $RUN_TYPE == 'bootstrap' ] || [ $RUN_TYPE == 'full' ]; then
    execute_bootstrap_playbook
fi

if [ $RUN_TYPE == 'dockerimages' ]; then
    execute_pull_docker_images_playbook
fi

popd > /dev/null