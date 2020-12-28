#!/usr/bin/env bash

export OS
export OS_VERSION

get_os() {
  if [ -f /etc/centos-release ] && command_exists yum; then
    local version
    version=$(cat /etc/centos-release | awk '{print $4}' | awk -F'.' '{print $1}')
    OS="centos"
    OS_VERSION="centos${version}"
  elif uname -a | grep 'Ubuntu' &> /dev/null && command_exists apt-get; then
    OS="ubuntu"
  fi

  if [ -z "${OS}" ]; then
    throw "目前本脚本不支持除CentOS和Ubuntu之外的操作系统"
  fi
}

install_docker_ubuntu() {
  local docker_repo=$(get_config app.docker_repo)

  if [ -z "${docker_repo}" ]; then
    docker_repo='http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo'
  fi

  if ! command_exists docker; then

    if ! sudo apt-get update -y; then
      throw "apt源更新失败" 1
    fi

    if ! sudo apt-get install \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg-agent \
      software-properties-common -y; then
      throw "前置软件包安装失败" 1
    fi

    # verify key
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -; then
      throw "key安装失败"
    fi

    if ! sudo apt-key fingerprint 0EBFCD88; then
       throw "key校验失败"
    fi

    if ! sudo add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) \
      stable"; then
      throw "docker下载仓库设置失败"
    fi

    if ! sudo apt-get update -y; then
      throw "docker下载源更新失败!"
    fi

    if ! sudo apt-get install docker-ce docker-ce-cli containerd.io -y; then
      throw "docker下载失败!"
    fi

    # docker没有启动前/etc/docker目录是不存在的, 无法进行拷贝.所以先启动docker
    sudo service docker start
    sudo cp "${papiyas_extra_path}/daemon.json" /etc/docker/daemon.json
#    sudo systemctl daemon-reload
#    sudo systemctl enable docker

    install_docker_compose

  else
    if ! command_exists docker-compose; then
      install_docker_compose
    fi
  fi

  # 给与当前用户docker权限, 需要推出终端重进才有效果
  if ! groups "${USER}" | grep docker &> /dev/null; then
    sudo gpasswd -a "${USER}" docker
  fi

  # 如果启动了则重启， 否则就是启动。
  # 对未重启的情况下可能导致无法下载镜像的问题
  sudo service docker restart

  # 无需退出终端即可拥有docker权限
  newgrp docker << INSTALL
    bash ${papiyas} install:laradock
INSTALL
}

install_docker_centos() {

  # Docker源
  local docker_repo=$(get_config app.docker_repo)

  if [ -z "${docker_repo}" ]; then
    docker_repo='http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo'
  fi

  if ! command_exists docker; then
    if ! sudo yum install yum-utils -y; then
      throw "yum utils 安装失败" 1
    fi

    if ! sudo yum-config-manager --add-repo "${docker_repo}"; then
      throw "设置docker源失败" 1
    fi

    install_docker_${OS_VERSION}

    # docker没有启动前/etc/docker目录是不存在的, 无法进行拷贝.所以先启动docker
    sudo systemctl start docker
    sudo cp "${papiyas_extra_path}/daemon.json" /etc/docker/daemon.json
    sudo systemctl daemon-reload
    sudo systemctl enable docker

    install_docker_compose

  else
    if ! command_exists docker-compose; then
      install_docker_compose
    fi
  fi

  # 给与当前用户docker权限, 需要推出终端重进才有效果
  if ! groups "${USER}" | grep docker &> /dev/null; then
    sudo gpasswd -a "${USER}" docker
  fi

  # 如果启动了则重启， 否则就是启动。
  # 对未重启的情况下可能导致无法下载镜像的问题
  sudo systemctl restart docker

  # 无需退出终端即可拥有docker权限
  newgrp docker << INSTALL
    bash ${papiyas} install:laradock
INSTALL
}

install_docker_centos7() {
  if ! sudo yum install docker-ce docker-ce-cli containerd.io -y; then
    throw "Docker安装失败!" 1
  fi
}

install_docker_centos8() {
  if ! sudo yum install https://mirrors.aliyun.com/docker-ce/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm -y; then
    throw "安装containerd失败" 1
  fi

  if ! sudo yum install docker-ce docker-ce-cli -y; then
    throw "Docker安装失败!" 1
  fi
}

install_git_ubuntu() {
  if ! sudo apt-get install git -y; then
     throw "安装git失败" 1
  fi
}

install_git_centos() {
  if ! sudo yum install git -y; then
    throw "安装git失败" 1
  fi
}

