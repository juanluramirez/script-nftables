clear
if [[ $(whoami) != "root" ]]
	then
			echo "No ha dado credenciales de super usuario."
			echo "Para poder ejecutar este scripts debe identificarse como 'su' o ejecutar el comando con 'sudo' (antes teniendo dicha opcion habilitada)"
###########################
####INSTALAMOS NFTABLES####
###########################
else
	nftables=$(dpkg -s nftables | grep Status)
	if [ "$nftables" == "Status: install ok installed" ] ; then
		echo "El paquete nftables esta instalado"
	else
		echo "Vamos a instalar el paquete"
		$(apt install nftables)
	fi	
	echo 1 > /proc/sys/net/ipv4/ip_forward
	modprobe nf_tables 
	modprobe nf_tables_ipv4
	modprobe  nf_tables_bridge
	modprobe  nf_tables_inet
	modprobe  nf_tables_arp
#####################################
####1. Política por defecto DROP.####
#####################################
	nft add table ip FILTER 
	nft add chain ip FILTER INPUT { type filter hook input priority 0 \; policy drop \;}
	nft add chain ip FILTER OUTPUT { type filter hook output priority 0 \; policy drop \;}
	nft add chain ip FILTER FORWARD { type filter hook forward priority 0 \; policy drop \;}

###############################################################################################################################
####2. Las máquinas de la red podrán navegar por Internet, excepto a las direcciones correspondientes a marca.com y as.com.####
###############################################################################################################################
	nft add table NAT
	nft add chain NAT PREROUTING { type nat hook prerouting priority 1 \; }
	nft add chain NAT POSTROUTING { type nat hook postrouting priority 1 \; }
	nft add rule ip FILTER FORWARD oif eth1 ct state established,related counter accept
	nft add rule NAT POSTROUTING ip saddr 192.168.100.0/24 oif eth0 nftrace set 1 masquerade

#Si queremos denegar el acceso a una paginas determinadas debemos saber cual es la direccion IP de esa maquina para ello realizamos un ping [Direccion_Web]

##################
####www.as.com####
##################
	nft add rule ip NAT PREROUTING ip saddr 192.168.100.0/24 ip daddr 185.43.182.75 counter drop

#####################
####www.marca.com####
#####################
	nft add rule ip NAT PREROUTING ip saddr 192.168.100.0/24 ip daddr 193.110.128.109 counter drop

############################################################
####3. Se permitirá el tráfico de loopback en el router.####
############################################################
	nft add rule ip FILTER INPUT iif lo counter accept
	nft add rule ip FILTER OUTPUT oif lo counter accept

###################################################
####4. El router podrá realizar conexiones SSH.####
###################################################
	nft add rule ip FILTER OUTPUT oif eth0 tcp dport 22 counter accept
	nft add rule ip FILTER INPUT ct state established,related counter accept

########################################################################
####5. El router ofrece un servicio SSH accesible desde el exterior.####
########################################################################

#En el primer apartdo hemos habilitado la politica por defecto a drop, entonces nos va sacar si estamos conectados por ssh 
#Por tanto añadimos las siguientes reglas para permitir el acceso por ssh
	nft add rule ip FILTER INPUT iif eth1 tcp dport 22 counter accept
	nft add rule ip FILTER OUTPUT ct state established,related counter accept

#########################################################
####6. El router podrá ser cliente DNS, HTTP y HTTPS.####
#########################################################

###########
####DNS####
###########
	nft add rule ip FILTER OUTPUT oif eth0 udp dport 53 counter accept

############
####HTTP####
############
	nft add rule ip FILTER OUTPUT oif eth0 tcp dport 80 counter accept

#############
####HTTPS####
#############
	nft add rule ip FILTER OUTPUT oif eth0 tcp dport 443 counter accept

####################################################################################
####7. El PC1 ofrece un servidor Web accesible desde el exterior, solo por HTTP.####
####################################################################################
	nft add rule ip NAT PREROUTING iif eth0 tcp dport 80 counter dnat to 192.168.100.2
	nft add rule FILTER FORWARD oif eth0 tcp sport 80 accept

#####################################################################
####8. El PC2 ofrece un servidor FTP accesible desde el exterior.####
#####################################################################
	nft add rule ip NAT PREROUTING iif eth1 tcp dport 21 counter dnat to 192.168.100.3
	nft add rule FILTER FORWARD oif eth0 tcp sport 21 accept

###############################################
####9. PC1 tiene permitido el tráfico ICMP.####
###############################################
	nft add rule ip FILTER FORWARD ip saddr 192.168.100.2 icmp type echo-request ct state new,related,established  counter accept
	nft add rule ip FILTER FORWARD ip daddr 192.168.100.2 icmp type echo-reply ct state related,established  counter accept

#############################################################################################################
####10. Adicionalmente, el cortafuegos debe ofrecer protección frente a los siguientes tipos de acciones:####
#############################################################################################################
#Bloqueo de puertos.
	nft add rule ip mangle PREROUTING tcp flags & fin|syn|rst|psh|ack|urg == 0x0 counter drop

