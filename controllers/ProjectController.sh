#!/usr/bin/env bash


project::configure() {
    ## 指定要安装的框架的版本号
    add_option 'v' 'version' $OPTION_REQUIRE
    ## 指定当前项目要使用的php版本
    add_option ''  'php-version' $OPTION_REQUIRE
}