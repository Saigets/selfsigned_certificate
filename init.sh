#!/usr/bin/bash
blue="\e[0;94m"
reset="\e[0m"

# -nodes do not create passphrase
init() {
	# root CA db
	mkdir -p ca/root-ca/private ca/root-ca/db crl certs
	chmod 700 ca/root-ca/private

	cp /dev/null ca/root-ca/db/root-ca.db
	cp /dev/null ca/root-ca/db/root-ca.db.attr
	echo 01 > ca/root-ca/db/root-ca.crt.srl
	echo 01 > ca/root-ca/db/root-ca.crl.srl

	#root CA request and SELF-sign
	echo -e "${blue}Requesting root CA${reset}"
	openssl req -new \
	    -config etc/root-ca.conf \
	    -out ca/root-ca.csr \
	    -nodes \
	    -keyout ca/root-ca/private/root-ca.key
	echo -e "${blue}Signing root CA${reset}"
	openssl ca -selfsign \
	    -config etc/root-ca.conf \
	    -in ca/root-ca.csr \
	    -out ca/root-ca.crt \
	    -extensions root_ca_ext

	# signing ca db
	mkdir -p ca/signing-ca/private ca/signing-ca/db crl certs
	chmod 700 ca/signing-ca/private

	cp /dev/null ca/signing-ca/db/signing-ca.db
	cp /dev/null ca/signing-ca/db/signing-ca.db.attr
	echo 01 > ca/signing-ca/db/signing-ca.crt.srl
	echo 01 > ca/signing-ca/db/signing-ca.crl.srl

	#signing request and sign
	echo -e "${blue}Request Signing CA${reset}"
	openssl req -new \
	    -config etc/signing-ca.conf \
	    -out ca/signing-ca.csr \
	    -nodes \
	    -keyout ca/signing-ca/private/signing-ca.key
	echo -e "${blue}Sign Signing CA${reset}"
	openssl ca \
	    -config etc/root-ca.conf \
	    -in ca/signing-ca.csr \
	    -out ca/signing-ca.crt \
	    -extensions signing_ca_ext
}

copy_certs () {
	name=$1
	mkdir -p /etc/zabbix/certs/
	cp ca/root-ca.crt certs/$name.key certs/$name.crt /etc/zabbix/certs/
	cat ca/signing-ca.crt >> /etc/zabbix/certs/$name.key
	chown -R zabbix:zabbix /etc/zabbix/certs/ && chmod -R 500 /etc/zabbix/certs/
}

create() {
	name=$1
	# new cert request and sign
	echo -e "${blue}Requesting $name certificate${reset}"
	CN=$name \
	SAN=DNS:$name \
	openssl req -new \
	    -config etc/server.conf \
	    -out certs/$name.csr \
	    -keyout certs/$name.key

	echo -e "${blue}Signing $name certificate${reset}"
	openssl ca \
	    -config etc/signing-ca.conf \
	    -in certs/$name.csr \
	    -out certs/$name.crt \
	    -extensions server_ext

	copy_certs $name
}

insert_conf () {
	agent_conf='TLSAccept=unencrypted,cert\nTLSCAFile=/etc/zabbix/certs/root-ca.crt\nTLSCertFile=/etc/zabbix/certs/agent.crt\nTLSKeyFile=/etc/zabbix/certs/agent.key'
	server_conf='TLSCAFile=/etc/zabbix/certs/root-ca.crt\nTLSCertFile=/etc/zabbix/certs/server.crt\nTLSKeyFile=/etc/zabbix/certs/server.key\n'
	echo -e $agent_conf >> /etc/zabbix/zabbix_agentd.conf
	echo -e $server_conf >> /etc/zabbix/zabbix_server.conf
}
if test -f "ca/root-ca.crt"; then
	echo -e "${blue}root cert already exists${reset}"
else
	init
fi
create "server"
create "agent"
insert_conf
