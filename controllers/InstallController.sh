#!/usr/bin/env bash

# trap 'retry' EXIT

# retry() {
#   ansi --red "安装失败, 正在重新尝试运行...."
#   sleep 3
#   $(get_controller)::$(get_action)
# }

install::configure() {
  add_option 'f' 'force' $OPTION_NULL '是否强制构建'
  add_option '' 'pull' $OPTION_NULL '始终获取最新的镜像'
  add_option 'q' 'quiet' $OPTION_NULL '不打印任何输出'
  add_option '' 'no-cache' $OPTION_NULL '不使用缓存'
  add_argument 'name' $INPUT_ARRAY
}

################################################################
## install:docker
## 
## @description: 安装docker和laradock, 执行该命令必须拥有sudo权限
## @notice: 目前仅适用于CentOS7和CentOS8
##
################################################################
install::docker() {
  ## 根据指定操作系统进行安装docker
  get_os

  install_docker_"${OS}"
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

    local laradock_path=$(get_laradock_path)
    install_laradock
  fi
}

######################################################################
##
## 检查git是否安装 以及laradock是否下载
##
######################################################################
check_requirements() {
  if ! command_exists git; then
    install_git_{OS}
  fi

  ## 之前的判断对不通过papiyas命令安装的laradock检查无法通过
  ## 修改检查逻辑, 增加git源校验. 只要目录是一个git仓库即通过校验
  if [ -d "${laradock_path}" ]; then
    
    if [ -f "${laradock_path}/.papiyas_installed" ]; then
      ansi --blue "Laradock已下载成功"
      return;
    elif ! git remote -v &> /dev/null; then
      throw "${laradock_path}不为空, 请删除该目录后重试"
    fi
  fi
}

download_laradock() {

  local laradock_repo=$(get_config app.laradock_repo)

  if [ -z "${laradock_repo}" ]; then
    laradock_repo='https://gitee.com/anviod/laradock.git'
  fi

  # 将laradock下载到LARADOCK_PATH目录
  if [ ! -d "${laradock_path}" ]; then
    git clone "${laradock_repo}" "${laradock_path}"
  fi

  if [ -d "${laradock_path}" ]; then
    touch "${laradock_path}/.papiyas_installed"
  else
    throw "下载Laradock失败, 请检查网络或更新下载源" 1
  fi
}

install_laradock() {

    # 检查必要软件是否安装
    check_requirements

    # 下载Laradock
    download_laradock

    # 要构建的容器列表
    local container=$(get_config app.server_list)

    # 由于新增了php$容器代表所有的php, 在安装的时候需要将之过滤. 并替换为php-fpm
    container=($(echo "${container}" | sed -n 's/php\$/php-fpm/gp'))

    sync_config

    # 构建workspace
    if has_build workspace; then
      ansi --blue "workspace已经构建成功, 不再重复构建"
    else
      if docker_compose build workspace; then
        build_success workspace
        local container_path=$(get_config env.app_code_path_container)
        docker_compose up -d workspace
        local user=$(get_workspace_user)
        docker_compose exec -T workspace bash -c "chown -R ${user}:${user} ${container_path}"
        ansi --yellow "Workspace构建成功..."
      else
        throw "workspace构建失败" 1
      fi
    fi

    # 构建docker-in-docker
    if has_build docker-in-docker; then
      ansi --blue "docker-in-docker已经构建成功, 不再重复构建"
    else
      if docker_compose build docker-in-docker; then
        build_success docker-in-docker
      else
        throw "docker-in-docker构建失败" 1
      fi
    fi

    if [ "${#container[@]}" -gt 0 ]; then

      ansi --yellow "开始构建服务容器列表..."

      local c
      for c in "${container[@]}"; do
        if ! has_build "${c}"; then
          if ! docker_compose build "${c}"; then
            throw "服务容器${c}构建失败" 1
          fi

          docker_compose up -d "${c}"
          build_success "${c}"
        fi  
      done

      ansi --yellow "服务容器列表构建成功..."
    fi


    install::php false

   
    ansi --yellow "Laradock安装成功! 请尽情享受."
}


################################################################
## install:php
## 
## @description: 单独安装多版本php
## @notice: 
##
##
################################################################
install::php() {

  # 不重复进行同步配置文件
  if [ "${1}" != false ]; then
    sync_config

    check_permission
  fi


  local compose_file=$(get_compose_file)
  local workspace_path=$(get_workspace_path)

  ## 多版本PHP构建
  ## 目前还是使用laradock的Dockerfile进行构建, 后续可能会独立出来进行一些适配的修改
  ## 必须保证php_multi为true, 且php_multi_versions不为空
  local php_multi=$(get_config app.php_multi)
  local php_version=$(get_config app.php_version)
  local php_multi_versions=$(get_config app.php_multi_versions)

  if [ ! -f "${workspace_path}/.composer/bin/composer" ]; then
    docker_compose exec -T --user="$(get_workspace_user)" workspace bash -c "mkdir -p .composer/bin/ && cp /usr/local/bin/composer .composer/bin/composer"
  fi

  # 将重复的php版本进行过滤
  php_multi_versions=($(echo $php_multi_versions | sed "s/${php_version}//g"))

  if [ "${php_multi}" == 'true' ] && [ "${#php_multi_versions[@]}" -gt 0 ]; then
    ansi --yellow "开始构建多版本PHP, 请耐心等待"

    local version
    local composer_repo=$(get_config env.WORKSPACE_COMPOSER_REPO_PACKAGIST)
    for version in "${php_multi_versions[@]}"; do
      local build="php${version}"

      if has_build "${build}"; then
        ansi --blue "容器${build}已经构建完成..."
      else
        local yml="${build}.yml"
        sed -n '/### PHP-FPM/, /^$/p' "${compose_file}" > tmp.yml
        cp -r php-fpm "${build}"
        rm -f "${build}/php*ini"
        cp "php-fpm/${build}.ini" "${build}"
        cp tmp.yml "${yml}"
        sed -i "s/PHP-FPM/PHP${version}/" "${yml}" 
        sed -i "s/php-fpm/php${version}/" "${yml}" 
        sed -i "s/\${PHP_VERSION}/${version}/" "${yml}"
        if ! has_compose_config "${build}" '' 'container'; then
          echo -e "$(cat ${yml})" >> "${compose_file}"
        fi

        ansi --yellow "正在构建${build}..."
        if ! docker-compose build "${build}"; then
          throw "${build}构建失败"
        fi

        docker_compose up -d "${build}"

        if [ -n "${composer_repo}" ]; then
          docker_compose exec -T --user=www-data "${build}"  php  /var/www/.composer/bin/composer config -g repo.packagist composer "${composer_repo}"
        fi

        ansi --yellow "${build}构建完毕..."
        build_success "${build}"
      fi
    done
  fi

   ansi --yellow "多版本php构建完成..."
}





##################################################################
## install:build
## 
## @options --quiet (optional) 构建过程中不输出任何数据
## @options --no-cache (optional) 不使用缓存
## @options --pull (optional) 使用最新的镜像
## @params  name 要构建的容器名称(可以是多个)
##
##################################################################
install::build() {
  local options=()
  local name=$(get_argument name)

  if [ -z "${name}" ]; then
    throw "请输入要构建的服务名称"
  fi

  sync_config

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


install::go() {
  if ! command_exists wget; then
    if ! sudo yum install wget -y; then
      throw "安装wget失败"
    fi
  fi

  if ! wget https://dl.google.com/go/go1.15.6.linux-amd64.tar.gz; then
    throw "下载go安装包失败"
  fi

  if ! sudo tar -C /usr/local -xzf go1.15.6.linux-amd64.tar.gz; then
    throw "解压go语言包失败"
  fi

  if ! cat /etc/profile | grep '/usr/local/go/bin' &> /dev/null; then
    cat /etc/profile > ./tmp.profile
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ./tmp.profile
    sudo cp ./tmp.profile /etc/profile
    rm -f ./tmp.profile
  fi
  
  ansi --bold "安装完毕, 请运行 source /etc/profile 之后再执行 go version 即可"
}

