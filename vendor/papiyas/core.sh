#!/usr/bin/env bash

#####################################################
##
## 核心函数库
## @author papiyas
##
#####################################################

##################################################
## 获取指定控制器对应的脚本文件路径
##
## @param controller_name 控制器名称
## 
##################################################
get_controller_file() {
  echo ${papiyas_controller_path}/$(to_camel $1)"Controller.sh"
}

##################################################
## 按需加载被调用的控制器
##
## @param controller_name 要加载的控制器名称，默认按需加载
## @throw 当控制器不存在时会抛出异常并结束程序
## 
##################################################
load_controller() {
  local controller_name=${1:-"$(get_controller)"}

  local controller_filename=$(get_controller_file $controller_name)

  if [ -f "${controller_filename}" ]; then
    . "${controller_filename}"
  else
    throw "控制器${controller_name}不存在!"
  fi
}


##################################################
## 获取配置信息
## 配置名称格式为 文件名.键名  其中文件名区分大小写而键名不区分大小写
## 比如要获取config/app.ini文件中的SERVER_LIST的值可以如下调用
## get_config app.server_list
## get_config app.SERVER_LIST
##
## @param name 配置名称
## @return 配置对应的值
## 
##################################################
get_config() {
  local config=($(echo $1 | awk -F'.' '{print $1, $2}'))

  local ini_file="${papiyas_config_path}/${config[0]}.ini"

  if [ -f "${ini_file}" ] && [ -n "${config[1]}" ]; then
     cat "${ini_file}" | sed -n "/^$(str_upper ${config[1]})=/p" | awk -F'=' '{print $2}'
  else
     # 当获取不到时 返回 空
     echo
  fi
}


##########################################################
##
## ansi库, 主要用于美化shell输出
## 详情查看 https://github.com/fidian/ansi
##
##########################################################
ansi() {
    bash "${papiyas_vendor_path}/ansi/ansi" "$@"
}

##########################################################
##
## shell异常抛出, 方便查看逻辑错误
## 应当尽在debug形态下才抛出
## 测试函数 ，暂不完善
##
## @param exception 异常名称, 可不填
## @param message   错误信息
##
##########################################################
throw() {
  local message=$1
  local exit_code=${2:-0}

  local index=0


  ansi --bold "[error]: ${message}"

  while true; do
    if [ ${BASH_LINENO[${index}]} -eq 0 ]; then
      break;
    fi

    ansi --red --bold "In ${BASH_SOURCE[$(expr ${index} + 1)]} Line ${BASH_LINENO[${index}]}:"
    echo -e "$(sed -n "${BASH_LINENO[${index}]}p" "${BASH_SOURCE[$(expr ${index} + 1)]}")\n"

    let ++index
  done

  exit "${exit_code}"
}



### alias ####################################################################

if ! function_exists add_option; then
  add_option() {
    Papiyas::addOption "$@"
  }
fi

if ! function_exists get_option; then
  get_option() {
    Papiyas::getOption "$@"
  }
fi

if ! function_exists add_argument; then
  add_argument() {
    Papiyas::addArgument "$@"
  }
fi

if ! function_exists get_argument; then
  get_argument() {
    Papiyas::getArgument "$@"
  }
fi

if ! function_exists get_controller; then
  get_controller() {
    Papiyas::getController
  }
fi

if ! function_exists get_action; then
  get_action() {
    Papiyas::getAction
  }
fi

#################################################################################



##################################################
## 封装好的docker-compose命令
## 几乎所有命令均调用此函数实现
## 
##################################################
function docker_compose() {
  local laradock_path=$(eval echo $(get_config app.laradock_path))
  local compose_file=$(get_config app.compose_file)

  docker-compose --project-directory=${laradock_path} -f"${laradock_path}/${compose_file}" "$@"
}
