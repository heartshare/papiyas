#!/usr/bin/env bash

Papiyas::run() {
  # 1. 当无参数时设置默认参数
  local command=${1:-'list'}
  
  # 2. 第一个参数必须是命令, 否则无法执行
  if [ ${command:0:1} == '-' ]; then
    ## 当为help指令时,等同于调用list命令
    if [ $command == '--help' ] || [ $command == '-h' ]; then
      command='list'
    else
      throw "第一个参数必须为命令名"
    fi
  fi

  # 3. 获取控制器与方法
  IFS=" " read -r -a commands <<< "$(echo "${command}" | awk -F':' '{print $1, $2}')"

  local controller_name
  local action_name
  case ${#commands[@]} in
    1)
      controller_name='main'
      action_name="${commands[0]}"
    ;;
    2)
      controller_name="${commands[0]}"
      action_name="${commands[1]}"
    ;;
    *)
      throw '命令格式错误'
    ;;
  esac

  # 4. 不允许调用configure方法
  if [ $action_name == 'configure' ]; then
    throw '非法命令!'
  fi

  # 5. 保存控制器与方法名
  Papiyas::setController $controller_name
  Papiyas::setAction $action_name
  
  # 6. 加载控制器脚本文件
  load_controller


  # 7. 判断控制器是否存在
  if ! function_exists "${controller_name}::${action_name}"; then
    throw "${controller_name}控制器不存在${action_name}方法"
  fi

  papiyas::configure

  # 8. 判断是否存在configure方法
  if function_exists "${controller_name}::configure"; then
    ${controller_name}::configure
  fi


  # 9. 进行参数和选项解析
  Papiyas::parese "${@:2}"

  # 10. 如果存在help指令, 则调用对应命令的帮助文档
  if [ $(get_option 'help') ]; then
    papiyas::help
    exit 0
  fi

  # 11. 如果存在debug指令, 则显示相应执行的命令
  if [ $(get_option 'debug') ]; then
    set -x
  fi

  # 12. 调用对应的控制器和方法
  ${controller_name}::${action_name}
}

# 设置控制器
Papiyas::setController() {
  controller_name=$1
}

# 设置方法名
Papiyas::setAction() {
  action_name=$1
}

# 获取控制器
Papiyas::getController() {
  echo $controller_name
}

# 获取方法名
Papiyas::getAction() {
  echo $action_name
}

