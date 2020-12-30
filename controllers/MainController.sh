#!/uname/bin/env bash


main::configure() {
  ## 因为docker-compose进入容器有user选项, 这里如果填写user会导致冲突. 所以使用uname
  add_option '' 'uname' $OPTION_OPTIONAL '容器操作的用户名'
  ## 使用指定的php版本号来执行php指令
  add_option '' 'php-version' $OPTION_REQUIRE 'PHP版本号'
}


################################################################
## docker-compose
## @alias: 可使用简写命令dc代替
## @description: 直接调用docker-compose执行原生指令
## @memo: 由于是全局调用, --project-directory指向了laradock目录
##   -f 指向了配置文件中的compose_file.
## 
################################################################
main::docker-compose() {
  docker_compose "${params[@]}"
}

################################################################
## dc
## @alias: docker-compose的简写
## @description: 直接调用docker-compose执行原生指令
## @memo: 由于是全局调用, --project-directory指向了laradock目录
##   -f 指向了配置文件中的compose_file.
## 
################################################################
main::dc() {
  main::docker-compose
}


################################################################
## check-permission
## @description: 如果当前操作docker会报权限不足，则调用此命令给予权限
## @notice: 使用papiyas命令安装docker的。可能需要sudo权限
## 
################################################################
# main::check-permission() {
#   if ! groups "${USER}" | grep docker &> /dev/null; then
#     sudo gpasswd -a "${USER}" docker
#   fi

#   check_permission
# }

################################################################
## php
## 
## @option --uname (optional) 默认为www-data
## @option --php-version 可指定要执行的php版本号, 确保已经构建了多版本PHP且容器已经运行
## @description: 
##   + 可执行原生php命令, 如无参数则会默认执行php -v
##   + 如果觉得指定版本执行太麻烦, 可以使用简写来代替
##     papiyas php --php-version=7.4 等同于 papiyas php7.4
## @append:
##   + 以下特性仅在被papiyas管理的项目中起作用
##   + 调用php指令时会自动调用该项目创建时所用的php版本
##   + 在laravel项目中可以将papiyas php artisan命令简写为papiyas artisan
##   + 在symfony项目中可以将papiyas php console命令简写为papiyas console
## 
################################################################
main::php() {
  local php_version=$(get_config app.php_version)
  local user_php_version=$(get_option php-version)

  local user=$(get_option uname)
  user=${user:-www-data}

  local container


  if [ -f ".papiyas" ]; then
    source .papiyas

    container=$project_php_version

    if [ -z "${container}" ] || [ -z "${project_name}" ]; then
      throw "项目管理文件缺失, 无法获取php版本号"
    fi

    if [ ${params[0]} == 'artisan' ] && [ ${project_framework} == 'laravel' ]; then
      params[0]="${project_name}/artisan"
    elif [ ${params[0]} == 'console' ]  && [ ${project_framework} == 'symfony' ]; then
      params[0]="${project_name}/bin/console"
    fi

  else
    if [ -z "${user_php_version}" ]; then
      container="php-fpm"
    elif [ "${php_version}" == "${user_php_version}" ]; then
      container='php-fpm'
    else
      container='php'${user_php_version}
    fi
  fi

  ## 防止空php指令卡住, 默认显示版本号
  if [ ${#params[@]} -eq 0 ]; then
    params[0]='-v'
  fi
  
  docker_compose exec --user=$user $container php ${params[@]};
}


################################################################
## composer
## 
## @option --uname (optional) 默认为www-data
## @option --php-version 可指定要执行的php版本号, 确保已经构建了多版本PHP且容器已经运行
## @description: 
##   + 可执行原生php命令, 如无参数则会默认执行php -v
##   + 如果觉得指定版本执行太麻烦, 可以使用简写来代替
##     papiyas composer --php-version=7.4 等同于 papiyas composer7.4
## @append:
##   + 以下特性仅在被papiyas管理的项目中起作用
##   + 调用composer指令时会自动调用该项目创建时所用的php版本
## 
################################################################
main::composer() {
  local php_version=$(get_config app.php_version)
  local user_php_version=$(get_option php-version)

  local user=$(get_option uname)
  user=${user:-www-data}

  local workspace_path=$(get_workspace_path)

  # 防止文件被意外删除
  if [ ! -f "${workspace_path}/.composer/bin/composer" ]; then
    docker_compose exec --user="$(get_workspace_user)" workspace bash -c "mkdir -p .composer/bin/ && cp /usr/local/bin/composer .composer/bin/composer"
  fi

  local container

  if [ -f ".papiyas" ]; then
    source .papiyas

    container=$project_php_version

    if [ -z "${container}" ]  || [ -z "${project_name}" ]; then
      throw "项目管理文件缺失, 无法获取php版本号"
    fi

    if [ ${#params[@]} -gt 0 ]; then
      local param
      for param in "${params[@]}"; do
        if [ "${param::1}" != "-" ]; then
          params[${#params[@]}]='-d'
          params[${#params[@]}]="${project_name}"
          break
        fi
      done
    fi

  else
    if [ -z "${user_php_version}" ]; then
      container="php-fpm"
    elif [ "${php_version}" == "${user_php_version}" ]; then
      container='php-fpm'
    else
      container='php'${user_php_version}
    fi
  fi

  docker_compose exec --user=$user $container php .composer/bin/composer ${params[@]}
}


################################################################
## npm
## 
## @option --uname (optional) 默认为papiyas
## @description: 如果没有安装nodejs, 则该指令无法执行成功
## 
################################################################
main::npm() {
  local user=$(get_option uname)
  user=${user:-papiyas}
  docker_compose exec --user=$user workspace npm "${params[@]}"
}


################################################################
## mysql
## 
## @option --uname (optional) 默认为mysql
## @description:
##   + 调用mysql服务容器的mysql指令
##   + 如果不输入用户名和密码则会调用默认的非root账号进行登录(env.ini)
## 
################################################################
main::mysql() {
  local user=$(get_option uname)
  user=${user:mysql}

  # 当不填写内容时会已默认非root账号登录
  # 如果用户更改过密码或账号则会无法登录
  if [ ${#params[@]} -eq 0 ]; then
    params[0]='-u'$(get_config env.mysql_user)
    params[1]='-p'$(get_config env.mysql_password)
  fi

  docker_compose exec --user=$user mysql mysql "${params[@]}"
}


main::list() {
  local papiyas_version=0.2.0
  echo -e "\033[34mPapiyas\033[0m - Laradock Manager Script: \033[31m${papiyas_version}\033[0m\n"
  echo -e "\033[33mUsage:\033[0m"
  echo -e "    command [options] [arguments]\n"

  echo -e "\033[33mAvailable commands:\033[0m"
  echo -e "\033[31m    list\033[0m                     显示Papiyas命令列表"
  # echo -e "\033[31m    check-permission\033[0m         当权限不足时调用此命令赋予权限，可能需要root权限"
  echo -e "\033[31m    docker-compose\033[0m           执行docker-compose原生命令, 简写dc"
  echo -e "\033[31m    php\033[0m                      执行php命令"
  echo -e "\033[31m    composer\033[0m                 执行composer命令"
  echo -e "\033[31m    npm\033[0m                      执行npm命令"
  echo -e "\033[31m    mysql\033[0m                    执行mysql命令"

  echo

  echo -e "\033[33m  server:\033[0m"
  echo -e "\033[31m    server:start\033[0m             启动服务容器"
  echo -e "\033[31m    server:stop\033[0m              停止服务容器"
  echo -e "\033[31m    server:restart\033[0m           重启服务容器"
  echo -e "\033[31m    server:remove\033[0m            移除所有服务容器"
  echo -e "\033[31m    server:ps\033[0m                查看服务容器状态"
  echo -e "\033[31m    server:top\033[0m               查看服务容器详细状态"

  echo

  echo -e "\033[33m  install:\033[0m"
  echo -e "\033[31m    install:docker\033[0m           安装docker和laradock"
  echo -e "\033[31m    install:laradock\033[0m         安装laradock"
  echo -e "\033[31m    install:build\033[0m            重新构建指定容器"

  echo

  echo -e "\033[33m  project:\033[0m"
  echo -e "\033[31m    project:create\033[0m           创建一个新项目, 可支持laravel, symfony, yii"
  echo -e "\033[31m    project:conf\033[0m             查看当前或者指定项目的配置文件"

  echo
  ansi --blue "目前papiyas正处于开发阶段, 在使用方面可能有诸多不足需要优化或者有影响使用的bug, 敬请谅解"
}


main::rollback() {
  local action=$(get_action)

  if [ -f '.papiyas' ]; then
    source '.papiyas'

    if [ $action == 'artisan' ] && [ ${project_framework} == 'laravel' ]; then
      bash ${papiyas} php --uname=$(get_option uname) artisan "${params[@]}"
      return
    elif [ $action == 'console' ]  && [ ${project_framework} == 'symfony' ]; then
      bash ${papiyas} php --uname=$(get_option uname) console "${params[@]}"
      return
    fi
  fi

  ## 快捷php版本
  if [[ "$action" =~ php ]]; then
    bash ${papiyas} php --uname=$(get_option uname) --php-version=${action#php}  "${params[@]}"
    return
  fi

   ## 快捷php版本 composer
  if [[ "$action" =~ composer ]]; then
    bash ${papiyas} composer --uname=$(get_option uname) --php-version=${action#composer}  "${params[@]}"
    return
  fi

  throw "${action}指令不存在"
}
