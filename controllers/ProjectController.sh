#!/usr/bin/env bash


project::configure() {
    ## 指定要安装的框架的版本号
    add_option 'v' 'version' $OPTION_REQUIRE
    ## 指定当前项目要使用的php版本
    add_option ''  'php-version' $OPTION_REQUIRE
    add_option ''  'full' $OPTION_NULL 'symfony专用, 下载完整版'
    add_option ''  'type' $OPTION_OPTIONAL '框架名称' 'laravel'
    add_argument 'project_name' $INPUT_REQUIRE '项目名称'  
    add_argument 'server_name' $INPUT_OPTIONAL '项目的域名'
}


################################################################
## project:create
## 
## @options --type (optional) 要安装的框架名称, 默认为laravel. 目前支持laravel, symfony, yii
## @options -v, --version (optional) 框架版本号, 默认为最新版
## @options --php-version (optional) 该项目要使用的php版本号, 不填则采用默认的版本号
## @options --full (optional) Symfony专用, 是否安装完整版
## @params  project_name 项目名称
## @description: 
## +. 在工作目录中创建项目, 并纳入到papiyas管理
## +. 被papiyas管理的项目可以做更多的事情, 如下所示(必须在项目目录下调用才有效)
##   -. papiyas console: 等同于执行了php bin/console
##   -. papiyas artisan: 等同于执行了php artisan
##   -. papiyas php: 调用当前项目使用的php版本
##   -. papiyas composer: 等同于执行了composer
## @notice:
## + 在项目目录中执行的php均为创建项目时指定的--php-version
## 
## 底层实际调用 docker-compose stop server_name
################################################################
project::create() {
  local framework=$(get_option type laravel)
  local project_name=$(get_argument project_name)

  if [ -z "${project_name}" ]; then
    throw "情输入项目名称"
  fi

  local server_name=$(get_argument server_name)

  if [ -z "${server_name}" ]; then
    ansi --red " 请输入该项目的域名，如果不输入则可调用project:conf到配置文件中设置:"
    ansi -n --red " > "
    read -r server_name
  fi

  local version=$(get_option version)
  local full=$(get_option full)
  local php_container=$(get_php_container)

  local php_command="docker_compose exec ${php_container} php"

  local laradock_path=$(eval echo $(get_config app.laradock_path))
  cd "${laradock_path}"
  local workspace_path=$(get_config app.workspace_path)

  if [ ! -f "${workspace_path}/.composer/bin/composer" ]; then
    docker_compose exec --user=papiyas workspace bash -c "mkdir -p .composer/bin/ && cp /usr/local/bin/composer .composer/bin/composer"
  fi

  

  local install_command

  case "${framework}" in
    laravel)
      install_command="create-project --prefer-dist laravel/laravel ${project_name} ${version}"
    ;;
    # thinkphp|tp)
    # ;;
    yii)
      install_command="create-project --prefer-dist yiisoft/yii2-app-basic ${project_name} ${version}"
    ;;
    symfony)
      # extra option: --full
      # composer create-project symfony/website-skeleton project-name
      if [ -n "${full}" ]; then
        install_command="create-project symfony/website-skeleton ${project_name} ${version}"
      else
        # composer create-project symfony/skeleton project-name
        install_command="create-project symfony/skeleton ${project_name} ${version}"
      fi
    ;;
    *)
      throw "目前不支持${framework}框架, 仅支持laravel, yii, symfony"
    ;;
  esac

  # 用来帮助papiyas来管理项目
  local project_config="project_name=${project_name}
project_framework=${framework}
project_version=${version}
project_backup_directory=
project_config_filename=${project_name}.conf
project_php_version=${php_container}
"

  # 未来未优化在php多版本安装的时候
  docker_compose exec --user=www-data "${php_container}"  php  /var/www/.composer/bin/composer config -g repo.packagist composer https://mirrors.aliyun.com/composer

  if docker_compose exec --user=www-data "${php_container}" php /var/www/.composer/bin/composer ${install_command}; then
    ansi --red "将项目纳入到papiyas中管理: "
    docker_compose exec --user=papiyas workspace bash -c "echo -e '${project_config}' > ${project_name}/.papiyas"

    local nginx_conf="${papiyas_extra_path}/nginx/${framework}.conf"
    ansi --bold -n "导入NGINX配置文件: "
    ansi --red "${laradock_path}/nginx/sites/${project_name}.conf"
    local app_code_path=$(get_config env.app_code_path_container)

    if [ $server_name ]; then
      sed -e "s/__SERVER_NAME__/$server_name/; s/__PROJECT_DIRECTORY__/`str_convert ${app_code_path}/$project_name`/; s/__PHP_CONTAINER__/`str_convert ${php_container}:9000`/" ${nginx_conf} > ${laradock_path}"/nginx/sites/${project_name}.conf"
    else
      sed "s/__PROJECT_DIRECTORY__/`str_convert ${app_code_path}/${project_name}`/; s/__PHP_CONTAINER__/`str_convert ${php_container}:9000`/" ${nginx_conf} > ${laradock_path}"/nginx/sites/${project_name}.conf"
    fi

    ansi --bold "项目创建成功, 如果您时在虚拟机上安装, 请将虚拟域名${server_name}添加到虚拟机的/etc/hosts以及主机的/etc/hosts中, 否则将无法访问"
  else
    throw "创建项目失败"
  fi
}


get_php_container() {
    local php_version=$(get_option php-version)

    local container="php-fpm"  # default

    local php_multi=$(get_config app.php_multi)

    # 开启多版本并且对应php版本容器存在
    if [ ${php_multi} = true ]; then
      if docker_compose top "php${php_version}" &> /dev/null; then
        container="php${php_version}"
      fi
    fi

    echo $container
}


project::conf() {
    echo
}