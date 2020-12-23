#!/usr/bin/env bash


################################################################
## install:docker
## 
## @description: 安装docker和laradock,
## @notice: 目前仅适用于CentOS7和CentOS8
##
##
################################################################
install::docker() {
  install_docker
}

check_enviroment() {
  if [ ! -f /etc/centos-release ] && ! command -v yum &> /dev/null; then
    throw "您当前的系统并非CentOS, 无法运行该命令"
  fi

  local version
  version=$(cat /etc/centos-release | awk '{print $4}' | awk -F'.' '{print $1}')

  if [ ! "$version" -eq 7 ] && [ ! "$version" -eq 8 ]; then
    throw "目前仅限CentOS7和CentOS8能够安装Docker"
  fi

  echo "centos${version}"
}

install_docker() {
  local os=$(check_enviroment)

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

    install_docker_${os}

    sudo cp "${papiyas_extension_path}/daemon.json" /etc/docker/daemon.json
    sudo systemctl daemon-reload
    sudo systemctl enable docker

    install_docker_compose

  else
    if ! command_exists docker-compose; then
      install_docker_compose
    fi
  fi

  if ! groups "${USER}" | grep docker &> /dev/null; then
    sudo gpasswd -a "${USER}" docker
  fi

  start_docker

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

start_docker() {
  sudo systemctl status docker &> /tmp/warning
  
  local status=$(cat '/tmp/warning' | awk '{if($1 == "Active:")print $3}' | awk '{print $1}')

  if [ $status == '(dead)' ]; then
    sudo systemctl start docker
  fi

  rm /tmp/warning
}

install_docker_compose() {
  sudo curl -L "https://get.daocloud.io/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
}


permission_denied() {
    docker ps &> /tmp/warning

    if cat /tmp/warning | grep 'permission denied' &> /dev/null; then
       return 0
    fi

    return 1
}

################################################################
## install:laradock
## 
## @description: 安装laradock
## @notice: vm虚拟机中CentOS8无法正常启动容器, aliyun可以.
##
##
################################################################
install::laradock() {
    # 判断是否有权限
    if ! command_exists docker && ! command_exists docker-compose; then
      throw "请先运行papiyas install:docker安装docker后再安装laradock"
    fi

    if permission_denied; then
      newgrp docker << INSTALL
        bash ${papiyas} install:laradock
INSTALL
    else
       if ! docker ps &> /dev/null; then
         throw "Docker未启动, 无法安装laradock"
       fi

       local LARADOCK_PATH
       LARADOCK_PATH=$(eval echo $(get_config app.laradock_path))

       install_laradock
    fi
}

check_requirements() {
  if [ -d "${LARADOCK_PATH}" ]; then
    if [ -f "${LARADOCK_PATH}/.papiyas_installed" ]; then
      ansi --blue "Laradock已下载成功"
      return;
    else
      throw "${LARADOCK_PATH}不为空, 请删除该目录后重试"
    fi
  fi

  if ! command_exists git; then
    if ! sudo yum install git -y; then
      throw "Git安装失败, 无法下载Laradock" 1
    fi
  fi
}

download_laradock() {

  local laradock_repo
  laradock_repo=$(get_config app.laradock_repo)

  if [ -z "${laradock_repo}" ]; then
    laradock_repo='https://gitee.com/anviod/laradock.git'
  fi

  if [ ! -d "${LARADOCK_PATH}" ]; then
    git clone "${laradock_repo}" "${LARADOCK_PATH}"
  fi

  if [ -d "${LARADOCK_PATH}" ]; then
    touch "${LARADOCK_PATH}/.papiyas_installed"
  else
    throw "下载Laradock失败, 请检查网络或更新下载源" 1
  fi
}

function replace_env {
  while [ "$1" ]; do
    sed -i.bak "s/^$1=.*$/$(str_convert "$2")/" "${LARADOCK_PATH}/env-example"
    shift 2
  done
}

set_env() {
  if [ ! -f "${LARADOCK_PATH}/.env-example.papiyas.bak" ]; then
    cp "${LARADOCK_PATH}/env-example" "${LARADOCK_PATH}/.env-example.papiyas.bak"
  else
    cp "${LARADOCK_PATH}/.env-example.papiyas.bak" "${LARADOCK_PATH}/env-example"
  fi

  # delete the lines in env.ini which begin witch # or empty

  local install_node=$(get_config env.WORKSPACE_INSTALL_NODE)

  cp "${papiyas_config_path}/env.ini" "${papiyas_config_path}/env.tmp.ini"

  ## 如果不安装node, 则需要将node相关关闭
  if [ ! "${install_node}" == 'true' ]; then
    sed -i 's/^WORKSPACE_NVM_NODEJS_ORG_MIRROR=.*$/WORKSPACE_NVM_NODEJS_ORG_MIRROR=/' "${papiyas_config_path}/env.tmp.ini"
    sed -i 's/^WORKSPACE_NPM_REGISTRY=.*$/WORKSPACE_NPM_REGISTRY=/' "${papiyas_config_path}/env.tmp.ini"
    sed -i 's/^WORKSPACE_INSTALL_NODE=.*$/WORKSPACE_INSTALL_NODE=false/' "${papiyas_config_path}/env.tmp.ini"
    sed -i 's/^WORKSPACE_INSTALL_YARN=.*$/WORKSPACE_INSTALL_YARN=false/' "${papiyas_config_path}/env.tmp.ini"
  fi

  sed -i "\$a PHP_VERSION=$(get_config app.php_version)" "${papiyas_config_path}/env.tmp.ini"
  sed -i "\$a APP_CODE_PATH_HOST=${workspace_path}" "${papiyas_config_path}/env.tmp.ini"
  
  env=$(cat "${papiyas_config_path}/env.tmp.ini" | awk -F '=' '{if($i !~ "(^#|^ *$)"){print $1, $0}}')
  # repalce
  replace_env $env
  # save to laradock/.env
  cp "${LARADOCK_PATH}/env-example" "${LARADOCK_PATH}/.env"  
  # rollback
  # cp $LARADOCK_PATH"/.env-example.papiyas.bak" $LARADOCK_PATH"/env-example"
  rm -f "${papiyas_config_path}/env.tmp.ini"
  ansi --yellow "配置信息设置成功"
}


set_dockerfile() {
  # workspace


  local workspace_dockerfile='workspace/Dockerfile'

  local APP_CODE_PATH_CONTAINER=$(get_config env.APP_CODE_PATH_CONTAINER)

  if [ -f 'workspace/Dockerfile.bak' ]; then
    cp 'workspace/Dockerfile.bak' "${workspace_dockerfile}"
  else
    cp "${workspace_dockerfile}" 'workspace/Dockerfile.bak'
  fi


  if [ -f 'docker-compose.yml.bak' ]; then
    cp 'docker-compose.yml.bak' "docker-compose.yml"
  else
    cp 'docker-compose.yml' "docker-compose.yml.bak"
  fi



  sed -i 's/ laradock / papiyas /g' "${workspace_dockerfile}"
  sed -i 's/USER laradock/USER papiyas/g' "${workspace_dockerfile}"
  sed -i 's/\/home\/laradock/\/home\/papiyas/g' "${workspace_dockerfile}" 
  sed -i 's/laradock:laradock/papiyas:papiyas/g' "${workspace_dockerfile}"
  sed -i '/WORKDIR \/var\/www/d' "${workspace_dockerfile}"
  sed -i '$a ARG APP_CODE_PATH_CONTAINER' "${workspace_dockerfile}"
  sed -i '$a WORKDIR ${APP_CODE_PATH_CONTAINER}' "${workspace_dockerfile}"

  local install_node=$(get_config env.WORKSPACE_INSTALL_NODE)

  if [ "${install_node}" == 'true' ]; then
    sed -i "s/$(str_convert https://raw.githubusercontent.com/creationix/nvm/)/$(str_convert http://laradock.papiyas.cn/creationix/nvm/)/" "${workspace_dockerfile}"
  fi

  line=$(expr $(get_line workspace: docker-compose.yml) + 4)
  str=$(sed -n "${line}p" docker-compose.yml)
  blank=$(echo "$str" | sed -r 's/( +)[^ ]+.*/\1/')
  sed -i "${line}a - APP_CODE_PATH_CONTAINER=\${APP_CODE_PATH_CONTAINER}" docker-compose.yml
  sed -i "$(expr ${line} + 1)s/^/${blank}/" docker-compose.yml

  local php_fpm_dockerfile='php-fpm/Dockerfile'

  if [ -f 'php-fpm/Dockerfile.bak' ]; then
    cp 'php-fpm/Dockerfile.bak' "${php_fpm_dockerfile}"
  else
    cp "${php_fpm_dockerfile}" 'php-fpm/Dockerfile.bak'
  fi

  sed -i 's/WORKDIR \/var\/www/ARG APP_CODE_PATH_CONTAINER\nWORKDIR ${APP_CODE_PATH_CONTAINER}/' "${php_fpm_dockerfile}"

  line=$(expr $(get_line php-fpm: docker-compose.yml) + 4)
  str=$(sed -n "${line}p" docker-compose.yml)
  blank=$(echo "$str" | sed -r 's/( +)[^ ]+.*/\1/')
  sed -i "${line}a - APP_CODE_PATH_CONTAINER=\${APP_CODE_PATH_CONTAINER}" docker-compose.yml
  sed -i "$(expr ${line} + 1)s/^/${blank}/" docker-compose.yml
}

install_laradock() {
    check_requirements

    download_laradock


    cd "${LARADOCK_PATH}"

    local workspace_path
    workspace_path=$(get_config app.workspace_path)
    local container
    container=$(get_config app.server_list)
    

    set_env

    set_dockerfile

    if ! docker_compose build workspace; then
      throw "workspace构建失败" 1
    fi

    ansi --yellow "Workspace构建成功..."

    if [ -n "${container}" ]; then

      ansi --yellow "开始构建服务容器列表..."

      if ! docker_compose build nginx mysql php-fpm; then
        throw "服务容器构建失败" 1
      fi

      ansi --yellow "服务容器列表构建成功..."
    fi 

    local php_multi
    php_multi=$(get_config app.php_multi)
    local php_version
    php_version=$(get_config app.php_version)
    local php_multi_versions
    php_multi_versions=$(get_config app.php_multi_versions)

    php_multi_versions=($(echo $php_multi_versions | sed "s/${php_version}//g"))

    if [ "${php_multi}" == 'true' ] && [ "${#php_multi_versions[@]}" -gt 0 ]; then
      ansi --yellow "开始构建多版本PHP, 请耐心等待"

      local version
      for version in "${php_multi_versions[@]}"; do
        sed -n '/### PHP-FPM/, /^$/p' docker-compose.yml > tmp.yml
        cp -r php-fpm "php${version}"
        cp tmp.yml "php${version}.yml"
        sed -i "s/PHP-FPM/PHP${version}/" "php${version}.yml" 
        sed -i "s/php-fpm/php${version}/" "php${version}.yml" 
        sed -i "s/\${PHP_VERSION}/${version}/" "php${version}.yml"
        echo -e "$(cat php${version}.yml)" >> docker-compose.yml

        ansi --yellow "正在构建PHP${version}..."
        if ! docker-compose build "php${version}"; then
          throw "PHP${version}构建失败"
        fi
        ansi --yellow "PHP${version}构建完毕..."
      done
    fi

    ansi --yellow "Laradock安装成功! 请尽情享受."
    
}


install::update() {
    echo
}

