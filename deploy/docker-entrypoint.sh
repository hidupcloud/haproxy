#!/bin/sh
set -e

function query () { echo ${HAPROXY_JSON_CFG} | jq "$1" | sed 's/"//g'; }
function putfile () { echo "${1}" >> ${2}; }
function putcrtlist () { putfile "$1" "/usr/local/etc/haproxy/crt-list.txt"; }
function putcfg () { putfile "$1" "/usr/local/etc/haproxy/haproxy.cfg"; }
function putpem () { putfile "$1" "$2"; }

for crt in $(query '.certs[]')
do
  putcrtlist "${crt}"
done

for domain in $(query ".domains[].name")
do
  idx=0
  for url in $(query '.domains | map(select(.name == "'$domain'"))[] | .url[]')
  do
    putcfg "  acl ${domain}_${idx}_acl hdr(host) -i ${url}"
    putcfg "  use_backend ${domain}_backend if ${domain}_${idx}_acl"
    idx=${idx}0
  done
done

putcfg ""

for userlist in $(query ".userlist[].name")
do
  putcfg "userlist ${userlist}"
  for user in $(query '.userlist | map(select(.name == "'$userlist'" ))[].users[].login')
  do
    passtype=$(query '.userlist | map(select(.name == "'$userlist'"))[].users | map(select(.login == "'$user'"))[] | .passtype')
    passfile=$(query '.userlist | map(select(.name == "'$userlist'"))[].users | map(select(.login == "'$user'"))[] | .passfile')
    putcfg "  user ${user} ${passtype} $(cat ${passfile})"
  done
done

putcfg ""

for domain in $(query ".domains[].name")
do
  server=$(query '.domains | map(select(.name == "'$domain'"))[] | .server')
  port=$(query '.domains | map(select(.name == "'$domain'"))[] | .port')
  putcfg "backend ${domain}_backend
  mode http
  server ${domain}_srv ${server}:${port}"
  userlist="$(query '.domains | map(select(.name == "'$domain'")) | map(select(.basicauth == true))[] | .userlist')"
  [[ ! -z "${userlist}" ]] && {
    putcfg "  acl AuthOkay_${domain} http_auth(${userlist})"
    putcfg "  http-request auth realm Forbiden if !AuthOkay_${domain}"
  }
done

[[ ! -z "${DEBUG}" ]] && {
  echo ${HAPROXY_JSON_CFG}
  cat /usr/local/etc/haproxy/haproxy.cfg
}

/sbin/syslogd -O /proc/1/fd/1

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

exec "$@"
