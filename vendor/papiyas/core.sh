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
docker_compose() {
  local laradock_path=$(eval echo $(get_config app.laradock_path))
  local compose_file=$(get_config app.compose_file)

  docker-compose --project-directory=${laradock_path} -f"${laradock_path}/${compose_file}" "$@"
}

has_dockerfile_config() {
  if [ -n "$(get_line "^## ${1} @papiyas" $2)" ]; then
    return 0;
  fi

  return 1
}

#######################################
## 移除原生的配置信息, 并返回行号
##
## @params config_name 要删除的配置命令
## @params dockerfile  要删除配置的dockerfile名称
## @return 返回删除的配置命令所在行号
## 
#######################################
remove_laradock_config() {
  local dockerfile=$2
  local start_line=$(sed -n "/^# ${1}:$/=" "${dockerfile}")

  # 无需移除
  if [ -z "${start_line}" ]; then 
    return;
  fi

  let --start_line
  sed -i "${start_line}, /^###############/d" "${dockerfile}"

  echo ${start_line}
}


#######################################
## 给dockerfile追加内容, 如果已经追加过了则不再追加
##
## @params config_name 要执行的配置命令
## @params dockerfile_name 要追加的dockerfile名称
## @params replace_line 要追加到dockerfile的第几行, 如果是末尾则不需要填写
## 
##
#######################################
append_dockerfile_config() {

  if has_dockerfile_config "$1" "$2"; then
    return;
  fi

  echo "Not return $1"

  local dockerfile="${papiyas_extra_path}/Dockerfile"
  local start_line=$(sed -n "/^## ${1}/=" "${dockerfile}")

  if [ -z "${start_line}" ]; then 
    throw "配置信息${1}无法找到, 请确认是否填写错误"
  fi

  let ++start_line
  local end_line=$(sed -n "${start_line}, /^###############/=" "${dockerfile}" | tail -n 1)
  let start_line-=2

  local loop=0
  local times=$(expr $end_line - $start_line)

  local line
  local replace_line=${3:-'$'}
  sed -n "${start_line}, ${end_line}p" "${dockerfile}" | while true
  do
    read line
    if [ -z "$line" ]; then
      sed -i "${replace_line}G" "${2}"
    else
      echo $line | sed -i "${replace_line}a \\${line}" "${2}"
    fi

    if [ $loop -lt $times ]; then
      let ++loop   
      continue
    else
      break
    fi

  done
}


has_compose_config() {
  local container=$(str_lower $1)
  local flag=${3:-'var'}
  local compose_file=$(get_config app.compose_file)

  case $flag in
    var)
      local value=$2
      local search=$(sed -n "/${container}:/, /^###/p" ${compose_file} | sed -n '/args:/, /:/p' | grep "${value}=")

      # 没找到对应的变量则返回假, 否则返回真
      if [ -z "${search}" ]; then
        return 1
      else
        return 0
      fi
    ;;
    *)
    ;;
  esac

  return 0
}
#######################################
## 给compose file新增变量
##
## @params container 容器名称
## @params value 变量定义
## @params 
## 
##
#######################################
append_compose_config() {
  if has_compose_config $1; then
    return
  fi

  local compose_file=$(get_config app.compose_file)
  local container=$1
  local flag=${3:-'var'}


  case $flag in
    var)
      local value=$2
      local base_line=$(sed -n "/${container}:/=" ${compose_file}) 
      local line=$(sed -n "/${container}:/, /^###/p" ${compose_file} | sed -n '/args:/, /:/=' | tail -n 1)
      line=$(expr $base_line + $line - 2)
      # 获取前缀空格数
      local str=$(sed -n "${line}p" ${compose_file})
      local blank=$(echo "$str" | sed -r 's/( +)[^ ]+.*/\1/')
      # 追加变量定义
      sed -i "${line}a - ${value}" ${compose_file}
      # 空格补足
      sed -i "$(expr ${line} + 1)s/^/${blank}/" ${compose_file}    
    ;;
    *)
    ;;
  esac

}



build_success() {
  local container
  local build_file="${papiyas_extra_path}/build_file"
  
  for container in "$@"; do
    # 不重复写入相同的容器
    if [ ! "$(sed -n "/^${1}\$/p" "${build_file}")" == "${1}" ]; then
      echo "${container}" >> "${build_file}"
    fi
  done
}

has_build() {
  local build_file="${papiyas_extra_path}/build_file"

  # 构建文件不存在, 则表示未构建
  if [ ! -f "${build_file}" ]; then
    return 1
  fi

  # 强制重新构建
  if [ -n "$(get_option force)" ]; then
    return 1
  fi

  # 找到完全匹配的则表示已构建
  if [ "$(sed -n "/^${1}\$/p" "${build_file}")" == "${1}" ]; then
    return 0
  fi

  return 1
}
