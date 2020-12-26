###############################################
## WORKDIR @papiyas
###############################################

ARG APP_CODE_PATH_CONTAINER
WORKDIR ${APP_CODE_PATH_CONTAINER}

###############################################




###############################################
## Set Timezone @papiyas
###############################################

ARG TZ=UTC
ENV TZ ${TZ}

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

###############################################


###############################################
## Symfony @papiyas
###############################################

USER root

ARG INSTALL_SYMFONY=false

RUN if [ ${INSTALL_SYMFONY} = true ]; then \
  mkdir -p /usr/local/bin \
  && apt-get install wget -y \
  && wget https://get.symfony.com/cli/installer -O - | bash \
  && mv ~/.symfony/bin/symfony  /usr/local/bin/symfony \
  && rm -rf ~/.symfony/bin \
;fi

###############################################


