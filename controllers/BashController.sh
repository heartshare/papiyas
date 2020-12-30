#!/usr/bin/env bash

bash::configure() {
  add_option 'u' 'user' "${OPTION_REQUIRE}" '用户名' 'papiyas'
}


bash::workspace() {
  local user=$(get_option user)
  local workspace_user=$(get_workspace_user)
  user=${user:-"${workspace_user}"}

  docker_compose exec --user="${user}" workspace bash
}
