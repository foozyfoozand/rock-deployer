#!/bin/bash
boostrap_version=1.2.0
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PACKAGES="vim net-tools wget"
EPEL_RPM_PUBLIC_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
ANSIBLE_VERSION="2.7.5"
RHEL_VERSION="7.5"
RHEL_ISO="rhel-server-$RHEL_VERSION-x86_64-dvd.iso"
export TFPLENUM_LABREPO=false

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
    echo "Select a run type:"
    echo "Full: Fresh Builds, Home Builds, A full run will remove tfplenum directories in /opt, reclone tfplenum git repos and runs boostrap ansible role."
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

function check_rhel_iso(){
    echo "Checking for RHEL ISO..."
    rhel_iso_exists=false
    if [ -f /root/$RHEL_ISO ]; then
        rhel_iso_exists=true
        echo "RHEL ISO found! Moving on..."
    fi
}

function prompt_rhel_iso_download() {
    check_rhel_iso
    if [ "$rhel_iso_exists" == false ]; then
        echo "-------"
        
        echo "RHEL ISO is required to setup the kit."
        echo "Download the RHEL ISO following these instructions:"
        echo "***If you already have the $RHEL_ISO skip to step 6.***"
        echo ""        
        echo "1. In a browser navgiate to https://access.redhat.com/downloads"
        echo "2. Select Red Hat Enterprise Linux."
        echo "3. Login using your Red Hat user/pass."
        echo "4. Select $RHEL_VERSION from the Versions dropdown."
        echo "5. Select Download for Red Hat Enterprise Linux $RHEL_VERSION Binary DVD."
        echo "6. SCP $RHEL_ISO to /root on your controller."
        
        while true; do
        read -p "Have you completed the above steps? (Y/N): " rhel_iso_prompted

        if [[ $rhel_iso_prompted =~ ^[Yy]$ ]]; then
            check_rhel_iso
            echo "rhel_iso_exists: $rhel_iso_exists"
            if [ "$rhel_iso_exists" == true ]; then
                break
            fi
        fi
        echo "Unable to find rhel iso please try again."
        done
    fi
}

function choose_rhel_yum_repo() {
    labrepo_available
    if [ "$labrepo_check" == true ] ; then
        if [ -z "$RHEL_SOURCE_REPO" ]; then
            echo "-------"            
            echo "Select the source rhel yum server to use:"
            echo "Labrepo: Requires dev network"
            echo "Public: Requires internet access"
            select cr in "Labrepo" "Public"; do
                case $cr in
                    Labrepo )                    
                    export RHEL_SOURCE_REPO="labrepo";
                    break                    
                    ;;
                    Public )
                    export RHEL_SOURCE_REPO="public";
                    break
                    ;;
                esac
            done
        fi
    else
        export RHEL_SOURCE_REPO="public";
    fi
}

function subscription_prompts(){    
    echo "Verifying RedHat Subscription..."
    subscription_status=`subscription-manager status | grep 'Overall Status:' | awk '{ print $3 }'`

    if [ "$subscription_status" != "Current" ]; then
        echo "-------"
        echo "Since you are running a RHEL controller outside the Dev Network and/or not using Labrepo, "
        echo "You will need to subscribe to RHEL repositories."
        echo "-------"        
        echo "Select RedHat subscription method:"
        echo "Standard: Requires Org + Activation Key"
        echo "RedHat Developer Login: A RedHat Developer account is free signup here https://developers.redhat.com/"
        echo "RedHat Developer License cannot be used in production environments"
        select cr in "Standard" "RedHat Developer" ; do
                case $cr in
                    Standard )                    
                    export RHEL_SUB_METHOD="standard";
                    break                    
                    ;;
                    "RedHat Developer" )
                    export RHEL_SUB_METHOD="developer";
                    break
                    ;;
                esac
            done
        while true; do
            subscription-manager remove --all
            subscription-manager unregister
            subscription-manager clean            

            if [ "$RHEL_SUB_METHOD" == "standard" ]; then
                if [ -z "$RHEL_ORGANIZATION" ]; then
                    read -p 'Please enter your RHEL org number (EX: Its the --org flag for the subscription-manager command): ' orgnumber
                    export RHEL_ORGANIZATION=$orgnumber
                fi

                if [ -z "$RHEL_ACTIVATIONKEY" ]; then
                    read -p 'Please enter your RHEL activation key (EX: Its the --activationkey flag for the subscription-manager command): ' activationkey
                    export RHEL_ACTIVATIONKEY=$activationkey
                fi               
                subscription-manager register --activationkey=$RHEL_ACTIVATIONKEY --org=$RHEL_ORGANIZATION --force
            elif [ "$RHEL_SUB_METHOD" == "developer" ]; then
                subscription-manager register
            fi

            subscription-manager refresh
            subscription-manager attach --auto
            echo "Checking subscription status..."
            subscription_status=`subscription-manager status | grep 'Overall Status:' | awk '{ print $3 }'`
            
            if [ "$subscription_status" == "Current" ]; then
                break;
            else
                echo "Error subscription appears to be invalid please try again..."
            fi
        done;

    fi

    if [ "$subscription_status" == "Current" ]; then
        subscription-manager repos --enable rhel-7-server-rpms
        subscription-manager repos --enable rhel-7-server-extras-rpms
        subscription-manager repos --enable rhel-7-server-optional-rpms
        prompt_rhel_iso_download
    fi


}

function centos_default_repos(){
    cat <<EOF > /etc/yum.repos.d/CentOS-Base.repo
# CentOS-Base.repo
#
# The mirror system uses the connecting IP address of the client and the
# update status of each mirror to pick mirrors that are updated to and
# geographically close to the client.  You should use this for CentOS updates
# unless you are manually picking other mirrors.
#
# If the mirrorlist= does not work for you, as a fall back you can try the
# remarked out baseurl= line instead.
#
#

[base]
name=CentOS-\$releasever - Base
mirrorlist=http://mirrorlist.centos.org/?release=\$releasever&arch=\$basearch&repo=os&infra=\$infra
#baseurl=http://mirror.centos.org/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#released updates
[updates]
name=CentOS-\$releasever - Updates
mirrorlist=http://mirrorlist.centos.org/?release=\$releasever&arch=\$basearch&repo=updates&infra=\$infra
#baseurl=http://mirror.centos.org/centos/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that may be useful
[extras]
name=CentOS-\$releasever - Extras
mirrorlist=http://mirrorlist.centos.org/?release=\$releasever&arch=\$basearch&repo=extras&infra=\$infra
#baseurl=http://mirror.centos.org/centos/\$releasever/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-\$releasever - Plus
mirrorlist=http://mirrorlist.centos.org/?release=\$releasever&arch=\$basearch&repo=centosplus&infra=\$infra
#baseurl=http://mirror.centos.org/centos/\$releasever/centosplus/\$basearch/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
}

function setup_ansible(){
cat <<EOF > /etc/yum.repos.d/ansible.repo
[ansible]
baseurl=https://releases.ansible.com/ansible/rpm/release/epel-7-x86_64/
enable=1
gpgcheck=0
name=ansible
EOF

yum install --enablerepo=ansible ansible-$ANSIBLE_VERSION -y

}


function generate_repo_file() {
    rm -rf /etc/yum.repos.d/*.repo > /dev/null

    if [ "$RHEL_SOURCE_REPO" == "labrepo" ] && [ "$TFPLENUM_OS_TYPE" == "rhel" ]; then
cat <<EOF > /etc/yum.repos.d/labrepo-rhel.repo
[rhel-7-server-extras-rpms]
name=labrepos rhel-7-server-extras-rpms
baseurl=http://yum.labrepo.lan/rhel/rhel-7-server-extras-rpms
enabled=1
gpgcheck=0

[rhel-7-server-optional-rpms]
name=labrepos rhel-7-server-extras-rpms
baseurl=http://yum.labrepo.lan/rhel/rhel-7-server-optional-rpms
enabled=1
gpgcheck=0

[rhel-7-server-rpms]
name=labrepos rhel-7-server-extras-rpms
baseurl=http://yum.labrepo.lan/rhel/rhel-7-server-rpms
enabled=1
gpgcheck=0
EOF

    elif [ "$RHEL_SOURCE_REPO" == "public" ] && [ "$TFPLENUM_OS_TYPE" == "rhel" ]; then
        subscription_prompts
    elif [ "$TFPLENUM_OS_TYPE" == "centos" ]; then
        centos_default_repos
    fi

    yum clean all > /dev/null
    rm -rf /var/cache/yum/ > /dev/null    
}

function get_controller_ip() {
    if [ -z "$TFPLENUM_SERVER_IP" ]; then
        controller_ips=`ip -o addr | awk '!/^[0-9]*: ?lo|inet6|docker|link\/ether/ {gsub("/", " "); print $4}'`
        choices=( $controller_ips )
        echo "-------"
        echo "Select the controllers ip address:"
        select cr in "${choices[@]}"; do
            case $cr in
                $cr ) export TFPLENUM_SERVER_IP=$cr; break;;
            esac
        done
    fi
}

function prompt_di2e_creds() {
    if [ -z "$DIEUSERNAME" ]; then
        echo "-------"
        echo "Bootstrapping a controller requires DI2E credentials."
        while true; do
            read -p "DI2E Username: "  DIEUSERNAME
            if [ "$DIEUSERNAME" == "" ]; then
                echo "The username cannot be empty.  Please try again."            
            elif [ "$DIEUSERNAME" != "" ]; then
                export GIT_USERNAME=$DIEUSERNAME
                break
            fi
        done
    fi

    if [ -z "$PASSWORD" ]; then
        while true; do
            read -s -p "DI2E Password: " PASSWORD
            echo
            if [ "$PASSWORD" == "" ]; then
                echo "The passwords cannot be empty.  Please try again."
            else                
                read -s -p "DI2E Password (again): " PASSWORD2
            fi            

            if [ "$PASSWORD" != "$PASSWORD2" ]; then                
                echo "The passwords do not match.  Please try again."
            elif [ "$PASSWORD" == "$PASSWORD2" ] && [ "$PASSWORD" != "" ]; then
                break
            fi
        done
        export GIT_PASSWORD=$PASSWORD
    fi
}

function set_git_variables() {

    if [ -z "$BRANCH_NAME" ]; then
        echo "WARNING: Any existing tfplenum directories in /opt will be removed."
        echo "Which branch do you want to checkout for all repos?"
        select cr in "Master" "Devel" "Fork" "Custom"; do
            case $cr in
                Master ) export BRANCH_NAME=master; export USE_FORK=no; break;;
                Devel ) export BRANCH_NAME=devel; export USE_FORK=no; break;;
                Fork ) export BRANCH_NAME=fork; export USE_FORK=yes; break;;
                Custom ) export BRANCH_NAME=custom; export USE_FORK=no; break;;
            esac
        done

        if [ "$BRANCH_NAME" == "fork" ]; then
            echo "Please type the name of the branch on your fork exactly. Make sure that you use the
            right branch name with each of your forks if the fork doesnt not exist then bootstrap will fail
            you need to go make one for each repo"

            read -p "tfplenum Branch Name: " TFPLENUM_BRANCH_NAME
            export TFPLENUM_BRANCH_NAME=$TFPLENUM_BRANCH_NAME

            read -p "tfplenum-deployer Branch Name: " DEPLOYER_BRANCH_NAME
            export DEPLOYER_BRANCH_NAME=$DEPLOYER_BRANCH_NAME

            read -p "tfplenum-frontend Branch Name: " FRONTEND_BRANCH_NAME
            export FRONTEND_BRANCH_NAME=$FRONTEND_BRANCH_NAME
        fi

        if [ "$BRANCH_NAME" == "custom" ]; then
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
        if [[ ! -d "$directory" && ("$USE_FORK" == "no") ]]; then
            git clone https://bitbucket.di2e.net/scm/thisiscvah/$i.git
            pushd $directory > /dev/null
            git checkout $BRANCH_NAME
            git remote set-url upstream https://bitbucket.di2e.net/scm/thisiscvah/$i.git

            popd > /dev/null
        fi
        if [[ ! -d "$directory" && ("$USE_FORK" == "yes") ]]; then
            git clone https://bitbucket.di2e.net/scm/~$DIEUSERNAME/$i.git
            pushd $directory > /dev/null
            case "$i" in
            "tfplenum" )
                test_branch_name "$TFPLENUM_BRANCH_NAME" "$i" ;;
            "tfplenum-deployer" )
                test_branch_name "$DEPLOYER_BRANCH_NAME" "$i" ;;
            "tfplenum-integration-testing" )
                git checkout origin/devel ;;
            "tfplenum-frontend" )
                test_branch_name "$FRONTEND_BRANCH_NAME" "$i" ;;
            esac
            git remote set-url origin https://bitbucket.di2e.net/scm/~$DIEUSERNAME/$i.git
            git remote add upstream https://bitbucket.di2e.net/scm/thisiscvah/$i.git

            popd > /dev/null
        fi
    done
}

function test_branch_name() {
    echo "Branch $1 is not found in your fork please reenter you branch name or create one with that name"
    if [[ ! $(git checkout $1) ]]; then
        enter_branch_name "$1" "$2"
    else
        git checkout $1
    fi
}

function enter_branch_name() {
    echo " Enter correct branch name for $2 the branch $1 doesnt exist"
    read -p "Branch Name: " NEW_BRANCH_NAME
    export NEW_BRANCH_NAME=$NEW_BRANCH_NAME
    test_branch_name "$NEW_BRANCH_NAME"
}

function setup_frontend(){
    run_cmd /opt/tfplenum-frontend/setup/setup.sh
}

function _install_and_start_mongo40() {    
cat <<EOF > /etc/yum.repos.d/mongodb-org-4.0.repo
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
EOF
    run_cmd yum install -y mongodb-org
    run_cmd systemctl enable mongod
}


function execute_pre(){

    run_cmd curl -s -o epel-release-latest-7.noarch.rpm $EPEL_RPM_PUBLIC_URL
    rpm -e epel-release-latest-7.noarch.rpm
    yum remove epel-release -y
    rm -rf /etc/yum.repos.d/epel*.repo    
    yum install epel-release-latest-7.noarch.rpm -y
    rm -rf epel-release-latest-7.noarch.rpm
        
    run_cmd yum -y update
    run_cmd yum -y install $PACKAGES
}

function remove_npmrc(){
    rm -rf ~/.npmrc
}

function setup_git(){
  if ! rpm -q git > /dev/null 2>&1; then
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

function set_os_type(){
    local os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    if [ "$os_id" == '"centos"' ]; then
        export TFPLENUM_OS_TYPE=centos
    else
        export TFPLENUM_OS_TYPE=rhel
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
    echo "---------------------------------"
    echo "TFPLENUM DEPLOYER BOOTSTRAP ${boostrap_version}"
    echo "---------------------------------"    
    set_os_type
    prompt_runtype
    get_controller_ip
    
    if [ "$TFPLENUM_OS_TYPE" == "rhel" ]; then       
        choose_rhel_yum_repo
    else
        export RHEL_SOURCE_REPO="public";
    fi

    generate_repo_file

    if [ "$RUN_TYPE" == "full" ]; then
        prompt_di2e_creds
        set_git_variables
    fi        
}

export BOOTSTRAP=true
prompts

if [ "$RUN_TYPE" == "full" ]; then
    setup_git    
    clone_repos
    git config --global --unset credential.helper
    execute_pre
    remove_npmrc
    setup_frontend
fi

if [ "$RUN_TYPE" == "bootstrap" ]; then    
    execute_pre
fi

if [ "$RUN_TYPE" == "bootstrap" ] || [ "$RUN_TYPE" == "full" ]; then
    setup_ansible
    execute_bootstrap_playbook
fi

if [ "$RUN_TYPE" == "dockerimages" ]; then
    execute_pull_docker_images_playbook
fi

popd > /dev/null
