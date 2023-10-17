## Installer VS Code for the web

Turn your fresh cloud VM into fully functional VS Code for the web with HTTPS enabled.

[![VS Code for the web](https://github-production-user-asset-6210df.s3.amazonaws.com/469847/275779903-a1b52a3a-6dd7-4b6a-a754-3071fb662ac5.jpg)](https://github-production-user-asset-6210df.s3.amazonaws.com/469847/275777169-60a3fe97-3296-479a-a772-4c0649ff794b.png)

### Pre installation

Before running the installation commands make sure to allow inbound connections on port 80 (HTTP) and 443 (HTTPS) via your cloud virtual firewal configuration.

```sh
export CODE_DOMAIN_NAME=vscode.example.com
curl -s -L https://raw.githubusercontent.com/rioastamal/installer-vscode-for-web/main/install.sh | bash -s -- --core
```

Command above will automatically install Docker on the host machine and run following containers to turn your cloud VM into Cloud IDE:

- [code-server](https://github.com/coder/code-server)
- [Caddy](https://caddyserver.com/)

Once the installation is complete you can access your VS Code via HTTPS URL, e.g: `https://vscode.example.com`. To view the password, you can check `$HOME/.config/code-server/config.yaml`.

### Post installation

Make sure to run `source $HOME/.bashrc` to apply all the changes for current shell.

### Table of contents

- [Supported Linux distributions](#supported-linux-distributions)
- [Development packages](#development-packages)
- [Accessing host machine](#accessing-host-machine)
- [Domain name for testing](#domain-name-for-testing)
- [Contributing](#contributing)
- [License](#license)

## Supported Linux distributions

Supported Linux distributions:

- Amazon Linux 2023
- Amazon Linux 2
- CentOS Stream 9 
- CentOS 7
- Debian 12
- Debian 11
- Debian 10
- Ubuntu 22.04 LTS
- Ubuntu 20.04 LTS
- Ubuntu 18.04 LTS
- More to come...

## Development packages

The installer provides with optional, ready to use development packages for modern application development.

- [x] AWS CLI v2
- [x] Bun (Javascript/TypeScript runtime)
- [x] Docker (via host machine)
- [x] Git
- [x] Go
- [x] Java (JDK)
- [x] nvm
- [x] Node (via nvm)
- [x] pip
- [x] Terraform
- [x] Serverless Framework

All your development activities should take place inside the `code-server` container, with your host directory mounted to the container:

Host directory | Mounted to
---------------|-----------
$HOME/vscode-home | /home/coder

To install development packages above run command below on your VS Code terminal.

```sh
curl -s -L https://raw.githubusercontent.com/rioastamal/installer-vscode-for-web/main/install.sh | bash -s -- --dev-utils
```

If you prefer to install only one of these packages, such as Java, run command below:

```sh
curl -s -L https://raw.githubusercontent.com/rioastamal/installer-vscode-for-web/main/install.sh | bash -s -- --jdk
```

## Accessing host machine

We have provided a handy command that allows you to run commands on the host machine from the VS Code terminal with ease. The script is called `cmd-host`.

```sh
cmd-host docker ps
```

Command above will execute `docker ps` on the host machine via SSH. If you need to pass multi-line commands, you can also use STDIN.

```
cat <<EOF | cmd-host bash
uname -a
sudo systemctl list-unit-files | grep enabled
EOF
```

If you want to log in into your host machine via SSH, do not provide any commands or arguments.

```sh
cmd-host
```

## Domain name for testing

If you do not have domain name for testing, you can use free DNS service mapping like [nip.io](https://nip.io) which can map your VM's public IP address into domain name.

As an example, if your VM's public IP is `1.2.3.4` you can use following to map domain `1.2.3.4.nip.io` to your public IP.

```sh
export CODE_DOMAIN_NAME="$( curl -s https://api.ipify.org ).nip.io"
curl -s -L https://raw.githubusercontent.com/rioastamal/installer-vscode-for-web/main/install.sh | bash -s -- --core
```

Now your VS Code should be available at `https://vscode-1-2-3-4.nip.io`.

> **Important**: I recommend using your own domain name for real-world use cases. Use free DNS mapping services like these for testing purposes only.

## Contributing

Fork this repo and send me a PR.

## License

This project is licensed under MIT License.
