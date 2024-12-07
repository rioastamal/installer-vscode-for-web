#!/bin/bash

OS_PACKAGE_HAS_BEEN_UPDATED='no'
INSTALLER_VERSION='1.2.1'

detect_os() {
  [ ! -z "$EMULATE_OS_VERSION" ] && printf "%s" "$EMULATE_OS_VERSION" && return 0
  grep 'PRETTY_NAME="Amazon Linux 2023' /etc/os-release >/dev/null && printf 'amazon_linux_2023' && return 0
  grep 'PRETTY_NAME="CentOS Stream 9' /etc/os-release >/dev/null && printf 'centos_9' && return 0
  grep 'PRETTY_NAME="CentOS Stream 8' /etc/os-release >/dev/null && printf 'centos_8' && return 0
  grep 'VERSION_CODENAME=noble' /etc/os-release >/dev/null && printf 'ubuntu_24_04' && return 0
  grep 'VERSION_CODENAME=jammy' /etc/os-release >/dev/null && printf 'ubuntu_22_04' && return 0
  grep 'VERSION_CODENAME=focal' /etc/os-release >/dev/null && printf 'ubuntu_20_04' && return 0
  grep 'VERSION_CODENAME=bookworm' /etc/os-release >/dev/null && printf 'debian_12' && return 0
  grep 'VERSION_CODENAME=bullseye' /etc/os-release >/dev/null && printf 'debian_11' && return 0
  grep 'VERSION_CODENAME=buster' /etc/os-release >/dev/null && printf 'debian_10' && return 0
  grep 'PLATFORM_ID="platform:el9"' /etc/os-release >/dev/null && printf 'rhel_9' && return 0
  
  printf 'unknown' && return 1
}

is_debian_based() {
  detect_os | grep 'debian_' && return 0
  detect_os | grep 'ubuntu_' && return 0
  
  return 1
}

is_rpm_based() {
  detect_os | grep 'centos_' && return 0
  detect_os | grep 'rhel_' && return 0
  detect_os | grep 'amazon_linux_' && return 0
  
  return 1
}

detect_strong_password() {
  local PASSWORD="$1"
  
  [ $( printf "$PASSWORD" | wc -c ) -lt 12 ] && {
    printf "Error: Password is less than 12 characters.\n" >&2
    return 1 
  }
  
  [ $( printf "$PASSWORD" | grep '[0-9]' ) ] || {
    printf "Error: Password must contains a digit.\n" >&2
    return 2
  }
  
  [ $( printf "$PASSWORD" | grep '[a-z]' ) ] || {
    printf "Error: Password must contains a lower case letter.\n" >&2
    return 2
  }
  
  [ $( printf "$PASSWORD" | grep '[A-Z]' ) ] || {
    printf "Error: Password must contains a upper case letter.\n" >&2
    return 2
  }

  return 0
}

is_selinux_enabled() {
  [ "$( sestatus | grep 'SELinux status' | awk '{print $3}' )" = "enabled" ] && return 0
  return 1
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

_init() {
    [ -f /.dockerenv ] && {
      dashed_printlog "Error: Running inside Docker detected\n" >&2
      printf "Please run --core option from host machine.\n" >&2
      
      exit 4
    }
    
    dashed_printlog "Preparing installation...\n"
    [ "$( detect_os )" = "unknown" ] && {
      printf "Error: Unsupported OS, please see supported OS at: %s\n" \
      "https://github.com/rioastamal/installer-vscode-for-web"
      exit 400
    }
    
    init_code_domain
    exit_if_password_not_strong
    
    [ -z "$HOME" ] && export HOME="$( getent passwd "$(whoami)" | awk -F':' '{print $6}' )"

    type -t tar >/dev/null || package_manager install -y tar
    type -t python3 > /dev/null || package_manager install -y python3
    type -t unzip > /dev/null || package_manager install -y unzip
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

update_os_package() {
  [ "$OS_PACKAGE_HAS_BEEN_UPDATED" = "no" ] && package_manager update -y
  OS_PACKAGE_HAS_BEEN_UPDATED='yes'
}

get_caddy_protocol() {
  [ -z "$CADDY_DISABLE_HTTPS" ] && CADDY_DISABLE_HTTPS='no'

  [ "$CADDY_DISABLE_HTTPS" = "no" ] && {
    printf "https://"
    return 0
  }

  printf "http://"
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
  
  [ $( type -t dpkg ) ] && sudo DEBIAN_FRONTEND=noninteractive apt "$@"
}

install_docker_debian() {
  local OS_NAME="$1"
  [ -z "$OS_NAME" ] && OS_NAME="debian"
  update_os_package
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
  update_os_package
  package_manager install -y yum-utils
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  package_manager install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin unzip
  sudo systemctl enable --now docker
  install_non_root_docker_user
}

install_docker_amazon_linux() {
  update_os_package
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
  [ "$( detect_os )" = "ubuntu_24_04" ] && install_docker_ubuntu
  [ "$( detect_os )" = "ubuntu_22_04" ] && install_docker_ubuntu
  [ "$( detect_os )" = "ubuntu_20_04" ] && install_docker_ubuntu
  [ "$( detect_os )" = "ubuntu_18_04" ] && install_docker_ubuntu
  [ "$( detect_os )" = "debian_12" ] && install_docker_debian
  [ "$( detect_os )" = "debian_11" ] && install_docker_debian
  [ "$( detect_os )" = "debian_10" ] && install_docker_debian
  [ "$( detect_os )" = "centos_9" ] && install_docker_centos
  [ "$( detect_os )" = "centos_8" ] && install_docker_centos
  [ "$( detect_os )" = "centos_7" ] && install_docker_centos
  [ "$( detect_os )" = "rhel_9" ] && install_docker_centos
  [ "$( detect_os )" = "amazon_linux_2023" ] && install_docker_amazon_linux
  [ "$( detect_os )" = "amazon_linux_2" ] && install_docker_amazon_linux
}

install_nvm() {
  [ -z "$NVM_VERSION" ] && NVM_VERSION=0.40.1
  [ -z "$NVM_DIR" ] && NVM_DIR="$HOME/.local/nvm"
  
  mkdir -p $NVM_DIR
  curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | NVM_DIR="$NVM_DIR" bash
  
  source $NVM_DIR/nvm.sh
  nvm install --lts
  nvm use --lts
}

install_miniconda() {
  curl -s -o /tmp/Miniconda3-latest-Linux-x86_64.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  bash /tmp/Miniconda3-latest-Linux-x86_64.sh -b -u -p $HOME/.local/miniconda
  $HOME/.local/miniconda/bin/conda init
}

install_terraform() {
  [ -z "$TERRAFORM_VERSION" ] && TERRAFORM_VERSION=1.10.1
  [ "$( get_cpu_arch )" = "x86_64" ] && TERRAFORM_URL="https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  [ "$( get_cpu_arch )" = "aarch64" ] && TERRAFORM_URL="https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
  curl -s -q -o /tmp/terraform.zip "$TERRAFORM_URL"
  unzip -o /tmp/terraform.zip -d $HOME/.local/bin/
  rm -rf /tmp/terraform.zip
  
  sudo rm /usr/local/bin/terraform 2>/dev/null 
  sudo ln -sf $HOME/.local/bin/terraform /usr/local/bin/terraform
  
  code-server --install-extension hashicorp.terraform
}

install_jdk() {
  [ -z "$JDK_VERSION" ] && JDK_VERSION=21
  [ "$( get_cpu_arch )" = "x86_64" ] && JDK_URL="https://download.oracle.com/java/$JDK_VERSION/latest/jdk-${JDK_VERSION}_linux-x64_bin.tar.gz"
  [ "$( get_cpu_arch )" = "aarch64" ] && JDK_URL="https://download.oracle.com/java/$JDK_VERSION/latest/jdk-${JDK_VERSION}_linux-aarch64_bin.tar.gz"
  curl -L -s -q -o /tmp/jdk.tar.gz "$JDK_URL"
  rm -rf $HOME/.local/jdk 2>/dev/null
  tar xvf /tmp/jdk.tar.gz -C $HOME/.local/
  mv $HOME/.local/jdk-${JDK_VERSION}* $HOME/.local/jdk
  rm /tmp/jdk.tar.gz
  
  grep 'JAVA_HOME=' $HOME/.bashrc >/dev/null 2>&1 || {
    printf "
JAVA_HOME=$HOME/.local/jdk
export PATH=\$JAVA_HOME/bin:\$PATH\n" >> $HOME/.bashrc
  }
  
  # Ensure next call for $PATH has newest value
  JAVA_HOME=$HOME/.local/jdk
  export PATH=$PATH:$JAVA_HOME/bin
  
  sudo rm /usr/local/bin/java /usr/local/bin/javac 2>/dev/null
  sudo ln -sf $HOME/.local/jdk/bin/java /usr/local/bin/java
  sudo ln -sf $HOME/.local/jdk/bin/javac /usr/local/bin/javac
}

install_serverless_framework() {
  # Make sure we got npm installed
  [ -d $HOME/.local/nvm ] || install_nvm
  source $HOME/.local/nvm/nvm.sh
  rm -rf "$( dirname $NVM_BIN )/lib/node_modules/serverless" 2>/dev/null
  
  npm install -g serverless
}

install_go() {
  [ -z "$GO_VERSION" ] && GO_VERSION=1.23.4
  [ "$( get_cpu_arch )" = "x86_64" ] && GO_URL="https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
  [ "$( get_cpu_arch )" = "aarch64" ] && GO_URL="https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz"
  curl -L -s -q -o /tmp/go.tar.gz "$GO_URL"
  rm -rf $HOME/.local/go
  tar xvf /tmp/go.tar.gz -C $HOME/.local/

  grep 'GO_HOME=' $HOME/.bashrc >/dev/null 2>&1 || {
    printf "
GO_HOME=$HOME/.local/go
export PATH=\$GO_HOME/bin:\$PATH\n" >> $HOME/.bashrc
  }
  
  # Ensure next call for $PATH has newest value
  GO_HOME=$HOME/.local/go
  export PATH=$PATH:$GO_HOME/bin
  
  sudo rm /usr/local/bin/go /usr/local/bin/gofmt 2>/dev/null
  sudo ln -sf $HOME/.local/go/bin/go /usr/local/bin/go
  sudo ln -sf $HOME/.local/go/bin/gofmt /usr/local/bin/gofmt
}

install_aws_cli() {
  [ "$( get_cpu_arch )" = "x86_64" ] && AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  [ "$( get_cpu_arch )" = "aarch64" ] && AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  curl -L -s -q -o /tmp/awsv2.zip "$AWS_CLI_URL"
  unzip -o /tmp/awsv2.zip -d /tmp 
  /tmp/aws/install --bin-dir $HOME/.local/bin --install-dir $HOME/.local/aws-cli
  rm -rf /tmp/aws /tmp/awsv2.zip
  
  sudo rm /usr/local/bin/aws 2>/dev/null
  sudo ln -sf $HOME/.local/bin/aws /usr/local/bin/aws
}

install_gcc() {
  update_os_package
  is_debian_based && package_manager install -y build-essential
  is_rpm_based && package_manager groupinstall -y "Development Tools"
}

install_bunjs() {
  [ -z "$BUN_VERSION" ] && BUN_VERSION=1.1.38
  curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
}

install_caddy() {
  # Download pre-built Caddy binary compiled with caddy-security plugin from github.com/rioastamal/caddy-plus-security
  [ -z "$CADDY_VERSION" ] && CADDY_VERSION="2.8.4"
  [ "$( get_cpu_arch )" = "x86_64" ] && CADDY_URL="https://github.com/rioastamal/caddy-plus-security/releases/download/v${CADDY_VERSION}/caddy-v${CADDY_VERSION}-linux-amd64"
  [ "$( get_cpu_arch )" = "aarch64" ] && CADDY_URL="https://github.com/rioastamal/caddy-plus-security/releases/download/v${CADDY_VERSION}/caddy-v${CADDY_VERSION}-linux-arm64"
  
  type -t sestatus >/dev/null || package_manager install -y policycoreutils

  local CADDY_HOME=/home/caddy
  sudo mkdir -p $CADDY_HOME
  
  sudo groupadd --system caddy
  sudo useradd --system \
    --gid caddy \
    --no-create-home \
    --home-dir $CADDY_HOME \
    --shell /usr/sbin/nologin \
    --comment "Caddy web server" \
    caddy
  
  sudo chmod 0700 $CADDY_HOME
  sudo chown caddy:caddy $CADDY_HOME
  sudo -u caddy mkdir -p $CADDY_HOME/.local/caddy/bin $CADDY_HOME/.config/caddy
  
  sudo -u caddy curl -L -s -o $CADDY_HOME/.local/caddy/bin/caddy "$CADDY_URL"
  sudo -u caddy chmod +x $CADDY_HOME/.local/caddy/bin/caddy
  
  sudo ln -fs $CADDY_HOME/.local/caddy/bin/caddy /usr/local/bin/caddy

  cat <<SYSTEMD | sudo tee /etc/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --config $CADDY_HOME/.config/caddy/Caddyfile --envfile $CADDY_HOME/.config/caddy/Caddyfile.env
ExecReload=/usr/local/bin/caddy reload --config $CADDY_HOME/.config/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
SYSTEMD

  # Caddy config file oauth2 authentication (Google and GitHub)
  sudo [ ! -f $CADDY_HOME/.config/caddy/Caddyfile.oauth2 ] && {
    local CADDY_PROTOCOL="$( get_caddy_protocol )"
    cat <<CADDY_FILE_OAUTH2 | sudo -u caddy tee $CADDY_HOME/.config/caddy/Caddyfile.oauth2
{
  order authenticate before respond
  order authorize before basicauth

  security {
    import oauth2/providers/google.conf
    import oauth2/providers/github.conf

    authentication portal vscode_portal {
      crypto default token lifetime 7200
      crypto key sign-verify {\$CRYPTO_KEY}
      import oauth2/providers/enabled.conf
      cookie domain .${CODE_DOMAIN_NAME}
      ui {
        links {
          "Visual Studio Code" "/" icon "las la-code"
        }
      }

      import oauth2/users/google.conf
      import oauth2/users/github.conf
    }

    authorization policy vscode_policy {
      set auth url ${CADDY_PROTOCOL}$CODE_DOMAIN_NAME/__/login
      crypto key verify {\$CRYPTO_KEY}
      allow roles authp/admin authp/user
      validate bearer header
      inject headers with claims
    }
  }
}

${CADDY_PROTOCOL}$CODE_DOMAIN_NAME {
  handle /__/* {
    authenticate with vscode_portal
  }

  handle {
    authorize with vscode_policy
    reverse_proxy 127.0.0.1:8080
  }
}
CADDY_FILE_OAUTH2
  }

  # Add oauth2 related configuration
  sudo -u caddy mkdir -p $CADDY_HOME/.config/caddy/oauth2/providers
  sudo -u caddy mkdir -p $CADDY_HOME/.config/caddy/oauth2/users

  sudo [ ! -f $CADDY_HOME/.config/caddy/oauth2/providers/google.conf ] && {
    cat <<'GOOGLE_OAUTH2' | sudo -u caddy tee $CADDY_HOME/.config/caddy/oauth2/providers/google.conf
oauth identity provider google {
  realm google
  driver google
  client_id {$GOOGLE_CLIENT_ID}
  client_secret {$GOOGLE_CLIENT_SECRET}
  scopes openid email profile
}
GOOGLE_OAUTH2
  }

  sudo [ ! -f $CADDY_HOME/.config/caddy/oauth2/providers/github.conf ] && {
    printf "oauth identity provider github {\$GITHUB_CLIENT_ID} {\$GITHUB_CLIENT_SECRET}\n" | \
    sudo tee $CADDY_HOME/.config/caddy/oauth2/providers/github.conf
  }

  sudo [ ! -f $CADDY_HOME/.config/caddy/oauth2/providers/enabled.conf ] && {
    cat <<'ENABLED_PROVIDERS' | sudo -u caddy tee $CADDY_HOME/.config/caddy/oauth2/providers/enabled.conf
# Use a comment to disable the provider.
enable identity provider google
enable identity provider github
ENABLED_PROVIDERS
  }

  sudo [ ! -f $CADDY_HOME/.config/caddy/oauth2/users/google.conf ] && {
    cat <<'GOOGLE_USER' | sudo -u caddy tee $CADDY_HOME/.config/caddy/oauth2/users/google.conf
transform user {
  match realm google
  # Replace the email with yours
  match email YOUR_EMAIL@gmail.com
  action add role authp/user
}
GOOGLE_USER
  }

  sudo [ ! -f $CADDY_HOME/.config/caddy/oauth2/users/github.conf ] && {
    cat <<'GITHUB_USER' | sudo -u caddy tee $CADDY_HOME/.config/caddy/oauth2/users/github.conf
transform user {
  match realm github
  # Replace with your GitHub username
  match sub github.com/YOUR_USERNAME
  action add role authp/user
}
GITHUB_USER
  }

  sudo [ ! -f $CADDY_HOME/.config/caddy/Caddyfile.env ] && {
    local CRYPTO_KEY_VAL="$( head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48 )"
    cat <<CADDY_ENV | sudo -u caddy tee $CADDY_HOME/.config/caddy/Caddyfile.env
# Homepage URL -> https://$CODE_DOMAIN_NAME
# Authorization callback URL -> https://$CODE_DOMAIN_NAME/__/oauth2/github/authorization-code-callback
# See https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0007-github
GITHUB_CLIENT_ID=YOUR_GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET=YOUR_GITHUB_CLIENT_SECRET

# Authorized Javascript origins -> https://$CODE_DOMAIN_NAME
# Authorized redirect URIs -> https://$CODE_DOMAIN_NAME/__/oauth2/google/authorization-code-callback
# See https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0002-google
GOOGLE_CLIENT_ID=YOUR_GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=YOUR_GOOGLE_CLIENT_SECRET

CRYPTO_KEY=$CRYPTO_KEY_VAL
CADDY_ENV
  }

  # Caddy config file with password enabled. This file will be used when oauth2 
  # authentication is not enabled
  sudo [ ! -f $CADDY_HOME/.config/caddy/Caddyfile.passwd ] && {
    cat <<CADDY_FILE | sudo -u caddy tee $CADDY_HOME/.config/caddy/Caddyfile.passwd
${CADDY_PROTOCOL}$CODE_DOMAIN_NAME {
  reverse_proxy 127.0.0.1:8080
}
CADDY_FILE
  }

  # Symlink the default Caddyfile to Caddyfile.passwd
  sudo [ ! -f $CADDY_HOME/.config/caddy/Caddyfile ] && {
    sudo -u caddy ln -fs $CADDY_HOME/.config/caddy/Caddyfile.passwd $CADDY_HOME/.config/caddy/Caddyfile
  }

  is_selinux_enabled && {
    package_manager install -y policycoreutils-python-utils
    sudo semanage fcontext -a -t bin_t $CADDY_HOME/.local/caddy/bin/caddy
    sudo restorecon -Rv $CADDY_HOME/.local/caddy/bin/caddy
  }
  sudo systemctl stop caddy 2>/dev/null
  sudo systemctl enable --now caddy
}

install_vscode() {
  local VSCODE_USER=vscode
  local VSCODE_HOME=/home/$VSCODE_USER
  
  sudo mkdir -p $VSCODE_HOME
  
  sudo groupadd $VSCODE_USER
  sudo useradd \
    --gid $VSCODE_USER \
    --no-create-home \
    --home-dir $VSCODE_HOME \
    --shell /bin/bash \
    --comment "VS Code User" \
    $VSCODE_USER
  
  sudo chown $VSCODE_USER:$VSCODE_USER $VSCODE_HOME
  sudo chmod 0700 $VSCODE_HOME
  sudo -u $VSCODE_USER mkdir -p $VSCODE_HOME/.config/code-server
  
  [ -f "$VSCODE_HOME/.bashrc" ] || {
    sudo -u $VSCODE_USER cp -r /etc/skel/. /home/$VSCODE_USER
  }
  
  sudo [ -f "$VSCODE_HOME/.config/code-server/config.yaml" ] || {
    [ ! -z "$CODE_PASSWORD" ] && {
      printlog "Setting up password for VS Code...\n"
      
      printf "bind-addr: 127.0.0.1:8080
auth: password
password: $CODE_PASSWORD
cert: false

# Use following config if you want to disable code-server password
# and prefer OAuth2 authentication using Google or GitHub.
#
#auth: none
#password:
" | sudo -u $VSCODE_USER tee $VSCODE_HOME/.config/code-server/config.yaml > /dev/null
    }
  }
  
  sudo -u $VSCODE_USER chmod 0600 $VSCODE_HOME/.config/code-server/config.yaml
  sudo ls /etc/sudoers.d/99-vscode-user >/dev/null 2>&1 || {
    printf "%s ALL=(ALL) NOPASSWD:ALL\n" "$VSCODE_USER" | sudo tee /etc/sudoers.d/99-vscode-user
  }

  curl -fsSL https://code-server.dev/install.sh | sh
  
  sudo systemctl stop code-server@$VSCODE_USER
  sudo systemctl enable --now code-server@$VSCODE_USER
}

exit_if_password_not_strong() {
  [ -z "$CODE_PASSWORD" ] && return 0
  detect_strong_password "$CODE_PASSWORD" || exit 1
}

# Parse the arguments
while [ $# -gt 0 ]; do
  case $1 in
    --caddy)
      dashed_printlog "Installing Caddy server (%s)...\n" "$( detect_os )"
      install_caddy
    ;;
    
    --vscode)
      dashed_printlog "Installing VS Code server (%s)...\n" "$( detect_os )"
      install_vscode
    ;;

    --core)
      _init
      CADDY_PROTOCOL="$( get_caddy_protocol )"
      
      dashed_printlog "Updating %s system packages...\n" "$( detect_os )"
      update_os_package
      
      dashed_printlog "Installing Caddy server (%s)...\n" "$( detect_os )"
      install_caddy
      
      dashed_printlog "Installing VS Code server (%s)...\n" "$( detect_os )"
      install_vscode
      
      dashed_printlog "Caddy reverse proxy is ready\n"
      printf "You can access VS Code at the following URL: 
%s\n" "${CADDY_PROTOCOL}$CODE_DOMAIN_NAME"

      printf "\nPlease wait for couple of minutes before accessing the website, the TLS certificate creation may take a while.\n"

      dashed_printlog "VS Code password\n"
      printf "Password are stored at /home/vscode/.config/code-server/config.yaml\n\n"

      dashed_printlog "Authentication via Google or GitHub (OAuth2)\n"
      printf "To activate, edit following files:

/home/caddy/.config/caddy/Caddyfile.env
/home/caddy/.config/caddy/oauth2/users/google.conf
/home/caddy/.config/caddy/oauth2/users/github.conf

Create symlink of /home/caddy/.config/caddy/Caddyfile, run following:

    sudo -u caddy ln -fs /home/caddy/.config/caddy/Caddyfile.oauth2 /home/caddy/.config/caddy/Caddyfile

Restart Caddy:

    sudo systemctl restart caddy

Now, you can optionally remove the password at /home/vscode/.config/code-server/config.yaml.

    sudo systemctl restart code-server@vscode

To logout from OAuth2 session go to:

    ${CADDY_PROTOCOL}$CODE_DOMAIN_NAME/__/logout

Visit https://github.com/rioastamal/installer-vscode-for-web/ project page for complete documentation.\n\n"
    ;;
    
    --dev-utils)
      dashed_printlog "Installing Docker (%s)...\n" "$( detect_os )"
      install_docker
      
      dashed_printlog "Installing nvm (%s)...\n" "$( detect_os )"
      install_nvm
      
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

      dashed_printlog "Installing Miniconda %s...\n" "$( detect_os )"
      install_miniconda
    ;;
    
    --docker)
      dashed_printlog "Installing Docker (%s)...\n" "$( detect_os )"
      install_docker
    ;;
    
    --terraform)
      dashed_printlog "Installing Terraform (%s)...\n" "$( detect_os )"
      install_terraform
    ;;
    
    --awscli)
      dashed_printlog "Installing AWS CLI v2 (%s)...\n" "$( detect_os )"
      install_aws_cli
    ;;
    
    --jdk)
      dashed_printlog "Installing Java Development Kit (JDK) (%s)...\n" "$( detect_os )"
      install_jdk
    ;;
    
    --go)
      dashed_printlog "Installing Golang (%s)...\n" "$( detect_os )"
      install_go
    ;;
    
    --gcc)
      dashed_printlog "Installing GCC (build-essential) (%s)...\n" "$( detect_os )"
      install_gcc
    ;;
    
    --bunjs)
      dashed_printlog "Installing Bun (Javascript/TypeScript runtime) %s...\n" "$( detect_os )"
      install_bunjs
    ;;

    --nvm)
      dashed_printlog "Installing nvm (%s)...\n" "$( detect_os )"
      install_nvm
    ;;
    
    --sls)
      dashed_printlog "Installing Serverless Framework %s...\n" "$( detect_os )"
      install_serverless_framework
    ;;

    --miniconda)
      dashed_printlog "Installing Miniconda %s...\n" "$( detect_os )"
      install_miniconda
    ;;

    --version)
      printf "version %s\n" "$INSTALLER_VERSION"
      exit 0
    ;;

    *) 
      echo "Unrecognised option passed: $1" 2>&2; 
      exit 1
    ;;
  esac
  shift
done
