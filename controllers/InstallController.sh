#!/usr/bin/env bash



trap 'retry $?' EXIT

retry() {
  if [ ! $1 -eq 0 ] && [ $FAILED_TIMES -lt 4 ]; then
    let ++$FAILED_TIMES
    ansi --red "第${FAILED_TIMES}次安装失败, 正在重新尝试运行...."
    sleep 3
    $(get_controller)::$(get_action)
  fi
}

install::configure() {
  add_option 'f' 'force' $OPTION_NULL '是否强制构建'
  add_option '' 'pull' $OPTION_NULL '始终获取最新的镜像'
  add_option 'q' 'quiet' $OPTION_NULL '不打印任何输出'
  add_option '' 'no-cache' $OPTION_NULL '不使用缓存'
}


export LARADOCK_PATH=$(eval echo $(get_config app.laradock_path))
export COMPOSE_FILE=$(get_config app.compose_file)
# 工作目录
export workspace_path=$(eval echo $(get_config app.workspace_path))


################################################################
## install:docker
## 
## @description: 安装docker和laradock, 执行该命令必须拥有sudo权限
## @notice: 目前仅适用于CentOS7和CentOS8
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

    install_docker_${os}

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

  start_docker

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

## 启动docker
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

## 判断用户是否有执行docker的权限
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
## @option: -f, --force (optional) 强制构建, 当构建完毕后不会重新构建, 如果需要重新构建则需要增加此参数
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

       # 安装laradock时需要用到的一些变量
       local LARADOCK_PATH=$(eval echo $(get_config app.laradock_path))
       local COMPOSE_FILE=$(get_config app.compose_file)
       local no_cache
       ## 如果强制构建会删除当前已下载的laradock重新下载
       if [ -n "$(get_option force)" ]; then
         rm -rf ${LARADOCK_PATH}
         no_cache='--no-cache'
       fi

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

  local laradock_repo=$(get_config app.laradock_repo)

  if [ -z "${laradock_repo}" ]; then
    laradock_repo='https://gitee.com/anviod/laradock.git'
  fi

  # 将laradock下载到LARADOCK_PATH目录
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

###########################################################
##
## 同步配置信息, 该操作在安装laradock以及构建容器时均会执行一次
## 该函数主要做3件事情
## 1. 将用户自定义的数据同步到.env文件中去
## 2. 补充主要容器的dockerfile的不足
## 3. 修改compose_file, 为dockerfile提供对应变量
##
###########################################################
sync_config() {
  local laradock_path=$(eval echo $(get_config app.laradock_path))

  ## 所有操作均在laradock_path目录下执行
  if [ ! -d "${laradock_path}" ]; then
    throw "${laradock_path}不存在"
  fi

  cd "${laradock_path}"

  local env_example="env-example"

  # 对原始文件进行备份
  if [ ! -f "${env_example}.bak" ]; then
    cp "${env_example}" "${env_example}.bak"
  fi

  # 在不对原配置文件更改的情况下去同步配置
  local config_file="${papiyas_config_path}/env.ini"
  local tmp_file="env.tmp.ini"

  cp "${config_file}" "${tmp_file}"

  ##################################################
  ## NODEJS 配置
  ##################################################

  local install_node=$(get_config env.workspace_install_node)

  # 只要没有将node_js安装选项设置为true, 统统认为不安装
  if [ ${install_node} != true ]; then
    sed -i 's/^WORKSPACE_NVM_NODEJS_ORG_MIRROR=.*$/WORKSPACE_NVM_NODEJS_ORG_MIRROR=/' "${tmp_file}"
    sed -i 's/^WORKSPACE_NPM_REGISTRY=.*$/WORKSPACE_NPM_REGISTRY=/' "${tmp_file}"
    sed -i 's/^WORKSPACE_INSTALL_NODE=.*$/WORKSPACE_INSTALL_NODE=false/' "${tmp_file}"
    sed -i 's/^WORKSPACE_INSTALL_YARN=.*$/WORKSPACE_INSTALL_YARN=false/' "${tmp_file}"
  fi
  ##################################################


  ##################################################
  ## 其他基础信息配置
  ##################################################

  # php版本从app.ini中读取
  sed -i "\$a PHP_VERSION=$(get_config app.php_version)" "${tmp_file}"

  # 本地安装路径也从app.ini中读取, 该路径必须为绝对路径或相对于laradock_path的相对路径
  local workspace_path=$(eval echo $(get_config app.workspace_path))
  sed -i "\$a APP_CODE_PATH_HOST=${workspace_path}" "${tmp_file}"

  ##################################################

  # 去除所有注释开头的以及空行
  env=$(cat "${tmp_file}" | awk -F '=' '{if($i !~ "(^#|^ *$)"){print $1, $0}}')

  function replace_config {
    while [ "$1" ]; do
      sed -i.bak "s/^$1=.*$/$(str_convert "$2")/" "${env_example}"
      shift 2
    done
  }

  # repalce
  replace_config $env
  # save to laradock/.env
  cp "${env_example}" ".env"  
  # rollback
  # cp $LARADOCK_PATH"/.env-example.papiyas.bak" $LARADOCK_PATH"/env-example"
  rm -f "${tmp_file}"

  ansi --yellow "配置文件数据同步成功..."


  local compose_file=$(get_config app.compose_file)

  if [ ! -f "${compose_file}.bak" ]; then
    cp "${compose_file}" "${compose_file}.bak"
  fi

  ########################################################################
  ##
  ## workspace/Dockerfile
  ##
  ########################################################################
  local workspace_dockerfile='workspace/Dockerfile'

  if [ ! -f "${workspace_dockerfile}.bak" ]; then
    cp "${workspace_dockerfile}" "${workspace_dockerfile}.bak"
  fi

  sed -i 's/ laradock / papiyas /g' "${workspace_dockerfile}"
  sed -i 's/USER laradock/USER papiyas/g' "${workspace_dockerfile}"
  sed -i 's/\/home\/laradock/\/home\/papiyas/g' "${workspace_dockerfile}" 
  sed -i 's/laradock:laradock/papiyas:papiyas/g' "${workspace_dockerfile}"
  sed -i '/WORKDIR \/var\/www/d' "${workspace_dockerfile}"

  append_dockerfile_config 'WORKDIR' "${workspace_dockerfile}"

  ## Nodejs 太难安装了, 所以替换为我自己的服务器的资源
  if [ ${install_node} = true ]; then
    sed -i "s/$(str_convert https://raw.githubusercontent.com/creationix/nvm/)/$(str_convert http://laradock.papiyas.cn/creationix/nvm/)/" "${workspace_dockerfile}"
  fi


  local install_symfony=$(get_config env.workspace_install_symfony)

  if [ ${install_symfony} = true ]; then
    local line=$(remove_laradock_config 'Symfony' "${workspace_dockerfile}")
    append_dockerfile_config 'Symfony' "${workspace_dockerfile}" "${line}"
  fi


  ########################################################################
  ##
  ## php-fpm/Dockerfile
  ##
  ########################################################################
  local php_fpm_dockerfile='php-fpm/Dockerfile'

  if [ ! -f "${php_fpm_dockerfile}.bak" ]; then
    cp "${php_fpm_dockerfile}" "${php_fpm_dockerfile}.bak"
  fi

  # 添加变量
  append_compose_config 'php-fpm' 'APP_CODE_PATH_CONTAINER=${APP_CODE_PATH_CONTAINER}' "${php_fpm_dockerfile}"
  append_compose_config 'php-fpm' 'TZ=${WORKSPACE_TIMEZONE}' "${php_fpm_dockerfile}"
  
  ## 动态更改工作目录
  local line=$(get_line 'WORKDIR \/var\/www' "${php_fpm_dockerfile}")
  append_dockerfile_config 'WORKDIR' "${workspace_dockerfile}" "${line}"
  sed -i "${line}d" "${php_fpm_dockerfile}"


  ## 设置时区 与 workspace 保持一致
  line=$(expr $(get_line "# Clean up" "${php_fpm_dockerfile}") - 1)
  append_dockerfile_config 'Set Timezone' "${workspace_dockerfile}" "${line}"
}

set_env() {

  ## 备份元配置文件, 每次安装都会调用元配置文件进行编辑
  if [ ! -f "${LARADOCK_PATH}/.env-example.papiyas.bak" ]; then
    cp "${LARADOCK_PATH}/env-example" "${LARADOCK_PATH}/.env-example.papiyas.bak"
  else
    cp "${LARADOCK_PATH}/.env-example.papiyas.bak" "${LARADOCK_PATH}/env-example"
  fi

  # delete the lines in env.ini which begin witch # or empty

  # 判断是否需要安装nodejs
  local install_node=$(get_config env.WORKSPACE_INSTALL_NODE)
  local tmp_env_ini="${papiyas_config_path}/env.tmp.ini"

  cp "${papiyas_config_path}/env.ini" "${papiyas_config_path}/env.tmp.ini"

  ## 如果不安装node, 则需要将node相关关闭
  if [ ! "${install_node}" == 'true' ]; then
    sed -i 's/^WORKSPACE_NVM_NODEJS_ORG_MIRROR=.*$/WORKSPACE_NVM_NODEJS_ORG_MIRROR=/' "${tmp_env_ini}"
    sed -i 's/^WORKSPACE_NPM_REGISTRY=.*$/WORKSPACE_NPM_REGISTRY=/' "${tmp_env_ini}"
    sed -i 's/^WORKSPACE_INSTALL_NODE=.*$/WORKSPACE_INSTALL_NODE=false/' "${tmp_env_ini}"
    sed -i 's/^WORKSPACE_INSTALL_YARN=.*$/WORKSPACE_INSTALL_YARN=false/' "${tmp_env_ini}"
  fi

  sed -i "\$a PHP_VERSION=$(get_config app.php_version)" "${tmp_env_ini}"
  sed -i "\$a APP_CODE_PATH_HOST=${workspace_path}" "${tmp_env_ini}"
  
  env=$(cat "${tmp_env_ini}" | awk -F '=' '{if($i !~ "(^#|^ *$)"){print $1, $0}}')
  # repalce
  replace_env $env
  # save to laradock/.env
  cp "${LARADOCK_PATH}/env-example" "${LARADOCK_PATH}/.env"  
  # rollback
  # cp $LARADOCK_PATH"/.env-example.papiyas.bak" $LARADOCK_PATH"/env-example"
  rm -f "${tmp_env_ini}"
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

  if [ -f "${COMPOSE_FILE}.bak" ]; then
    cp "${COMPOSE_FILE}.bak" "${COMPOSE_FILE}"
  else
    cp "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak"
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

  local line
  local str
  local blank
  line=$(expr $(get_line workspace: ${COMPOSE_FILE}) + 4)
  str=$(sed -n "${line}p" ${COMPOSE_FILE})
  blank=$(echo "$str" | sed -r 's/( +)[^ ]+.*/\1/')
  sed -i "${line}a - APP_CODE_PATH_CONTAINER=\${APP_CODE_PATH_CONTAINER}" ${COMPOSE_FILE}
  sed -i "$(expr ${line} + 1)s/^/${blank}/" ${COMPOSE_FILE}

  local php_fpm_dockerfile='php-fpm/Dockerfile'

  if [ -f 'php-fpm/Dockerfile.bak' ]; then
    cp 'php-fpm/Dockerfile.bak' "${php_fpm_dockerfile}"
  else
    cp "${php_fpm_dockerfile}" 'php-fpm/Dockerfile.bak'
  fi

  sed -i 's/WORKDIR \/var\/www/ARG APP_CODE_PATH_CONTAINER\nWORKDIR ${APP_CODE_PATH_CONTAINER}/' "${php_fpm_dockerfile}"

  line=$(expr $(get_line php-fpm: ${COMPOSE_FILE}) + 4)
  str=$(sed -n "${line}p" ${COMPOSE_FILE})
  blank=$(echo "$str" | sed -r 's/( +)[^ ]+.*/\1/')
  sed -i "${line}a - APP_CODE_PATH_CONTAINER=\${APP_CODE_PATH_CONTAINER}" ${COMPOSE_FILE}
  sed -i "$(expr ${line} + 1)s/^/${blank}/" ${COMPOSE_FILE}
  let ++line

  sed -i "${line}a - TZ=\${WORKSPACE_TIMEZONE}" ${COMPOSE_FILE}
  sed -i "$(expr ${line} + 1)s/^/${blank}/" ${COMPOSE_FILE}


  line=$(expr $(get_line "# Clean up" "${php_fpm_dockerfile}") - 1)
 
  local append=()
  append[0]=###########################################################################
  append[1]='# Set Timezone'
  append[2]=###########################################################################
  append[3]='\ '
  append[4]='ARG TZ=UTC'
  append[5]='ENV TZ ${TZ}'
  append[6]='\ '
  append[7]='RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone'
  append[8]='\ '

  for timezone in "${append[@]}"; do
    sed -i "${line}a ${timezone}" ${php_fpm_dockerfile}
    let ++line
  done
}

install_laradock() {

    # 检查必要软件是否安装
    check_requirements

    # 下载Laradock
    download_laradock

    # 后续操作都在LARADOCK_PATH目录下进行
    cd "${LARADOCK_PATH}"

    # 要构建的容器列表
    local container=($(get_config app.server_list))

    sync_config

    # 构建workspace
    if has_build workspace; then
      ansi --blue "workspace已经构建成功, 不再重复构建"
    else
      if docker_compose build  ${no_cache} workspace; then
        build_success workspace
        local APP_CODE_PATH_CONTAINER=$(get_config env.APP_CODE_PATH_CONTAINER)
        docker_compose up -d workspace
        docker_compose exec workspace bash -c "chown -R papiyas:papiyas ${APP_CODE_PATH_CONTAINER}" 
        ansi --yellow "Workspace构建成功..."
      else
        throw "workspace构建失败" 1
      fi
    fi

    # 构建docker-in-docker
    if has_build docker-in-docker; then
      ansi --blue "docker-in-docker已经构建成功, 不再重复构建"
    else
      if docker_compose build ${no_cache} docker-in-docker; then
        build_success docker-in-docker
      else
        throw "docker-in-docker构建失败" 1
      fi
    fi

    if [ "${#container[@]}" -gt 0 ]; then

      ansi --yellow "开始构建服务容器列表..."

      if ! docker_compose build ${no_cache} "${container[@]}"; then
        throw "服务容器构建失败" 1
      fi

      ansi --yellow "服务容器列表构建成功..."

      build_success ${container[@]}
    fi


    ## 多版本PHP构建
    ## 必须保证php_multi为true, 且php_multi_versions不为空
    local php_multi=$(get_config app.php_multi)
    local php_version=$(get_config app.php_version)
    local php_multi_versions=$(get_config app.php_multi_versions)

    # 将重复的php版本进行过滤
    php_multi_versions=($(echo $php_multi_versions | sed "s/${php_version}//g"))

    if [ "${php_multi}" == 'true' ] && [ "${#php_multi_versions[@]}" -gt 0 ]; then
      ansi --yellow "开始构建多版本PHP, 请耐心等待"

      local version
      for version in "${php_multi_versions[@]}"; do
        local build="php${version}"

        if has_build "${build}"; then
          ansi --blue "容器${build}已经构建完成..."
        else
          local yml="${build}.yml"
          sed -n '/### PHP-FPM/, /^$/p' $COMPOSE_FILE > tmp.yml
          cp -r php-fpm "${build}"
          cp tmp.yml "${yml}"
          sed -i "s/PHP-FPM/PHP${version}/" "${yml}" 
          sed -i "s/php-fpm/php${version}/" "${yml}" 
          sed -i "s/\${PHP_VERSION}/${version}/" "${yml}"
          echo -e "$(cat php${version}.yml)" >> $COMPOSE_FILE

          ansi --yellow "正在构建${build}..."
          if ! docker-compose build ${no_cache} "${build}"; then
            throw "${build}构建失败"
          fi

          ansi --yellow "${build}构建完毕..."
          build_success ${build}
        fi
      done
    fi

    ansi --yellow "Laradock安装成功! 请尽情享受."
}


install::build() {

  sync_config

  local options=()
  local name=$(get_argument name)

  if [ -n "$(get_option quiet)" ]; then
    options[${#options[@]}]='--quiet'
  fi

  if [ -n "$(get_option no-cache)" ]; then
    options[${#options[@]}]='--no-cache'
  fi

  if [ -n "$(get_option pull)" ]; then
    options[${#options[@]}]='--pull'
  fi

  if ! docker_compose build "${options[@]}" "${name}" ; then
     throw "构建${name}失败" 1
  fi
}

