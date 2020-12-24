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
  if [ "${params[0]}" == "build" ]; then
    if docker_compose "${params[@]}"; then
      echo
    fi
  else
    docker_compose "${params[@]}"
  fi
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
## php
## 
## @option --uname (optional) 默认为www-data
## @option --php-version 可指定要执行的php版本号, 确保已经构建了多版本PHP且容器已经运行
## @description: 
##   + 可执行原生php命令, 如无参数则会默认执行php -v
##   + 如果觉得指定版本执行太麻烦, 可以使用简写来代替
##     papiyas php --php-version=7.4 等同于 papiyas php7.4
## 
################################################################
main::php() {
  local php_version=$(get_config app.php_version)
  local user_php_version=$(get_option php-version)

  local user=$(get_option uname)
  user=${user:-www-data}

  local container
  if [ -z "${user_php_version}" ]; then
    container="php-fpm"
  elif [ "${php_version}" == "${user_php_version}" ]; then
    container='php-fpm'
  else
    container='php'${user_php_version}
  fi

  # if ! has_build "$container"; then
  #   throw "${container}容器未安装, 无法执行."
  # fi

  ## 防止空php指令卡住, 默认显示版本号
  if [ ${#params[@]} -eq 0 ]; then
    params[0]='-v'
  fi
  
  docker_compose exec --user=$user $container php "${params[@]}";
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
  user=${user:papiyas}
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
  echo
}


main::rollback() {
  local action=$(get_action)

  if [[ "$action" =~ php ]]; then
    bash ${papiyas} php -u$(get_option uname) --php-version=${action#php}  "${params[@]}"
    return
  fi

  throw "${action}指令不存在"
}