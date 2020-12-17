#!/usr/bin/env bash

# 获取系统信息
OS_NAME=$(uname -s)


### 用于实现用户命令行参数与选项的读取 #############
# Linux和MacOS下关联数组声明命令不一致
case "${OS_NAME}" in
  Linux*)
    # Linux
    declare -A input_short_options
    declare -A input_long_options
    declare -A input_arguments
    declare -A input_map
    declare -A output_options
    declare -A output_arguments
  ;;
  Darwin*)
    declare -a input_short_options
    declare -a input_long_options
    declare -a input_arguments
    declare -a input_map
    declare -a output_options
    declare -a output_arguments 
  ;;
  *)
    throw "无法获取系统名称, 仅支持Linux和MacOS."
    exit
  ;;
esac;

### 命令行选项常量 #################################

export OPTION_NULL=0
export OPTION_REQUIRE=1
export OPTION_OPTIONAL=2

### 命令行参数常量 #################################

export INPUT_REQUIRE=1
export INPUT_OPTIONAL=2
export INPUT_ARRAY=3

### 控制器与方法  #################################

export controller_name
export action_name

### 失败次数  #####################################

if [ -z "$FAILED_TIMES" ]; then
  export FAILED_TIMES=0
fi

### 经过处理后剩余的参数列表  ######################

export params=()






