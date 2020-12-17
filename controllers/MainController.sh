#!/usr/bin/env bash


main::configure() {
    add_argument 'name' $INPUT_ARRAY
}


main::list() {
   # echo $(get_argument name)
echo $(get_argument name)
echo $(get_option help)
}