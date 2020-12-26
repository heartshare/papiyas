#!/usr/bin/env bash


project::configure() {
    ## 指定要安装的框架的版本号
    add_option 'v' 'version' $OPTION_REQUIRE
    ## 指定当前项目要使用的php版本
    add_option ''  'php-version' $OPTION_REQUIRE
}


################################################################
## project:create
## 
## @params name (optional) 要安装的框架名称, 默认为laravel. 目前支持thinkphp(tp), yii, symfony
## @options -a, --all 是否停止所有服务
## @description: 
## +. 当服务名称为空时, 会停止配置文件中的SERVER_LIST
## +. 如果服务名称不为空, 则会停止这些服务
## +. 如果有-a|--all选项, 则会停止所有已启动服务
## +. 如果服务名称与SERVER_LIST同时为空, 则等同于输入了-a|--all选项
## 
## 底层实际调用 docker-compose stop server_name
################################################################
project::create() {

}