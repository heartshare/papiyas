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


##################################################
## 获取Laradock_path的信息, 防止为空等非法路径
## 
##################################################
get_laradock_path() {
  local laradock_path=$(eval echo $(get_config app.laradock_path))

  if [ -z "${laradock_path}" ] || [ "${laradock_path}" = '.' ] || [ "${laradock_path}" = '..' ]; then
    laradock_path="${papiyas_path}/../laradock"
  elif [ ! -d "${laradock_path}" ]; then
    if ! mkdir -p "${laradock_path}"; then
      laradock_path="${papiyas_path}/../laradock"
    fi
  fi
  
  echo "${laradock_path}"
}

##################################################
## 获取Laradock_path的信息, 防止为空等非法路径
## 
##################################################
get_compose_file() {
  local compose_file=$(get_config app.compose_file)

  if [ ! -f "${laradock_path}/${compose_file}" ] && [ "${compose_file##*.}" != 'yml' ]; then
    compose_file="docker-compose.yml"
  fi

  echo "${compose_file}"
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

  append_compose_config 'workspace' 'APP_CODE_PATH_CONTAINER=${APP_CODE_PATH_CONTAINER}'
  append_dockerfile_config 'WORKDIR' "${workspace_dockerfile}"

  ## Nodejs 太难安装了, 所以替换为我自己的服务器的资源
  if [ ${install_node} = true ]; then
    sed -i "s/$(str_convert https://raw.githubusercontent.com/creationix/nvm/)/$(str_convert http://laradock.papiyas.cn/creationix/nvm/)/" "${workspace_dockerfile}"
  fi


  local install_symfony=$(get_config env.workspace_install_symfony)

 

  if [ ${install_symfony} = true ]; then
    local line=$(remove_laradock_config 'Symfony' "${workspace_dockerfile}")
    if [ -n "${line}" ]; then
      append_dockerfile_config 'Symfony' "${workspace_dockerfile}" "${line}"
    fi
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
  append_compose_config 'php-fpm' 'APP_CODE_PATH_CONTAINER=${APP_CODE_PATH_CONTAINER}'
  append_compose_config 'php-fpm' 'TZ=${WORKSPACE_TIMEZONE}'
  
  ## 动态更改工作目录
  local line=$(get_line 'WORKDIR \/var\/www' "${php_fpm_dockerfile}")
  ## 防止2次错误处理
  if [ -n "${line}" ]; then
    append_dockerfile_config 'WORKDIR' "${php_fpm_dockerfile}" "${line}"
    sed -i "${line}d" "${php_fpm_dockerfile}"
  fi

  ## 设置时区 与 workspace 保持一致
  line=$(expr $(get_line "# Clean up" "${php_fpm_dockerfile}") - 1)

  append_dockerfile_config 'Set Timezone' "${php_fpm_dockerfile}" "${line}"
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


  let ++start_line
  local end_line=$(sed -n "${start_line}, /^###############/=" "${dockerfile}" | tail -n 2 | head -n 1)
  let start_line-=2

  sed -i "${start_line}, ${end_line}d" "${dockerfile}"

  let --start_line

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
  local replace_line=${3:-$(sed -n "$=" "${2}")}
  sed -n "${start_line}, ${end_line}p" "${dockerfile}" | while true
  do
    read line
    if [ -z "$line" ]; then
      sed -i "${replace_line}G" "${2}"
    else
      echo $line | sed -i "${replace_line}a \\${line}" "${2}"
    fi

    let ++replace_line

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
      local value=$(echo $2 | awk -F'=' '{print $1}')
      local search=$(sed -n "/${container}:/, /^###/p" ${compose_file} | sed -n '/args:/, /:/p' | grep "${value}=")

      # 没找到对应的变量则返回假, 否则返回真
      if [ -z "${search}" ]; then
        return 1
      else
        return 0
      fi
    ;;
    container)
      local search=$(sed -n "/${container}:/=" ${compose_file})

      if [ -z "${search}" ]; then
        return 1;
      else
        return 0;
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
  if has_compose_config "${1}" "${2}"; then
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

  if [ ! -f "${build_file}" ]; then
    touch "${build_file}"
  fi
  
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

  # 找到完全匹配的则表示已构建
  if [ "$(sed -n "/^${1}\$/p" "${build_file}")" == "${1}" ]; then
    return 0
  fi

  return 1
}
