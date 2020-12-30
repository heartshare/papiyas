#!/usr/bin/env bash

##############################################################
##
## 核心入口文件
## @author papiyas
##
##############################################################



##############################################################
## 入口函数
## 对命令进行解析 并 分发至相对应的控制器中
## 
## @param $@ 用于执行命令脚本所传入的所有参数
##
##############################################################
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


  local callback=${controller_name}::${action_name}
  # 7. 判断控制器是否存在
  if ! function_exists "${callback}"; then
    if function_exists "${controller_name}::rollback"; then
      callback=${controller_name}::rollback
    else
      throw "${controller_name}控制器不存在${action_name}方法"
    fi
  fi

  Papiyas::configure

  # 8. 判断是否存在configure方法
  if function_exists "${controller_name}::configure"; then
    ${controller_name}::configure
  fi


  # 9. 进行参数和选项解析
  Papiyas::parse "${@:2}"

  # 10. 如果存在help指令, 则调用对应命令的帮助文档
  if [ $(get_option 'help') ]; then
    Papiyas::help
    exit 0
  fi

  # 11. 如果存在debug指令, 则显示相应执行的命令
  if [ $(get_option 'debug') ]; then
    set -x
  fi

  # 12. 调用对应的控制器和方法
  ${callback}
}

########################################################
## 命令行参数与选项解析
##
## @param $@ 用户执行命令脚本所传入的所有参数
## 
########################################################
Papiyas::parse() {

  #### 1. 用来对命令参数索引赋值, 如果遇到为数组类型的参数,则后续所有参数皆会被此数组参数接受
  local argument_size=0

  while [ -n "$1" ]; do
    local arg  # 去除前缀-和--的用户输入参数
    local option_name # 选项名
    local option_value # 选项值
    local is_required # 是否未必选参数

    # 长选项解析
    if [[ ${1::2} == '--' ]]; then

      arg=${1:2} # 去除--
      option_name=${arg%%=*} # 把第一个等号后面的内容全部截取掉
      option_value=${arg#*=} # 把第一个等号等号前面的内容截取掉

      # 不存在等号时两者相等, 则选项值为空
      if [[ $option_value == $option_name ]]; then 
        option_value=''
      fi

       # 判断是否存在长选项
      if [ -n "${input_long_options[${option_name}]}" ]; then

         # 如果选项值为空且存在默认值, 则赋予默认值
        if [ -z "${option_value}" ] && [ -n "${input_map[${option_name}_default]}" ]; then 
          option_value=${input_map[${option_name}_default]};
        fi

        local short_option_name
        ## 如果该长选项有对应短选项, 则读取短选项存储的数据
        if [[ "${input_long_options[${option_name}]}" == 1 ]]; then 
          is_required=${input_map[${option_name}_required]}
        else
          is_required=${input_map[${input_long_options[${option_name}]}"_required"]}
          short_option_name=${input_long_options[${option_name}]}
        fi

        case $is_required in
          $OPTION_NULL)
          # 无参数的选项只要存在则为1
            output_options[$option_name]=1
          ;;
          $OPTION_REQUIRE)
            if [ -z "${option_value}" ]; then
              throw "选项${option_name}为必填项"
            fi

            output_options[$option_name]=$option_value
          ;;
          $OPTION_OPTIONAL)
            # 可选项, 只在有值时进行赋值
            if [ -n "${option_value}" ]; then
              output_options[$option_name]=$option_value
            fi
          ;;
          *)
            throw "选项${option_name}的参数规则不正确"
          ;;
        esac

        if [ -n "${short_option_name}" ]; then
          output_options[$short_option_name]=${output_options[$option_name]}
        fi

      else
        # throw "选项${option_name}不存在"
        # 由于要执行原生指令, 所以对不存在的选项名不再报错. 存储后提供给原生执行做参数使用
        params[${#params[@]}]="$1"
      fi

    # 短选项解析
    elif [[ ${1::1} == '-' ]]; then

      option_name=${1:1:1} # 去除-后的第一个字符为选项名
      option_value=${1:2}  # 剩余字符为选项值

      if [ -n "${input_short_options[${option_name}]}" ]; then

        case ${input_map[${option_name}_required]} in
          $OPTION_NULL)
            output_options[$option_name]=1
          ;;
          $OPTION_REQUIRE)
            # 无选项值
            if [ -z "${option_value}" ]; then
              if  [[ ${1::1} == '-' ]]; then
                ## 后续仍为选项, 而非值
                if [ -n "${input_map[${option_name}_default]}" ]; then 
                  option_value=${input_map[${option_name}_default]}
                else
                  throw "选项${option_name}为必填项"
                fi
              else
                option_value=$2
                shift
              fi
            fi

            output_options[$option_name]=$option_value
          ;;
          $OPTION_OPTIONAL)
            if [ -z "${option_value}" ]; then
              if [[ ${1::1} == '-' ]]; then
              ## 后续仍为选项, 而非值
                if [ -n "${input_map[${option_name}_default]}" ]; then 
                  option_value=${input_map[${option_name}_default]}
                else
                  continue
                fi
              else
                option_value=$2
                shift
              fi
            fi

            output_options[$option_name]=$option_value
          ;;
          *)
            throw "选项${option_name}的参数规则不正确"
          ;;
        esac


         ## 如果短选项有对应长选项, 则同时设置长选项存储的数据
        if [[ "${input_short_options[${option_name}]}" != 1 ]]; then 
          output_options[${input_short_options[${option_name}]}]=${output_options[$option_name]}
        fi

      else
        # throw "选项${option_name}不存在"
        # 由于要执行原生指令, 所以对不存在的选项名不再报错. 存储后提供给原生执行做参数使用
        params[${#params[@]}]="$1"
      fi

    # 参数解析
    else
      # 只要不是-开头的全部为参数, 依次存入到参数列表中
      if [ -n "${input_arguments[${argument_size}]}" ]; then
        output_arguments[${input_arguments[${argument_size}]}]=$1
        let ++argument_size
      # 如果参数存储到头了, 则判断最后一个参数是否为数组
      # 如果是数组则存储到参数列表中  
      else
        local old_size=$(expr $argument_size - 1)     
        local key=${input_map[${input_arguments[${old_size}]}"_argument"]}
        if [ -n "$key" ] && [ $key -eq $INPUT_ARRAY ]; then
          output_arguments["${input_arguments[${old_size}]}"]+=' '$1
        else
          params[${#params[@]}]="$1"
        fi
      fi
    fi

    shift
  done
}


Papiyas::configure() {
  add_option 'h' 'help'  $OPTION_NULL '查看帮助文档'
  add_option ''  'debug' $OPTION_NULL '调试信息'
}

########################################################
## 帮助函数
##
## 当用户调用帮助指令时, 会自动读取对应方法的注释作为帮助文档
## 展示给用户查看
## 
########################################################
Papiyas::help() {
  local controller_name=$(get_controller)
  local controller_filename=$(get_controller_file "${controller_name}")
  local search
  if [ "${controller_name}" == 'main' ]; then
    search=$(get_action)
  else
    search=${controller_name}:$(get_action)
  fi

  local start_line=$(get_line "^## ${search}" "${controller_filename}")

  # 不存在帮助文档
  if [ -z "${start_line}" ]; then
    ansi --red "No help document for ${search}"
    exit 0
  fi

  let --start_line

  sed -n "${start_line}, /^###/p" ${controller_filename}

}

########################################################
## 增加一个选项
## 可以通过getOption(short_name) || getOption(long_name) 来获取用户输入选项
##
## @param short_name   短选项   单个英文字符. 如果为空则表示没有长选项
## @param long_name    长选项   长度大于1的英文字符串, 如果为空则表示没有长选项
## @param is_required  选项规则 OPTION_NULL 无参数选项(默认), OPTION_REQUIRE 必填参数选项, OPTION_OPTIONAL 可选参数
## @param description  选项描述 字符串(保留)
## @param default      默认值   当用户未输入此选项或未给选项赋值时会读取该值
## 
########################################################
Papiyas::addOption() {
  local short_name=$1
  local long_name=$2

  if [ -z "${short_name}" ] && [ -z "${long_name}" ]; then
    throw "短选项与长选项不能都为空";
  fi

  local is_required=${3:-$OPTION_NULL}
  local description=${4:-'just keep it!'}
  local default=$5

  if [ -n "${short_name}" ]; then

    if [ -n "${input_short_options[${short_name}]}" ]; then 
      throw "短选项'${short_name}'已存在"
    fi

    if [[ ! "${short_name}" =~ ^[[:alpha:]]$ ]]; then
      throw '短选项必须为英文字符'
    fi

    input_short_options["${short_name}"]=1
    
    # 短选项对应数据
    input_map["${short_name}_required"]=$is_required
    input_map["${short_name}_description"]=$description
    input_map["${short_name}_default"]=$default
  fi

  if [ -n "${long_name}" ]; then

    if [ -n "${input_long_options[${long_name}]}" ]; then 
      throw "长选项'${long_name}'已存在!"
    fi

    if [[ ! "${long_name}" =~ ^[a-zA-Z-]+$ ]]; then
    throw '长选项必须为英文字符串'
    fi

    input_long_options[$long_name]=1
    # 短选项对应数据
    input_map["${long_name}_required"]=$is_required
    input_map["${long_name}_description"]=$description
    input_map["${long_name}_default"]=$default

  fi

  # 长短选项进行关联
  if [ -n "${short_name}" ] && [ -n "${long_name}" ]; then

    input_short_options[$short_name]=$long_name
    input_long_options[$long_name]=$short_name

  fi
}

########################################################
## 获取选项值
##
## @param option_name  选项名  不能为空
## @param default      默认值  当没有对应选项值时返回
## 
########################################################
Papiyas::getOption() {
  local option_name=$1

  if [ -z "${option_name}" ]; then 
    throw "请输入要获取的选项名称"
  fi

  # 判断该选项名是否被定义, 如果未定义抛出异常
  if [ -z "${input_long_options[${option_name}]}" ] && [ -z "${input_short_options[${option_name}]}" ]; then
    throw "选项${1}不存在"
  fi

  # 获取选项值
  if [ -n "${output_options[${option_name}]}" ]; then
    echo ${output_options[${option_name}]}
  else
    echo $2
  fi

  # u user
  # [u]=v  [user]=v
  # '' user
  # [user]=v
  # u ''
  # [u]=v
}

########################################################
## 增加一个参数
## 可以通过getArgument(name)来获取用户输入参数
##
## @param name         参数名称 由数字,英文字母和下划线组成,但不能以数字开头
## @param is_required  选项规则 INPUT_REQUIRE 必填参数, INPUT_ARRAY 数组参数, 有且仅能有一个且必须在最后, INPUT_OPTIONAL 可选参数(必须设置默认值)
## @param description  选项描述 字符串(保留)
## @param default      默认值   当用户未输入此参数项赋值时会读取该值, 仅适用于最后几个参数
## 
## @author papiyas
########################################################
Papiyas::addArgument() {
  local name=$1

  if [ -z "${name}" ]; then
    throw "请输入参数";
  fi

  if [[ ! "${name}" =~ ^[[:alpha:]_][[:alpha:]0-9_]+$ ]]; then
    throw "参数${name}名称不符合规则, 必须由数字,英文字母和下划线组成,但不能以数字开头"
  fi

  if [ -n "${input_map[${name}_argument]}" ]; then
    throw "参数${name}已存在, 无法重复定义"
  fi

  

  local is_required=${2:-"${INPUT_REQUIRE}"}
  local description=${3:-'just keept it!'}
  local default

  if [ $is_required == $INPUT_ARRAY ]; then
    default=${@:4}
  else
    default=$4
  fi

  local size=${#input_arguments[@]}
  input_arguments[${size}]=$name
  input_map["${name}_argument"]=$is_required
  input_map["${size}_required"]=$is_required
  input_map["${size}_description"]=$description
  input_map["${size}_default"]=$default
}

########################################################
## 获取选项值
##
## @param option_name  选项名  不能为空
## @param default      默认值  当没有对应选项值时返回
## 
########################################################
Papiyas::getArgument() {
  if [ -z "$1" ]; then 
    throw "请输入要获取的参数名称"
  fi

  if [ -z "${input_map[${1}_argument]}" ]; then
    throw "参数${1}不存在"
  fi

  # 获取选项值
  if [ -n "${output_arguments[$1]}" ]; then
    echo ${output_arguments[$1]}
  else
    echo $2
  fi
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

