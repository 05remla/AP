#!/bin/sh
# Firewall for Debian Etch accesspoint

# Program paths and variables
IPTABLES="/sbin/iptables"

# Working directory
WorkDir=$(dirname $(readlink -f $0))

# Wlan interface
WLANIF=$(cat "${WorkDir}/interfaces.conf" | grep LAN | cut -d# -f2)

# External, Internet-facing interface
EXTIF=$(cat "${WorkDir}/interfaces.conf" | grep WAN | cut -d# -f2)

# Loopback interface, which has to defined or
# shit hits the fan.
LOOPIF=lo

# Wireless LAN address and netmask. In this
# case addresses 192.168.0.0 - 192.168.0.254
# are reserved for it.
WLAN="$(cat "${WorkDir}/dhcpd.conf" | grep "subnet " | awk '{print $2}')/24"


# Enable IP-forwarding. Otherwise we won't be able
# to forward any traffic from the WLAN to the Internet
echo "Enabling IP-forwarding"
echo 1 > /proc/sys/net/ipv4/ip_forward

# Remove all previously made rules
echo "Removing old rules"
$IPTABLES -F
$IPTABLES -X

# Create custom chains for inbound and outbound
# traffic on the WLAN interface and the external
# interface + some other custom chains. This is
# done to simplify mainteinance.
echo "Configuring custom chains:"
$IPTABLES -N in_extif
$IPTABLES -N out_extif
$IPTABLES -N in_wlanif
$IPTABLES -N out_wlanif

###############################################
################ CUSTOM CHAINS ################
###############################################


################ out_extif chain ##############
# * External interface, going out
echo "   out_extif"
# Accept all outgoing traffic
$IPTABLES -A out_extif -o $EXTIF -j ACCEPT
$IPTABLES -A out_extif -o $EXTIF -j DROP

################ in_wlanif chain ##############
# Wlan interface, coming in
echo "   in_wlanif"
# * Allow all incoming traffic to the WLAN interface
$IPTABLES -A in_wlanif -i $WLANIF -s $WLAN -j ACCEPT
$IPTABLES -A in_wlanif -i $WLANIF -j DROP

################ out_wlanif chain #############
# Wlan interface, going out
echo "   out_intif"
# * Allow all outgoing traffic from the WLAN interface
$IPTABLES -A out_wlanif -o $WLANIF -d $WLAN -j ACCEPT
$IPTABLES -A out_wlanif -o $WLANIF -j DROP

###############################################
################ STANDARD CHAINS ##############
###############################################

echo "Configuring standard chains:"

################ POSTROUTING chain ############
echo "   postrouting"
# Masquerade connections if they arrive from specified addresses,
# in this case from the wireless LAN
$IPTABLES -t nat -A POSTROUTING -o $EXTIF  -s $WLAN -j MASQUERADE

################ FORWARD chain #################
# Forward chain processes packets that arrive to
# the accesspoint but are not destined for it.
# This includes, for example, packets that are sent
# from WLAN clients to the Internet via the AP.
echo "   forward"

# Set policy to DROP
$IPTABLES -P FORWARD DROP

# Related & established
$IPTABLES -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Drop any new or invalid packets coming from external interface
$IPTABLES -A FORWARD -i $EXTIF -m state --state NEW,INVALID -j DROP

# New connections from WLANIF
$IPTABLES -A FORWARD -i $WLANIF -o $EXTIF -m state --state NEW -j ACCEPT

# Drop everything else
$IPTABLES -A FORWARD -j DROP


################ INPUT chain ##################
echo "   input"
# Set policy to DROP
$IPTABLES -P INPUT DROP

# Allow inbound loopback
$IPTABLES -A INPUT -i $LOOPIF -m state --state NEW -j ACCEPT

# Allow related & established packets 
$IPTABLES -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Jump to per-interface chains
$IPTABLES -A INPUT -i $EXTIF -j in_extif
$IPTABLES -A INPUT -i $WLANIF -j in_wlanif

# Drop all other packets
$IPTABLES -A INPUT -j DROP

################ OUTPUT chain ##################
echo "   output"

# Set policy to DROP
$IPTABLES -P OUTPUT DROP

# Allow outbound loopback
$IPTABLES -A OUTPUT -o $LOOPIF -m state --state NEW -j ACCEPT

# Related & established
$IPTABLES -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Jump to per-interface chains
$IPTABLES -A OUTPUT -o $EXTIF -j out_extif
$IPTABLES -A OUTPUT -o $WLANIF -j out_wlanif

# Drop all other packets
$IPTABLES -A OUTPUT -j DROP
 
