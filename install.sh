#!/bin/bash

CODE_SERVER_DOCKER_NAME="code-server"
CODE_SERVER_IMAGE="codercom/code-server"
[ -z "$CODE_SERVER_VERSION" ] && CODE_SERVER_VERSION="bullseye"

CADDY_SERVER_DOCKER_NAME="caddy"
CADDY_SERVER_IMAGE="caddy"
[ -z "$CADDY_SERVER_VERSION" ] && CADDY_SERVER_VERSION="2.7.5"

detect_os() {
  grep 'PRETTY_NAME="Amazon Linux 2"' /etc/os-release >/dev/null && echo 'amazon_linux_2'
  grep 'PRETTY_NAME="Amazon Linux 2023"' /etc/os-release >/dev/null && echo 'amazon_linux_2023'
  grep 'PRETTY_NAME="CentOS Stream 9"' /etc/os-release >/dev/null && echo 'centos_9'
  grep 'PRETTY_NAME="CentOS Linux 7 (Core)"' /etc/os-release >/dev/null && echo 'centos_7'
  grep 'VERSION_CODENAME=jammy' /etc/os-release >/dev/null && echo 'ubuntu_22_04'
  grep 'VERSION_CODENAME=focal' /etc/os-release >/dev/null && echo 'ubuntu_20_04'
  grep 'VERSION_CODENAME=bionic' /etc/os-release >/dev/null && echo 'ubuntu_18_04'
  grep 'VERSION_CODENAME=bookworm' /etc/os-release >/dev/null && echo 'debian_12'
  grep 'VERSION_CODENAME=bullseye' /etc/os-release >/dev/null && echo 'debian_11'
  grep 'VERSION_CODENAME=buster' /etc/os-release >/dev/null && echo 'debian_10'
}

get_cpu_arch() {
  uname -a | awk '{ print $(NF-1) }'
}

printlog() {
  printf "[Installer] "
  printf "$@"
}

dashed_printlog() {
  repeat_chars '-'
  printlog "$@"
  repeat_chars '-'
}

init_code_domain() {
  [ -z "$CODE_DOMAIN_NAME" ] && {
    printf "Error: Missing CODE_DOMAIN_NAME env.
  
You need to have fully qualified domain name FQDN, as an example:
  
export CODE_DOMAIN_NAME=\"vscode.example.com\"\n"
    exit 1
  }
  
  printf "Using domain name $CODE_DOMAIN_NAME\n"
}

repeat_chars() {
  local REPEAT=80
  [ ! -z "$2" ] && REPEAT=$2
  
  for (( i=1; i<=$REPEAT; i++))
  do
    printf "$1"
  done
  
  printf "\n"
}

package_manager() {
  # Modern CentOS based with dnf and yum
  ( [ $( type -t dnf ) ] && [ $( type -t yum ) ] ) && sudo dnf "$@"
  
  # Older CentOS based with only yum
  ( [ ! $( type -t dnf ) ] && [ $( type -t yum ) ] ) && sudo yum "$@"
  
  [ $( type -t dpkg ) ] && sudo apt "$@"
}

install_docker_debian() {
  local OS_NAME="$1"
  [ -z "$OS_NAME" ] && OS_NAME="debian"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$OS_NAME/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  
  # Add the repository to Apt sources:
  echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_NAME \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin unzip
  install_non_root_docker_user
}

install_docker_ubuntu() {
  install_docker_debian ubuntu
}

install_docker_centos() {
  package_manager install -y yum-utils
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  package_manager install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin unzip
  sudo systemctl enable --now docker
  install_non_root_docker_user
}

install_docker_amazon_linux() {
  package_manager install -y docker unzip
  sudo systemctl enable --now docker
  install_docker_compose_amazon_linux
  install_non_root_docker_user
}

install_docker_compose_amazon_linux() {
  [ -z "$DOCKER_COMPOSE_VERSION" ] && DOCKER_COMPOSE_VERSION="2.22.0"
  mkdir -p $HOME/.docker/cli-plugins
  curl -sL -o $HOME/.docker/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$( get_cpu_arch )"
  chmod +x $HOME/.docker/cli-plugins/docker-compose
}

install_non_root_docker_user() {
  sudo groupadd docker 2>/dev/null
  sudo usermod -aG docker $USER
  newgrp - docker
}

install_docker() {
  [ "$( detect_os )" = "ubuntu_22_04" ] && install_docker_ubuntu
  [ "$( detect_os )" = "ubuntu_20_04" ] && install_docker_ubuntu
  [ "$( detect_os )" = "ubuntu_18_04" ] && install_docker_ubuntu
  [ "$( detect_os )" = "debian_12" ] && install_docker_debian
  [ "$( detect_os )" = "debian_11" ] && install_docker_debian
  [ "$( detect_os )" = "debian_10" ] && install_docker_debian
  [ "$( detect_os )" = "centos_9" ] && install_docker_centos
  [ "$( detect_os )" = "centos_7" ] && install_docker_centos
  [ "$( detect_os )" = "amazon_linux_2023" ] && install_docker_amazon_linux
  [ "$( detect_os )" = "amazon_linux_2" ] && install_docker_amazon_linux
}

install_nvm() {
  [ -z "$NVM_VERSION" ] && NVM_VERSION=0.39.5
  [ -z "$NVM_DIR" ] && NVM_DIR="$HOME/.local/nvm"
  
  mkdir -p $NVM_DIR
  curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | NVM_DIR="$NVM_DIR" bash
  
  source $NVM_DIR/nvm.sh
  nvm install --lts
  nvm use --lts
}

install_pip() {
  sudo apt install -y python3-distutils
  curl -s -o /tmp/get-pip.py 'https://bootstrap.pypa.io/get-pip.py'
  python3 /tmp/get-pip.py
  
  sudo rm /usr/local/bin/pip3 2>/dev/null
  sudo ln -s /home/coder/.local/bin/pip3 /usr/local/bin/pip3
  sudo ln -s /home/coder/.local/bin/pip /usr/local/bin/pip
}

install_terraform() {
  [ -z "$TERRAFORM_VERSION" ] && TERRAFORM_VERSION=1.6.1
  [ "$( get_cpu_arch )" = "x86_64" ] && TERRAFORM_URL="https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  [ "$( get_cpu_arch )" = "aarch64" ] && TERRAFORM_URL="https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
  curl -s -q -o /tmp/terraform.zip "$TERRAFORM_URL"
  unzip -o /tmp/terraform.zip -d $HOME/.local/bin/
  rm -rf /tmp/terraform.zip
  
  sudo rm /usr/local/bin/terraform 2>/dev/null 
  sudo ln -s /home/coder/.local/bin/terraform /usr/local/bin/terraform
}

install_jdk() {
  [ -z "$JDK_VERSION" ] && JDK_VERSION=21
  [ "$( get_cpu_arch )" = "x86_64" ] && JDK_URL="https://download.oracle.com/java/$JDK_VERSION/latest/jdk-${JDK_VERSION}_linux-x64_bin.tar.gz"
  [ "$( get_cpu_arch )" = "aarch64" ] && JDK_URL="https://download.oracle.com/java/$JDK_VERSION/latest/jdk-${JDK_VERSION}_linux-aarch64_bin.tar.gz"
  curl -L -s -q -o /tmp/jdk.tar.gz "$JDK_URL"
  rm -rf $HOME/.local/jdk 2>/dev/null
  tar xvf /tmp/jdk.tar.gz -C $HOME/.local/
  mv $HOME/.local/jdk-$JDK_VERSION $HOME/.local/jdk
  rm /tmp/jdk.tar.gz
  
  grep 'JAVA_HOME=' $HOME/.bashrc >/dev/null 2>&1 || {
    printf "
JAVA_HOME=$HOME/.local/jdk
export PATH=$PATH:\$JAVA_HOME/bin\n" >> $HOME/.bashrc
  }
  
  # Ensure next call for $PATH has newest value
  JAVA_HOME=$HOME/.local/jdk
  export PATH=$PATH:$JAVA_HOME/bin
  
  sudo rm /usr/local/bin/java /usr/local/bin/javac 2>/dev/null
  sudo ln -s $HOME/.local/jdk/bin/java /usr/local/bin/java
  sudo ln -s $HOME/.local/jdk/bin/javac /usr/local/bin/javac
}

install_serverless_framework() {
  npm install -g serverless
}

install_go() {
  [ -z "$GO_VERSION" ] && GO_VERSION=1.21.3
  [ "$( get_cpu_arch )" = "x86_64" ] && GO_URL="https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
  [ "$( get_cpu_arch )" = "aarch64" ] && GO_URL="https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz"
  curl -L -s -q -o /tmp/go.tar.gz "$GO_URL"
  rm -rf $HOME/.local/go
  tar xvf /tmp/go.tar.gz -C $HOME/.local/

  grep 'GO_HOME=' $HOME/.bashrc >/dev/null 2>&1 || {
    printf "
GO_HOME=$HOME/.local/go
export PATH=$PATH:\$GO_HOME/bin\n" >> $HOME/.bashrc
  }
  
  # Ensure next call for $PATH has newest value
  GO_HOME=$HOME/.local/go
  export PATH=$PATH:$GO_HOME/bin
  
  sudo rm /usr/local/bin/go /usr/local/bin/gofmt 2>/dev/null
  sudo ln -s $HOME/.local/go/bin/go /usr/local/bin/go
  sudo ln -s $HOME/.local/go/bin/gofmt /usr/local/bin/gofmt
}

install_aws_cli() {
  [ "$( get_cpu_arch )" = "x86_64" ] && AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  [ "$( get_cpu_arch )" = "aarch64" ] && AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  curl -L -s -q -o /tmp/awsv2.zip "$AWS_CLI_URL"
  unzip -o /tmp/awsv2.zip -d /tmp 
  /tmp/aws/install --bin-dir $HOME/.local/bin --install-dir $HOME/.local/aws-cli
  rm -rf /tmp/aws /tmp/awsv2.zip
  
  sudo rm /usr/local/bin/aws 2>/dev/null
  sudo ln -s /home/coder/.local/bin/aws /usr/local/bin/aws
}

install_gcc() {
  sudo apt install -y build-essential
}

install_bunjs() {
  [ -z "$BUN_VERSION" ] && BUN_VERSION=1.0.6
  curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
}

install_caddy_docker() {
  mkdir -p $HOME/.local/caddy $HOME/.config/caddy
  
  cat <<EOF > $HOME/.config/caddy/Caddyfile
$CODE_DOMAIN_NAME {
	reverse_proxy 172.17.0.1:8080
}
EOF
  
  sudo docker stop caddy-server && sudo docker rm caddy-server
  sudo docker run -it --name caddy-server -p 80:80 -p 443:443 \
    -v "$HOME/.local/caddy:/data" \
    -v "$HOME/.config/caddy/Caddyfile:/etc/caddy/Caddyfile" \
    -u "$(id -u):$(id -g)" \
    -e "DOCKER_USER=$USER" \
    --restart unless-stopped \
    -d caddy:latest
}

install_vscode_docker() {
  mkdir -p $HOME/vscode-home/project
  
  sudo docker stop $CODE_SERVER_DOCKER_NAME && sudo docker rm $CODE_SERVER_DOCKER_NAME
  sudo docker run -it --name $CODE_SERVER_DOCKER_NAME -p 8080:8080 \
    -v "$HOME/vscode-home:/home/coder" \
    -u "$(id -u):$(id -g)" \
    -e "DOCKER_USER=$USER" \
    --restart unless-stopped \
    -d $CODE_SERVER_IMAGE:$CODE_SERVER_VERSION
    
    configure_post_docker_installation
}

configure_post_docker_installation() {
  rm $HOME/.ssh/docker-ssh.key 2>/dev/null
  rm $HOME/.ssh/docker-ssh.key.pub 2>/dev/null
  ssh-keygen -t rsa -b 2048 -N "" -f $HOME/.ssh/docker-ssh.key
  cat $HOME/.ssh/docker-ssh.key.pub >> $HOME/.ssh/authorized_keys
  cat <<EOF | sudo docker exec -i $CODE_SERVER_DOCKER_NAME bash -
[ ! -f /home/coder/.bashrc ] && cp -r /etc/skel/. /home/coder

mkdir /home/coder/.ssh 
chmod 0700 /home/coder/.ssh

echo "$( cat $HOME/.ssh/docker-ssh.key )" > /home/coder/.ssh/docker-ssh.key
chmod 0600 /home/coder/.ssh/docker-ssh.key

echo 'ssh -o StrictHostKeyChecking=no -o LogLevel=error -o UserKnownHostsFile=/dev/null -i /home/coder/.ssh/docker-ssh.key' $USER@172.17.0.1 '"\$@"' | sudo tee /usr/local/bin/ssh-host
sudo chmod +x /usr/local/bin/ssh-host
sudo ln -s /usr/local/bin/ssh-host /usr/local/bin/exec-host
sudo ln -s /usr/local/bin/ssh-host /usr/local/bin/cmd-host

echo 'ssh-host docker' '"\$@"' | sudo tee /usr/local/bin/docker-host
sudo chmod +x /usr/local/bin/docker-host

sudo apt update -y
sudo apt install -y git unzip
EOF
}

exit_if_not_docker() {
  [ ! -f /.dockerenv ] && {
    dashed_printlog "Error: Running inside host machine detected.\n" >&2
    printf "Please run this option from VS Code container.\n" >&2
    
    exit 4
  }
}

# Parse the arguments
while [ $# -gt 0 ]; do
  case $1 in
    --core)
      [ -f /.dockerenv ] && {
        dashed_printlog "Error: Running inside Docker detected\n" >&2
        printf "Please run --core option from host machine.\n" >&2
        
        exit 4
      }
      
      dashed_printlog "Checking domain name...\n"
      init_code_domain
      
      dashed_printlog "Updating %s system packages...\n" "$( detect_os )"
      package_manager update -y
      
      dashed_printlog "Installing VS Code for web browser (%s)...\n" "$( detect_os )"
      install_docker
      
      sudo systemctl enable --now docker && sleep 3
      
      install_vscode_docker
      install_caddy_docker
      # install_caddy
      
      dashed_printlog "Caddy reverse proxy is ready\n"
      printf "You can access VS Code at the following URL: 
%s\n" "https://$CODE_DOMAIN_NAME"

      printf "\nPlease wait for couple of minutes before accessing the website, the TLS certificate creation may take a while.\n"

      dashed_printlog "VS Code password\n"
      printf "Password are stored at $HOME/vscode-home/.config/code-server/config.yaml\n"
    ;;
    
    --dev-utils)
      exit_if_not_docker
      
      dashed_printlog "Installing nvm (%s)...\n" "$( detect_os )"
      install_nvm
      
      dashed_printlog "Installing Python PIP 3 (%s)...\n" "$( detect_os )"
      install_pip
      
      dashed_printlog "Installing AWS CLI v2 (%s)...\n" "$( detect_os )"
      install_aws_cli
      
      dashed_printlog "Installing Terraform (%s)...\n" "$( detect_os )"
      install_terraform
      
      dashed_printlog "Installing Java Development Kit (JDK) (%s)...\n" "$( detect_os )"
      install_jdk
      
      dashed_printlog "Installing Golang (%s)...\n" "$( detect_os )"
      install_go
      
      dashed_printlog "Installing GCC (build-essential) (%s)...\n" "$( detect_os )"
      install_gcc
      
      dashed_printlog "Installing Bun (Javascript/TypeScript runtime) %s...\n" "$( detect_os )"
      install_bunjs
      
      dashed_printlog "Installing Serverless Framework %s...\n" "$( detect_os )"
      install_serverless_framework
    ;;
    
    --terraform)
      exit_if_not_docker
      dashed_printlog "Installing Terraform (%s)...\n" "$( detect_os )"
      install_terraform
    ;;
    
    --awscli)
      exit_if_not_docker
      dashed_printlog "Installing AWS CLI v2 (%s)...\n" "$( detect_os )"
      install_aws_cli
    ;;
    
    --pip3)
      exit_if_not_docker
      dashed_printlog "Installing Python PIP 3 (%s)...\n" "$( detect_os )"
      install_pip
    ;;
    
    --jdk)
      exit_if_not_docker
      dashed_printlog "Installing Java Development Kit (JDK) (%s)...\n" "$( detect_os )"
      install_jdk
    ;;
    
    --go)
      exit_if_not_docker
      dashed_printlog "Installing Golang (%s)...\n" "$( detect_os )"
      install_go
    ;;
    
    --gcc)
      exit_if_not_docker
      dashed_printlog "Installing GCC (build-essential) (%s)...\n" "$( detect_os )"
      install_gcc
    ;;
    
    --bunjs)
      exit_if_not_docker
      dashed_printlog "Installing Bun (Javascript/TypeScript runtime) %s...\n" "$( detect_os )"
      install_bunjs
    ;;

    --nvm)
      exit_if_not_docker
      dashed_printlog "Installing nvm (%s)...\n" "$( detect_os )"
      install_nvm
    ;;
    
    --sls)
      exit_if_not_docker
      dashed_printlog "Installing Serverless Framework %s...\n" "$( detect_os )"
      install_serverless_framework
    ;;

    --version)
      printf "version %s\n" "1.0"
      exit 0
    ;;

    *) 
      echo "Unrecognised option passed: $1" 2>&2; 
      exit 1
    ;;
  esac
  shift
done