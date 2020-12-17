#!/usr/bin/env bash


main::configure() {
    add_option 'u' 'user' $OPTION_OPTIONAL '容器操作的用户名' 'laradock'
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
## php
## 
## @option user (optional)
## @description: 
## @memo: 
## 
################################################################
main::php() {
  docker_compose exec --user=$(get_option user) workspace php  "${params[@]}";
}


################################################################
## npm
## 
## @option user (optional)
## @description: 
## @memo: 
## 
################################################################
main::npm() {
  echo docker_compose exec --user="$(get_option user)" workspace npm "${params[@]}"
}


################################################################
## mysql
## 
## @option user (optional)
## @description: 
## @memo: 
## 
################################################################
main::mysql() {
  echo docker_compose exec --user=mysql mysql mysql "${params[@]}"
}


main::list() {
  echo
}