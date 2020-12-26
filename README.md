# 目前命令如下

如果对命令不了解如何使用, 可以使用-h|--help指令查看, 例如`./bin/papiyas server:start -h`

## server

+ server:start
+ server:stop
+ server:restart
+ server:remove
+ server:ps

## install

目前在安装Laradock部分的配置数据较小, 之后会把常用的放进来.
如果有想要配置的但是没有的可以直接从laradock的env-example中粘贴过来放入env.ini中即可

在安装laradock过程中构建成功的容器不会再次构建(即使修改了配置也不行), 后续可以通过clear命令或者-f参数来解决这个问题
当然安装成功后也不建议重复安装, 可以使用单独的build命令来重新构建

+ install:docker
+ install:laradock


## project

项目管理, 目前只写了创建项目(只支持laravel, symfony, yii)

+ project:create

## 其他命令

+ docker-compose  
+ dc
+ php
+ npm
+ mysql