#!/bin/sh
set -e

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- haproxy "$@"
fi

if [ "$1" = 'haproxy' ]; then
	shift # "haproxy"
	# if the user wants "haproxy", let's add a couple useful flags
	#   haproxy-systemd-wrapper -- "master-worker mode" (similar to the new "-W" flag; allows for reload via "SIGUSR2")
	#   -db -- disables background mode
	set -- "$(which haproxy-systemd-wrapper)" -p /run/haproxy.pid -db "$@"
fi

function putfile () { echo "${1}" >> ${2}; }
function putcrtlist () { putfile "$1" "/usr/local/etc/haproxy/crt-list.txt"; }
function putcfg () { putfile "$1" "/usr/local/etc/haproxy/haproxy.cfg"; }
function putpem () { putfile "$1" "$2"; }

for crt in $(echo ${HAPROXY_JSON_CFG} | jq ".certs[]" | sed 's/"//g')
do
  putcrtlist "${crt}"
done

for domain in $(echo ${HAPROXY_JSON_CFG} | jq ".domains[].name" | sed 's/"//g')
do
  url=$(echo ${HAPROXY_JSON_CFG} | jq '.domains | map(select(.name == "'$domain'"))[] | .url' | sed 's/"//g')
  putcfg "  acl ${domain}_acl hdr(host) -i ${url}"
  putcfg "  use_backend ${domain}_backend if ${domain}_acl"
done

putcfg ""

for userlist in $(echo ${HAPROXY_JSON_CFG} | jq ".userlist[].name" | sed 's/"//g')
do
  putcfg "userlist ${userlist}"
  for user in $(echo ${HAPROXY_JSON_CFG} | jq '.userlist | map(select(.name == "'$userlist'" ))[].users[].login' | sed 's/"//g')
  do
    passtype=$(echo ${HAPROXY_JSON_CFG} | jq '.userlist | map(select(.name == "'$userlist'"))[].users | map(select(.login == "'$user'"))[] | .passtype' | sed 's/"//g')
    passfile=$(echo ${HAPROXY_JSON_CFG} | jq '.userlist | map(select(.name == "'$userlist'"))[].users | map(select(.login == "'$user'"))[] | .passfile' | sed 's/"//g')
    putcfg "  user ${user} ${passtype} $(cat ${passfile})"
  done
done

putcfg ""

for domain in $(echo ${HAPROXY_JSON_CFG} | jq ".domains[].name" | sed 's/"//g')
do
  server=$(echo ${HAPROXY_JSON_CFG} | jq '.domains | map(select(.name == "'$domain'"))[] | .server' | sed 's/"//g')
  port=$(echo ${HAPROXY_JSON_CFG} | jq '.domains | map(select(.name == "'$domain'"))[] | .port' | sed 's/"//g')
  putcfg "backend ${domain}_backend
  mode http
  server ${domain}_srv ${server}:${port}"
  userlist="$(echo ${HAPROXY_JSON_CFG} |  jq '.domains | map(select(.name == "'$domain'")) | map(select(.basicauth == true))[] | .userlist' | sed 's/"//g')"
  [[ ! -z "${userlist}" ]] && {
    putcfg "  acl AuthOkay_${domain} http_auth(${userlist})"
    putcfg "  http-request auth realm Forbiden if !AuthOkay_${domain}"
  }
done

/sbin/syslogd -O /proc/1/fd/1
exec "$@"
