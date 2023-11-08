#!/usr/bin/env bash
#
# SPDX-License-Identifier: APACHE-2.0
# shellcheck disable=SC1091

set -Eeuo pipefail
#set -x

# Load libraries
. "$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/liblog.sh"

is_boolean_yes() {
    local -r bool="${1:-}"
    # comparison is performed without regard to the case of alphabetic characters
    shopt -s nocasematch
    if [[ "$bool" = 1 || "$bool" =~ ^(yes|true)$ ]]; then
        true
    else
        false
    fi
}

debug_execute() {
    if is_boolean_yes "${DEBUG:-false}"; then
        LDAPTLS_REQCERT=never "$@"
    else
        LDAPTLS_REQCERT=never "$@" >/dev/null 2>&1
    fi
}

test_failure() {
    error "Failure during testing!"
    exit 1
}
trap 'test_failure' SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM

NAMESPACE=ds

info "Testing the openldap database cluster..."

info "Fetch the LDAP admin password from k8s"
LDAP_ADMIN_PASSWORD=$(kubectl get secret --namespace ${NAMESPACE} openldap -o jsonpath="{.data.LDAP_ADMIN_PASSWORD}" | base64 --decode; echo)

info "Add a user"
debug_execute ldapadd -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -f .bin/user.ldif

cnt=${2:-${1:-10}}
info "Add $cnt entries"
for ((i = 0 ; i < cnt ; i++ )); do
    sed 's/dn: uid=einstein,dc=example,dc=org/dn: uid=einstein-'"${i}"',dc=example,dc=org/; s/uid: einstein/uid: einstein-'"${i}"'/; s/uidNumber: 20000/uidNumber: '"$(printf "2%04d" $i)"'/; s|homeDirectory: /home/einstein|homeDirectory: /home/einstein-'"${i}"'|; s/ownCloudUUID:: NGM1MTBhZGEtYzg2Yi00ODE1LTg4MjAtNDJjZGY4MmMzZDUx/ownCloudUUID:: '"$(uuidgen | base64)"'/' .bin/user.ldif | debug_execute ldapadd -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636
done

info "Search for data in our cluster"
debug_execute ldapsearch -o nettimeout=20 -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -b 'dc=example,dc=org' | tee /tmp/test-write.txt

# info "Ensure num responses"
# [[ $(grep "numResponses" /tmp/test-write.txt | cut -d ":" -f 2 | tr -d ' ') -ge 1 ]] || exit 1

# info "Ensure objectClass"
# [[ $(grep "objectClass: ownCloud" /tmp/test-write.txt) == "objectClass: ownCloud" ]] || exit 1

if [ -z "${1:-}" ]; then
    info "Remove $cnt entries"
    for ((i = 0 ; i < cnt ; i++ )); do
	sed 's/dn: uid=einstein,dc=example,dc=org/dn: uid=einstein-'"${i}"',dc=example,dc=org/' .bin/user-delete.ldif | debug_execute ldapmodify -x -D 'cn=admin,dc=example,dc=org' -w Not@SecurePassw0rd -H ldaps://localhost:30636
    done
fi

# info "Search for data in our cluster"
# debug_execute ldapsearch -o nettimeout=20 -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -b 'uid=einstein,dc=example,dc=org' | tee /tmp/test-write.txt

if [ -z "${1:-}" ]; then
    info "Delete user"
    debug_execute ldapmodify -x -D 'cn=admin,dc=example,dc=org' -w "${LDAP_ADMIN_PASSWORD}" -H ldaps://localhost:30636 -f .bin/user-delete.ldif
fi

info "Successful test run!"
