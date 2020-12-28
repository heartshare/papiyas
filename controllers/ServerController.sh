#!/usr/bin/env bash

server::configure() {
  add_option 'a' 'all'   "${OPTION_NULL}"  '全部'
  add_option 'f' 'force' "${OPTION_NULL}"  '强制执行'
  add_argument 'server_name' "$INPUT_ARRAY" '服务名称'
}

################################################################
## server:start
## @params server_name (optional) 要启动的服务名称
## @description: 
## +. 当要启动的服务名称为空时, 会启动配置文件中的SERVER_LIST
## +. 如果要启动的服务名称不为空, 则会直接启动这些服务 
## +. 如果服务名称与SERVER_LIST同时为空, 则会报错并结束程序
## @notice:
## + 由于新增多版本php原因, 有时候要启动多个php, 一个一个启动略微麻烦. 可以通过php$启动所有的php版本
## 
## 底层实际调用 docker-compose up -d server_name
################################################################
server::start() {
  local server_name=$(get_argument server_name)

  ## 如果用户未填写服务名, 则读取配置列表中的服务名称
  if [ -z "${server_name}" ]; then
    server_name=$(get_config app.server_list)
  fi

  

  ## 如果配置列表中的服务名称依旧为空, 则报错
  server_name=$(parse_server_name "${server_name}")

  if [ -z "${server_name}" ]; then
    throw '读取配置信息失败, 请完善配置信息或填写要启动的服务名称'
  fi

  docker_compose up -d $server_name
}

## PHP解析
parse_server_name() {
  local server_name=$1

  # 通过php*来快捷启动所有的php版本
  if echo "${server_name}" | grep 'php\$' &> /dev/null; then
    server_name=$(echo "${server_name}" | sed -n 's/php\$//gp')
    # 判断是否开启了多版本php
    local php_multi=$(get_config app.php_multi)

    if [ "${php_multi}" = true ]; then
      local php_version=$(get_config app.php_version)
      local php_multi_versions=$(get_config app.php_multi_versions)
      # 将重复的php版本进行过滤
      php_multi_versions=($(echo "${php_multi_versions}" | sed "s/${php_version}//g"))

      if [ ${#php_multi_versions[@]} -gt 0 ]; then
        local version
        for version in "${php_multi_versions[@]}"; do
          server_name+=" php${version}"
        done
      fi
    fi

    # 无论是否多版本都会启动php-fpm
    if ! echo "${server_name}" | grep 'php-fpm' &> /dev/null; then
      server_name+=" php-fpm"
    fi
  fi

  echo "${server_name}"
}


################################################################
## server:restart
## @params server_name (optional) 要重新启动的服务名称
## @options -a, --all 是否重启所有服务
## @description: 
## +. 当服务名称为空时, 会重新启动配置文件中的SERVER_LIST
## +. 如果服务名称不为空, 则会重新启动这些服务
## +. 如果有-a|--all选项, 则会重启所有已启动服务
## +. 如果服务名称与SERVER_LIST同时为空, 则等同于输入了-a|--all选项
## 
## 底层实际调用 docker-compose restart server_name
################################################################
server::restart() {

  if [ -n "$(get_option all)" ]; then
    docker_compose restart
    return 0
  fi

  local server_name=$(get_argument server_name)

  ## 如果用户未填写服务名, 则读取配置列表中的服务名称
  if [ -z "$server_name" ]; then
    server_name=$(get_config app.server_list)
  fi

  server_name=$(parse_server_name "${server_name}")

  ## 如果配置列表中的服务名称依旧为空, 则重启所有服务
  if [ -z "$server_name" ]; then
    docker_compose restart
    return 0
  fi

  docker_compose restart $server_name
}


################################################################
## server:stop
## @params server_name (optional) 要重新启动的服务名称
## @options -a, --all 是否停止所有服务
## @description: 
## +. 当服务名称为空时, 会停止配置文件中的SERVER_LIST
## +. 如果服务名称不为空, 则会停止这些服务
## +. 如果有-a|--all选项, 则会停止所有已启动服务
## +. 如果服务名称与SERVER_LIST同时为空, 则等同于输入了-a|--all选项
## 
## 底层实际调用 docker-compose stop server_name
################################################################
server::stop() {

  if [ -n "$(get_option all)" ]; then
    docker_compose stop
    return 0
  fi

  local server_name=$(get_argument server_name)

  ## 如果用户未填写服务名, 则读取配置列表中的服务名称
  if [ -z "$server_name" ]; then
    server_name=$(get_config app.server_list)
  fi

  server_name=$(parse_server_name "${server_name}")

  ## 如果配置列表中的服务名称依旧为空, 则重启所有服务
  if [ -z "$server_name" ]; then
    docker_compose stop
    return 0
  fi

  docker_compose stop $server_name
}


################################################################
## server:ps
## @params server_name (optional) 要查看状态的服务名称
## @description: 
## +. 当服务名称为空时, 会查看所有已运行的服务名称
## +. 如果服务名称不为空, 则会查看这些服务的状态
## 
## 底层实际调用 docker-compose ps server_name
################################################################
server::ps() {
  local server_name=$(get_argument server_name)

  ## 如果用户未填写服务名, 则读取配置列表中的服务名称
  server_name=$(parse_server_name "${server_name}")

  if [ -z "$server_name" ]; then
    docker_compose ps
  else
    docker_compose ps $server_name
  fi
}


################################################################
## server:top
## @params server_name (optional) 要查看状态的服务名称
## @description: 
## +. 当服务名称为空时, 会查看所有已运行的服务名称
## +. 如果服务名称不为空, 则会查看这些服务的状态
## 
## 底层实际调用 docker-compose top server_name
################################################################
server::top() {
  local server_name=$(get_argument server_name)

  ## 如果用户未填写服务名, 则读取配置列表中的服务名称
  server_name=$(parse_server_name "${server_name}")

  if [ -z "$server_name" ]; then
    docker_compose top
  else
    docker_compose top $server_name
  fi
}

################################################################
## server:remove
## @options -f, --force 不进行提示, 强制移除服务
## @description: 
##  +. 移除所有服务
## 
## 底层实际调用 docker-compose down
################################################################
server::remove() {

  if [ -n "$(get_option force)" ]; then
    docker_compose down
    return 0
  fi

  local answer
  echo 
  ansi --yellow "是否移除所有容器, 该操作不可逆!(y|N)"
  ansi --red -n "> "
  read answer

  case $answer in
    y|Y)
      docker_compose down
    ;;
    *)
      ansi --white --bold "用户取消移除操作"
    ;;
  esac
}
