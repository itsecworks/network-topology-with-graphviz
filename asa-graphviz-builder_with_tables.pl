#!/usr/bin/perl
# Author: Akos Daniel daniel.akos77ATgmail.com
# Filename: asa-graphviz-builder_with_tables.pl
# Current Version: 0.1 beta
# Created: 10th of July 2013
# Last Changed: 18th of Dec 2013
# -----------------------------------------------------------------------------------------------
# Description:
# -----------------------------------------------------------------------------------------------
# This is a rather crude and quick hacked Perl-script to build a config file
# for dot to make beautiful graphs or topologies automaticaly.
# -----------------------------------------------------------------------------------------------
# Known issues:
# - Duplicate edges sometimes somewhere...
# - The natted adresses would be presented too, since it can be proxy arp-ed to the firewall
# or could be a virtual mapped network and this should be part of the IP Topology.
# -----------------------------------------------------------------------------------------------
# [solved] if name is used it will not work. Do not use names! Like "route inside 1.1.1.0 255.255.255.0 intern-router"
# -----------------------------------------------------------------------------------------------
# Change History
# 18.12.13 name commands are prased too, but only the route entries with names are parsed to IPs.
# 18.12.13 if there is no vlan on the interface where there is an IP, I write "vlan no"
# 18.12.13 the automatic interface positioning is set based on security level.
# 		   if the security-level > 49 put it on the left side, else put on right side.
# 16.02.14 IPSec IKEv1 Lan-to-Lan VPNs are parsed and graphed too.
# 21.02.14 IPSec IKEv1 Lan-to-Lan Dynamic VPNs are parsed and graphed too. They will be out on the default route.
# -----------------------------------------------------------------------------------------------
# 0.1 beta: (10th of July 2013)
# 0.2 beta: (18th of Dec 2013)

use strict;
use Net::Netmask; # http://perltips.wikidot.com/module-net:netmask
use List::MoreUtils qw(uniq);
use Array::Utils qw(:all);
use Term::Query qw( query);
use Regexp::Common;

##################################################################################################
# 1.) Syntax checking and help - BEGIN
##################################################################################################

my $numberofargs = @ARGV;
my $outfilename = $ARGV[1];
print "\n==| asa-graphviz-builder_with_tables.pl v. 0.1 beta (10th of July 2013) by Akos Daniel \(daniel.akos77ATgmail.com\) |==\n";

if ($numberofargs < 2) {

    print "\nSyntax:\n";
    print "-------\n";
    print "asa-graphviz-builder_with_tables.pl <Input filename> <Output filename>\n";
    print "\n";
    print "Mandatory arguments:\n";
    print "-------------------\n";
    print " <Input filename> : Name of inputfile. This file should contain the Cisco ASA configuration\n";
    print " <Output filename> : Name of outputfile. This name will be used for the dot file and for the generated png and svg file\n";
	print "Example: ./asa-graphviz-builder_with_tables.pl asa-test.cfg asa-test.dot\n";
	print "This will generate \"asa-test.dot.svg\" and \"asa-test.dot.png\" files\n";
    die ("\n");

    } # End if

##################################################################################################
# 1.) Syntax checking and help - END
##################################################################################################


##################################################################################################
# 2.) Collect Firewall IPs from all cfg files - BEGIN
#
# This part collects from cfg files (ASA configs) the IPs, since they are not in DNS registered.
##################################################################################################

my @cfgfiles = <asa*.cfg>; # only the config files from asa firewall are used!!! 
my @firewallinterfaces;

### Open cfg files and put the contents in one HUGE array

 foreach my $file (@cfgfiles) {
    open (PARSEFILE,$file) || die ("==| Error! Could not open file $ARGV[0]"); # open the cfg files (one to another) to read
    print "\nLoading ASA Configuration-file from $file cfg file...";
    my @filetoarray = <PARSEFILE>; # write the content of the file into an array
    print "Done\n";

	##################################################################################################
	# Setup start
	##################################################################################################
	#
	# When Setup is finished the Interfaces will end up in a array of its own.

	my @interface_cmd;
	my @nameif_cmd;
	my @ipaddr_cmd;
	my @hostname_cmd;
	my $interface_found;

	foreach my $line (@filetoarray) {

		#-----------------
		# Parse Hostname |
		#-----------------

		if ($line =~ /^hostname/m) { # find the lines *starts* with hostname
			@hostname_cmd = split (' ', $line);
		}
		
		#------------------
		# Parse Interfaces|
		#------------------
		#
		# The order of if statements is important. 
		# This is currently the following: interface->vlan->nameif->security-level->ip address
		
		if ($line =~ /^interface/m) { # find the lines *starts* with interface
			@interface_cmd = split (' ', $line);
			$interface_found = 'true';
		}
		if ($line =~ /^\snameif/m && $interface_found eq 'true') { # find the lines *starts* with <space>nameif
			@nameif_cmd = split (' ', $line);
		}
		if ($line =~ /^\sip\saddress/m && $interface_found eq 'true') { # find the lines *starts* with <space>ip address
			@ipaddr_cmd = split (' ', $line);
			my $temp =  join (' ',$hostname_cmd[1],$interface_cmd[1],$ipaddr_cmd[2],$ipaddr_cmd[3],$nameif_cmd[1]);
			push (@firewallinterfaces,$temp);
			$interface_found = 'false';
		}
	}   
	close (PARSEFILE);
}

# firewallinterfaces array example:
# fw1 Port-channel1.251 192.168.250.1 255.255.255.240 sweden
# fw1 Port-channel1.252 192.168.250.17 255.255.255.240 china
##################################################################################################

##################################################################################################
# 2.) Collect Firewall IPs from all cfg files - END
##################################################################################################

##################################################################################################
# 3.) Setup initialisation - BEGIN
# Save the interfaces, routes and hostname in arrays
##################################################################################################

# 3/1.) Open input-file and put the contents in one HUGE array
##################################################################################################

open (PARSEFILE,$ARGV[0]) || die ("==| Error! Could not open file $ARGV[0]"); # open the file to read

print "\nLoading ASA Configuration-file from $ARGV[0]...";

my @Parse_array = <PARSEFILE>;
my $Parsefile_size = @Parse_array;
print "Done\n";

close (PARSEFILE);

# 3/2.) Save the names, interfaces, routes and hostname in arrays and variable
##################################################################################################

my @hostname_cmd;

my @name_cmd;
my @interface_cmd;
my @vlan_cmd;
my @nameif_cmd;
my @seclevel_cmd;
my @ipaddr_cmd;
my @interfaces;
my $interface_found = 'false'; # indicator for interface command

my @object_network_cmd;
my $object_network_name;
my @object_networks; #					---------- key array for object network --------------------

my @object_group_cmd;
my $object_group_name;
my @object_groups;

my @object_groups_ungrupped;
my @object_groups_ungrupped1; #			---------- key array for 2x ungrupped object-group ----------

my @access_list_cmds;
my @cry_acl_dst_groups;
my @cry_acl_dst_groupsu;
my @acl_src_group;

my @route_cmd;

my $cry_matchaddr;
my $cry_map_name_id;
my $cry_peer;
my $cry_trset;
my $crypto_if;
my $cry_dynmap_acl;
my @crypto_map_datas;

foreach my $line (@Parse_array) {

	#----------------
	# Parse Hostname|
	#----------------

	if ($line =~ /^hostname/m) { # find the lines *starts* with hostname
		@hostname_cmd = split (' ', $line);
	}

	#---------------------
	# Parse name commands|
	#---------------------
	#
	# example:
	# name 192.168.1.1 waf01
	# name 192.168.1.2 waf02
	
	if ($line =~ /^name\s/m) {
		my @name_cmd_splitted = split (' ', $line);
		push (@name_cmd,$name_cmd_splitted[1]." ".$name_cmd_splitted[2]);
	}
    
	#------------------
	# Parse Interfaces|
	#------------------
    # The order of if statements is important. 
	# This is currently the following: interface->vlan->nameif->security-level->ip address

	if ($line =~ /^interface/m) { # find the lines *starts* with interface
		@interface_cmd = split (' ', $line);
		$interface_found = 'true';
	}
	if ($line =~ /^\svlan/m && $interface_found eq 'true') { # find the lines *starts* with <space>vlan
		@vlan_cmd = split (' ', $line);
	}
	if ($line =~ /^\snameif/m && $interface_found eq 'true') { # find the lines *starts* with <space>nameif
		@nameif_cmd = split (' ', $line);
	}
	if ($line =~ /^\ssecurity-level/m && $interface_found eq 'true') { # find the lines *starts* with <space>security-level
		@seclevel_cmd = split (' ', $line);
	}
	if ($line =~ /^\sip\saddress/m && $interface_found eq 'true') { # find the lines *starts* with <space>ip address
		@ipaddr_cmd = split (' ', $line);
		if (!@vlan_cmd)	{$vlan_cmd[1] = "no"};
		my $interfaceparams =  join (' ', $interface_cmd[1],$ipaddr_cmd[2],$ipaddr_cmd[3],$nameif_cmd[1],$seclevel_cmd[1],$vlan_cmd[1]);
		push (@interfaces,$interfaceparams);
		$interface_found = 'false';
	}

	# -----------------------
	# Parse network objects |
	# -----------------------
	#
	# Example Config:
	# object network mytestnetwork
	#  subnet 172.17.136.0 255.255.255.0
	# object network mytestnetwork1
	#  host 172.17.136.1
	# object network meeting-intern
	#  fqdn v4 meeting-intern.mycompany.com
	# 
	# object network saturn-hansa-dhcp1
	#  range 10.7.4.100 10.7.4.199
	#
	
	if ($line =~ /^object\snetwork/m) { # find the lines *starts* with object<space>network
		@object_network_cmd = split (' ', $line);
		$object_network_name = $object_network_cmd[2];
	}
	if ($line =~ /^\ssubnet/m || $line =~ /^\shost/m || $line =~ /^\sfqdn\sv4/m || $line =~ /^\srange\s/m) { # find the lines *starts* with <space>subnet or <space>host or <space>fqdn or <space>range
		my @object_cmd = split (' ', $line);
		if ($object_cmd[0] eq 'host') {
			$object_cmd[2] = '255.255.255.255';
		}
		elsif ($object_cmd[0] eq 'fqdn') {
			my $ipaddress  = nslookup(host => $object_cmd[2], type => "PTR");
			$object_cmd[1] = $ipaddress;
			$object_cmd[2] = '255.255.255.255';
		}
		elsif ($object_cmd[0] eq 'range') {
			# nothing to do...$object_cmd[1],$object_cmd[2] will be correct
		}
		my $temp1 = join (' ',$object_network_name,$object_cmd[1],$object_cmd[2] );
		push (@object_networks,$temp1);
		$#object_cmd = -1;
	}
	
	# Result:
	# object_networks array example:
	# mytestnetwork 172.17.136.0 255.255.255.0
	# mytestnetwork1 172.17.136.1 255.255.255.255
	
	# ----------------------------
	# Parse network object-groups|
	# ----------------------------
	# 
	# Example Config:
	# object-group network fa-opelgmbh
	#  network-object host 192.168.15.32
	#  network-object 172.17.139.0 255.255.255.192
	#  group-object group2
	#  network-object object mytestnetwork
	
	if ($line =~ /^object-group\snetwork/m) { # find the lines *starts* with object-group<space>network
		@object_group_cmd = split (' ', $line);
		$object_group_name = $object_group_cmd[2];
	}
	if ($line =~ /^\snetwork-object/m || $line =~ /^\sgroup-object/m) { # find the lines *starts* with <space>network-object or <space>group-object
		my @object_cmd = split (' ', $line);
		if ($object_cmd[1] eq 'host') {
			$object_cmd[1] = $object_cmd[2];
			$object_cmd[2] = '255.255.255.255';
		}
		if ($object_cmd[1] eq 'object') {
		
		# the network object are before network object groups in the config (tested SW Version 8,9).
		# the object_networks array can be searched, since it has all the entries at this point.
			foreach my $object_networks (@object_networks) {
				my @object_networks_splitted = split (' ', $object_networks);
				if ($object_cmd[2] eq $object_networks_splitted[0]) {
					$object_cmd[1] = $object_networks_splitted[1];
					$object_cmd[2] = $object_networks_splitted[2];
				}
			}
		}
		if ($object_cmd[0] eq 'group-object') {
			$object_cmd[2] = $object_cmd[1];
			$object_cmd[1] = 'group-object';
		}
		my $temp1 = join (' ',$object_group_name,$object_cmd[1],$object_cmd[2] );
		push (@object_groups,$temp1);
		$#object_cmd = -1;
	}
	
	# object_groups array example
	# fa-opelgmbh 192.168.15.32 255.255.255.255
	# fa-opelgmbh 172.17.139.0 255.255.255.192
	# fa-opelgmbh 172.17.136.0 255.255.255.0
	# fa-opelgmbh group-object group2*
	# *
	# the group in group extraction follows later on the code.
	
	# -----------
	# Parse ACLs|
	# -----------
	# Example:
	# myfirewall.cfg:access-list tun-opelgmbh remark #ID00011 - Fa. opelgmbh
	# myfirewall.cfg:access-list tun-opelgmbh extended permit ip object-group mss-opelgmbh object-group fa-opelgmbh time-range End-Mar-20
	# 
		
	if ($line =~ /^access-list\s/m && $line !~ /remark/m ) { # find the lines *starts* with access-list
		push (@access_list_cmds, $line);
	}
	
	#---------------------
	# Parse Static Routes|
	#---------------------
	
	if ($line =~ /^route\s/m) { # find the lines *starts* with route
		push(@route_cmd,$line);
	}
	
	# -----------------
	# Parse L2L IPSec | 
	# -----------------
	#
	# This parse is strongly based on the order of commands in the cisco asa config.
	# If cisco changes it the complete parse will fail.
	# The order of commands are the following:
	# 1. crypto map <crypto_map_name> <ID> match address <ACL-name>
	# 2. crypto map <crypto_map_name> <ID> set peer <Peer IP> 
	# 3. crypto map <crypto_map_name> <ID> set ikev1 transform-set <transform_set like ESP-AES-256-SHA>
	#
	# --------------------------------------
	# Parse Crypto ACL name from crypto map|
	# --------------------------------------
	#
	# Example:
	# crypto map <crypto_map_name> <ID> match address <ACL-name>
	
	if ($line =~ /^crypto\smap/m && $line =~ /match\saddress/m) { # find the lines *starts* with "crypto map" and contains "match address"
		my @crypto_map_match_cmd = split (' ', $line);
		$cry_map_name_id = join(' ',$crypto_map_match_cmd[2],$crypto_map_match_cmd[3]);
		$cry_matchaddr = $crypto_map_match_cmd[6];
	}

	# ---------------
	# Parse Peer IPs|
	# ---------------
	#
	# Example:
	# crypto map <crypto_map_name> <ID> set peer <Peer IP> 
	
	if ($line =~ /^crypto\smap/m && $line =~ /set peer/m) { # find the lines *starts* with 'crypto map' and contains 'set peer'
		my @crypto_map_peer_cmd = split (' ', $line);
		my $cry_map_name_id_2 = join (' ',$crypto_map_peer_cmd[2],$crypto_map_peer_cmd[3]);
		if ($cry_map_name_id eq $cry_map_name_id_2) {
			$cry_peer = $crypto_map_peer_cmd[6];
		}
		
	}
	
	# --------------------------
	# Parse IPSec transform set|
	# --------------------------
	# 
	# Example:
	# crypto map <crypto_map_name> <ID> set ikev1 transform-set <transform_set like ESP-AES-256-SHA>
	
	if ($line =~ /^crypto\smap/m && $line =~ /set\sikev1\stransform-set/m) { # find the lines *starts* with "crypto map" and contains "set ikev1 transform-set"
		my @crypto_map_trset_cmd = split (' ', $line);
		my $cry_map_name_id_2 = join (' ',$crypto_map_trset_cmd[2],$crypto_map_trset_cmd[3]);
		if ($cry_map_name_id eq $cry_map_name_id_2) {
			$cry_trset = $crypto_map_trset_cmd[7];
			my $crypto_map_datas = join (' ',$cry_map_name_id,$cry_matchaddr,$cry_peer,$cry_trset);
			push (@crypto_map_datas,$crypto_map_datas);
			# Example "<cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>"
			$cry_matchaddr ='';
			$cry_map_name_id ='';
			$cry_peer ='';
			$cry_trset ='';
		}
	}
	
	#-------------------------------
	#Parse IPSec enabled Interface |
	#-------------------------------
	#
	#
	#example for dynamic map
	#crypto dynamic-map <dynmap-name> <ID> match address <access-list>
	#crypto dynamic-map <dynmap-name> <ID> set ikev1 transform-set <transformsets>
	
	if ($line =~ /^crypto\sdynamic-map/m && $line =~ /match\saddress/m) {
		my @crypto_dynmap_cmd = split (' ', $line);
		$cry_dynmap_acl = $crypto_dynmap_cmd[6];
	}

	if ($line =~ /^crypto\sdynamic-map/m && $line =~ /set\sikev1\stransform-set/m) {
		my @crypto_dynmap_cmd = split (' ', $line);
		push (@crypto_map_datas,$crypto_dynmap_cmd[2]." ".$crypto_dynmap_cmd[3]." ".$cry_dynmap_acl." "."254.254.254.250"." ".$crypto_dynmap_cmd[7]);
		$cry_dynmap_acl ='';
	}
	

	#-------------------------------
	#Parse IPSec enabled Interface |
	#-------------------------------
	# Currently only one :-)
	# crypto map <crypto_map_name> interface <interface_name>
	
	if ($line =~ /^crypto\smap/m && $line =~ /interface/m) { # find the lines *starts* with "crypto map" and contains "interface"
		my @crypto_map_if_cmd = split (' ', $line);
		$crypto_if = $crypto_map_if_cmd[4];
	}
	
}

# 3/3.) Save the IPs of the routers from route command but before get the stupid name commands out
#		from route entries.
##################################################################################################
# name 10.10.10.0 name01
# name 1.2.3.1 name02
# route outside 0.0.0.0 0.0.0.0 1.2.3.4 1
# route inside name01 255.255.255.224 name02 1

my @routeripsunsorted;
my @routerip;
my @route_cmd_nonames;

foreach my $route_cmd (@route_cmd) {
	my @route_cmd_splitted = split (' ', $route_cmd);
	my $router_ip_noname = $route_cmd_splitted[4];
	my $net_ip_noname = $route_cmd_splitted[2];
	
	if ($route_cmd_splitted[4] !~ m/$RE{net}{IPv4}/ ) {
		foreach my $name_cmd (@name_cmd) {
			my @name_cmd_splitted = split (' ',$name_cmd);
			if ($name_cmd_splitted[1] eq $route_cmd_splitted[4]) {
				$router_ip_noname = $name_cmd_splitted[0];
			}
		}
	}
	if ($route_cmd_splitted[2] !~ m/$RE{net}{IPv4}/ ) {
		foreach my $name_cmd (@name_cmd) {
			my @name_cmd_splitted = split (' ',$name_cmd);
			if ($name_cmd_splitted[1] eq $route_cmd_splitted[2]) {
				$net_ip_noname = $name_cmd_splitted[0];
			}
		}
	}
	push (@route_cmd_nonames,$route_cmd_splitted[0]." ".$route_cmd_splitted[1]." ".$net_ip_noname." ".$route_cmd_splitted[3]." ".$router_ip_noname." ".$route_cmd_splitted[5]);
}
@route_cmd = @route_cmd_nonames;

foreach my $route_cmd (@route_cmd) {
	my @route_cmd_splitted = split (' ', $route_cmd);
	push (@routeripsunsorted,$route_cmd_splitted[4]);
}
@routerip = uniq (@routeripsunsorted);

# 3/4/1.) ungroup group-in-group objects 2 times!
##################################################################################################
# it can be done more times as 2... but now just 2 times
#

# group in group 1.

foreach my $object_group1 (@object_groups) {
	my @object_group_splitted1 = split (' ', $object_group1);
	if ($object_group_splitted1[1] eq 'group-object') {
		foreach my $object_group2 (@object_groups) {
			my @object_group_splitted2 = split (' ', $object_group2);
			if ($object_group_splitted1[2] eq $object_group_splitted2[0]) {
				my $temp = join(' ',$object_group_splitted1[0],$object_group_splitted2[1],$object_group_splitted2[2]);
				push(@object_groups_ungrupped,$temp);
			}
		}
	}
	else {
		push(@object_groups_ungrupped,$object_group1);
	}
}

# group in group 2.

foreach my $object_group1 (@object_groups_ungrupped) {
	my @object_group_splitted1 = split (' ', $object_group1);
	if ($object_group_splitted1[1] eq 'group-object') {
		foreach my $object_group2 (@object_groups_ungrupped) {
			my @object_group_splitted2 = split (' ', $object_group2);
			if ($object_group_splitted1[2] eq $object_group_splitted2[0]) {
				my $temp = join(' ',$object_group_splitted1[0],$object_group_splitted2[1],$object_group_splitted2[2]);
				push(@object_groups_ungrupped1,$temp);
			}
		}
	}
	else {
		push(@object_groups_ungrupped1,$object_group1);
	}
}

# 3/4/2.) extract ips from the access-lists
##################################################################################################
# the object and object groups are now extracted.
# We can use them to extract the ACLs.
# the services are now not yet part of the extraction.
#
# Idea for this code used from http://www.perlmonks.org/?node_id=906142

#my $acl_name;
#my $acl_action;
#my $acl_protocol;
#my $acl_src;
#my $acl_src_port;
#my $acl_dst;
#my $acl_dst_port;

my $cisco_protocol = qr {
    (?:ip|tcp|udp|icmp|esp) 
    |
    (?:object-group\s+[\S]+)
}x;
# icmp code types are not tested!

my $cisco_network = qr{
    (?:host\s+[\S]+)
    |
	(?:object\s+[\S]+)
    |
    (?:$RE{net}{IPv4}\s+$RE{net}{IPv4})
    |
    (?:object-group\s+[\S]+)
    |
    any
}x;

my $cisco_ports = qr{
    (?:eq\s+\d+)
    |
	(?:ne\s+\d+)
	|
	(?:gt\s+\d+)
	|
	(?:lt\s+\d+)
	|
    (?:range\s+\d+\s+\d+)
    |
    (?:eq\s+\S+)
    |
	(?:ne\s+\S+)
	|
	(?:gt\s+\S+)
	|
	(?:lt\s+\S+)
}x;

my $cisco_regex = qr{^
    access-list
    \s+
    (?<name>[\S]+) # name
    \s+
    extended
    \s+
    (?<action>(?:permit|deny)) # action
    \s+
    (?<proto>$cisco_protocol) # protocol
    \s+
    (?<source>$cisco_network) # source_network
	(?:\s+(?<src_ports>$cisco_ports))? # source ports
	\s+
    (?<destination>$cisco_network)  # destination_network
    (?:\s+(?<dst_ports>$cisco_ports))? # destination ports
}x;

foreach my $rule (@access_list_cmds) {
    chomp $rule;
    if ( $rule =~ m/$cisco_regex/ ) {
        my $acl_name = $+{name};
        my $acl_action = $+{action};
        my $acl_protocol = $+{proto};
        my $acl_src = $+{source};
        my $acl_src_port = $+{src_ports} if defined $+{src_ports};
		my $acl_dst = $+{destination};
        my $acl_dst_port = $+{dst_ports} if defined $+{dst_ports};

		foreach my $crypto_map_data (@crypto_map_datas) {
			# Example "<cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>"
			my @crypto_map_data_splitted = split (' ',$crypto_map_data);
			if ($crypto_map_data_splitted[2] eq $acl_name) {
				# look for object or object-group in DST
				
				# object_groups array example
				# fa-opelgmbh 192.168.15.32 255.255.255.255
				# fa-opelgmbh 172.17.139.0 255.255.255.192
				
				my @acl_dst_splitted = split(' ',$acl_dst);
				# check if object-group
				if ($acl_dst_splitted[0] eq 'object-group') {
					foreach my $object_group (@object_groups_ungrupped1) {
						my @object_groups_ungrupped1_splitted = split (' ', $object_group);
						if ($acl_dst_splitted[1] eq $object_groups_ungrupped1_splitted[0]) {
							push (@cry_acl_dst_groups, $crypto_map_data_splitted[3]." ".$object_groups_ungrupped1_splitted[1]." ".$object_groups_ungrupped1_splitted[2]);
						}
					}
				}
				# check if object
				elsif ($acl_dst_splitted[0] eq 'object') {
					foreach my $object_network (@object_networks) {
						my @object_network_splitted = split (' ', $object_network);
						if ($acl_dst_splitted[1] eq $object_network_splitted[0]) {
							push (@cry_acl_dst_groups, $crypto_map_data_splitted[3]." ".$object_network_splitted[1]." ".$object_network_splitted[2]);
						}
					}
				}
				# check if host
				elsif ($acl_dst_splitted[0] eq 'host') {
					push (@cry_acl_dst_groups, $crypto_map_data_splitted[3]." ".$acl_dst_splitted[1]." 255.255.255.255");
				}
				# it must be network (ip with netmask)
				else {
					push (@cry_acl_dst_groups, $crypto_map_data_splitted[3]." ".$acl_dst);
				}
				# cry_acl_dst_groups array example
				# 10.10.10.1 192.168.15.32 255.255.255.255
			}
		}
	}
}

@cry_acl_dst_groupsu = uniq(@cry_acl_dst_groups);

# 3/5.) Set the interface place for the graph - after interaction with user
##################################################################################################
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
##################################################################################################

my $side;
my $prompt;
my @interfacesL;
my @interfacesR;
my @interfacesALL;
my $temp8;
my @sides = split(' ','left right');

foreach my $interfaces (@interfaces) {
	my @interfaces_splitted = split (' ', $interfaces);
	push (@interfacesALL,$interfaces_splitted[3]);
}
my @interfacesnameseclevelALL;

foreach my $interfaces (@interfaces) {
	my @interfaces_splitted = split (' ', $interfaces);
	my $interfacesnameseclevel = join (' ', $interfaces_splitted[3], $interfaces_splitted[4]);
	push (@interfacesnameseclevelALL,$interfacesnameseclevel);
}
print "Your firewall has the following interfaces: \n";
print "interfacename security-level:\n";
foreach my $interfacesALL (@interfacesnameseclevelALL) {
	print $interfacesALL, "\n";
}
print "\n";
print "On the graph the interfaces behind the firewall will be on the left side and\n";
print "the interfaces before the firewall will be on the right side \n";
print "\n";

foreach my $interfacesnameseclevelALL (@interfacesnameseclevelALL) {
	my @interfacesnameseclevelALL_splitted = split (' ',$interfacesnameseclevelALL);
	$prompt = join (' ','On which side of the firewall is the interface ',$interfacesnameseclevelALL_splitted[0],'?');
	if ($interfacesnameseclevelALL_splitted[1] > 49) {
		$side = &query($prompt,'rkd',\@sides,'left');
	}
	else {
		$side = &query($prompt,'rkd',\@sides,'right');
	}
	if ($side eq 'left') {
		push (@interfacesL,$interfacesnameseclevelALL_splitted[0]);
	}
	elsif ($side eq 'right') {
		push (@interfacesR,$interfacesnameseclevelALL_splitted[0]);
	}
	print "\n";
}
print "\n";

# query arguments:
# r Some input is required; an empty response will be refused. This option is only meaningful when there is no default input (see the d flag character below).
# k \@Array The next argument is a reference to an array of allowable keywords. The input is matched against the array elements in a case-insensitive manner, with unambiguous abbreviations allowed. This flag implies the s flag.
# d The next argument is the default input. This string is used instead of an empty response from the user. The default value can be a scalar value, a reference to a scalar value, or a reference to a subroutine, which will be invoked for its result only if a default value is needed (no input is given).
# source: http://search.cpan.org/~akste/Term-Query-2.0/Query.pm

##################################################################################################
# 3.) Setup initialisation - END
##################################################################################################

##################################################################################################
# 4.) Create and print the DOT file for graphviz - BEGIN
##################################################################################################

print "\n";
print "\n";
print "\n";
print "\n";

open STDOUT, '>', "$outfilename";
print "#Saving output to $outfilename.dot";

print "\n";
print "digraph G {\n";
print "rankdir=LR\n";
print "\n";

# 4/1.) Firewall Node
#
##################################################################################################

print "# 1.) Description: node for the firewall\n";
print "# Syntax: firewall1 [shape=none, fontsize=11, label=\"firewall1\", labelloc=\"b\", image=\"firewall.gif\"]\n";
print "\n";
print "\"",$hostname_cmd[1], "\" [shape=none, fontsize=11, label=\"", $hostname_cmd[1], "\", labelloc=\"b\", image=\"firewall.gif\"]\n";
print "\n";

# 4/2.) Direct Net Node
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
##################################################################################################

print "# 2.) Description: nodes for directly connected nets\n";
print "# Syntax:\n";
print "# Nets1 [shape=none, fontsize=11, label=\"10.1.1.0/24\\ndomainname1\", image=\"cloud.gif\"]\n";
print "# Netz12700132 [shape=none, fontsize=11, label=\"127.0.0.1/32\\n\", image=\"cloud.gif\"]\n";
print "\n";

foreach my $interfaces (@interfaces) {
	my @interfaces_splitted = split (' ', $interfaces);
	my $interfaceipnet = join ('/',$interfaces_splitted[1],$interfaces_splitted[2]);
	my $interfaceipblock = Net::Netmask->new($interfaceipnet);
	my @interfaceip = split ('\.', $interfaces_splitted[1]);
	
	print "Netz",@interfaceip," [shape=none, fontsize=11, label=\"", $interfaceipblock->base(),"/",$interfaceipblock->bits(),"\\n vlan ",$interfaces_splitted[5], "\", image=\"cloud.gif\"]\n";	
}
print "\n";

# 4/3.) Static Net Node
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

print "# 3.) Description: nodes for static route nets\n";
print "# Syntax: Rnetstorouter10101010 [shape=Mrecord, fontsize=11, label=\"10.1.1.0/24\\n10.1.2.0/24\", style=filled, fillcolor=red]\n";
print "# Syntax: Rhoststorouter10101010 [shape=Mrecord, fontsize=11, label=\"10.1.1.1/32\\n10.1.2.20/32\", style=filled, fillcolor=red]\n";
print "\n";

foreach my $routerip (@routerip) {
	push (my @remotehostlabels,'Host routes|');
	push (my @remotenetlabels,'Network routes|');
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ', $route_cmd);
		if ($routerip eq $route_cmd_splitted[4]) {
			my $remoteipnet = join ('/',$route_cmd_splitted[2],$route_cmd_splitted[3]);
			my $remotenetipblock = Net::Netmask->new($remoteipnet);
			my $remotenetlabel = $remotenetipblock->base() . "/" . $remotenetipblock->bits() . "|";
			if 	($remotenetipblock->bits() eq '32') {
				push (@remotehostlabels,$remotenetlabel);
			}
			else {
				push (@remotenetlabels,$remotenetlabel);
			}
		}
	}
	
	my @routeripnodot = split ('\.', $routerip);
	my $remotenetlabelssize = $#remotenetlabels + 1;
	if ($remotenetlabelssize > 1) {
		print "RNetstorouter",@routeripnodot,"[shape=Mrecord, fontsize=11, label=\"",@remotenetlabels,"\", style=filled, fillcolor=gold]\n";
	}
	my $remotehostlabelssize = $#remotehostlabels + 1;
	if (@remotehostlabels > 1) {
		print "RHoststorouter",@routeripnodot,"[shape=Mrecord, fontsize=11, label=\"",@remotehostlabels,"\", style=filled, fillcolor=darkkhaki]\n";
	}
}
print "\n";

# 4/4.) Crypto ACL Destination Node
# The network that through vpn reachable
#
# cry_acl_dst_groupsu array example
# 10.10.10.1 192.168.15.32 255.255.255.255
# crypto_map_datas array example
# Example "<cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>"
##################################################################################################

print "# 4.) Description: nodes for crypto acl destinations\n";
print "# Syntax: RnetstoIPSecPeer1010101 [shape=Mrecord, fontsize=11, label=\"10.1.1.0/24\\n10.1.2.0/24\", style=filled, fillcolor=red]\n";
print "# Syntax: RhoststoIPSecPeer1010101 [shape=Mrecord, fontsize=11, label=\"10.1.1.1/32\\n10.1.2.20/32\", style=filled, fillcolor=red]\n";
print "\n";

foreach my $crypto_map_data (@crypto_map_datas) {
	my @crypto_map_data_splitted = split (' ', $crypto_map_data);
	push (my @remotehostlabels,'Hosts|');
	push (my @remotenetlabels,'Networks|');
	foreach my $cry_acl_dst_group (@cry_acl_dst_groupsu) {
		my @cry_acl_dst_group_splitted = split (' ', $cry_acl_dst_group);
		if ($crypto_map_data_splitted[3] eq $cry_acl_dst_group_splitted[0]) {
			my $remoteipnet = join ('/',$cry_acl_dst_group_splitted[1],$cry_acl_dst_group_splitted[2]);
			my $remotenetipblock = Net::Netmask->new($remoteipnet);
			my $remotenetlabel = $remotenetipblock->base() . "/" . $remotenetipblock->bits() . "|";
			if 	($remotenetipblock->bits() == '32') {
				push (@remotehostlabels,$remotenetlabel);
			}
			else {
				push (@remotenetlabels,$remotenetlabel);
			}
		}
	}
	
	my @IPSecPeeripnodot = split ('\.', $crypto_map_data_splitted[3]);
	my $remotenetlabelssize = $#remotenetlabels + 1;
	if ($remotenetlabelssize > 1) {
		print "RNetstoIPSecPeer",@IPSecPeeripnodot,"[shape=Mrecord, fontsize=11, label=\"",@remotenetlabels,"\", style=filled, fillcolor=firebrick1]\n";
	}
	my $remotehostlabelssize = $#remotehostlabels + 1;
	if (@remotehostlabels > 1) {
		print "RHoststoIPSecPeer",@IPSecPeeripnodot,"[shape=Mrecord, fontsize=11, label=\"",@remotehostlabels,"\", style=filled, fillcolor=firebrick3]\n";
	}
}
print "\n";

# 4/5.) Next-hop Node
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
# firewallinterfaces array example:
# myfirewall Port-channel1.251 192.168.250.1 255.255.255.240 sweden
# myfirewall Port-channel1.252 192.168.250.17 255.255.255.240 china
##################################################################################################

print "# 5.) Description: nodes for next hops\n";
print "# Syntax: Router1010102 [shape=none, fontsize=11, label=\"\", image=\"router.gif\"]\n";
print "\n";

my $itwasfirewall;

foreach my $routerip (@routerip) {
	my @routerip_splitted = split ('\.', $routerip);
	$itwasfirewall = 'false';
	foreach my $firewallinterface (@firewallinterfaces) {
		my @firewallinterface_splitted = split (' ',$firewallinterface);
		if ($routerip eq $firewallinterface_splitted[2]) {
			print "Router",@routerip_splitted," [shape=none, fontsize=11, label=\"",$routerip,"\\n",$firewallinterface_splitted[0]," - IF: ",$firewallinterface_splitted[4],"\", labelloc=\"b\", image=\"firewall.gif\"]\n";
			$itwasfirewall = 'true';
		}
	}
	if ($itwasfirewall eq 'false') {
		print "Router",@routerip_splitted," [shape=none, fontsize=11, label=\"",$routerip,"\", labelloc=\"b\", image=\"router.gif\"]\n";
	}
}
print "\n";

# 4/6.) Crypto IPSec Peer Node
#
# crypto_map_datas example: "<cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>"
# crypto_if example: "outside"
##################################################################################################

print "# 6.) Description: nodes for IPSec Peer node\n";
print "# Syntax: IPSecPeer1010101 [shape=none, fontsize=11, label=\"10.10.10.1\", image=\"router.gif\"]\n";
print "\n";

foreach my $crypto_map_data (@crypto_map_datas) {
	my @crypto_map_data_splitted = split (' ', $crypto_map_data);
	my @crypto_peerip_splitted = split ('\.',$crypto_map_data_splitted[3]);
	if ($crypto_map_data_splitted[3] = '254.254.254.250')  {
		print "IPSecPeer",@crypto_peerip_splitted," [shape=none, fontsize=11, label=\"","dynamic IP","\\n",$crypto_map_data_splitted[4],"\\n",$crypto_map_data_splitted[2],"\", labelloc=\"b\", image=\"router.gif\"]\n";
	}
	else {
		print "IPSecPeer",@crypto_peerip_splitted," [shape=none, fontsize=11, label=\"",$crypto_map_data_splitted[3],"\\n",$crypto_map_data_splitted[4],"\\n",$crypto_map_data_splitted[2],"\", labelloc=\"b\", image=\"router.gif\"]\n";
	}
}
print "\n";

# 4/7) Firewall Interface Table Node - Right side
#
##################################################################################################

print "# 7.) Description: record based node for firewall interface tables for the right side\n";
print "# Syntax: FirewallIFsR [shape=Mrecord, fontsize=11, label=\"<IF1> IF1 sec-level SEC-LEVEL\\n10.1.1.1|<IF2> IF2 sec-level SEC-LEVEL\\n10.1.2.1\", style=filled, fillcolor=firebrick]\n";
print "\n";

# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
##################################################################################################

my @temp3;

foreach my $interfacesR (@interfacesR){
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfaces_splitted[3] eq $interfacesR) {
			my $firewallipnet = join ('/',$interfaces_splitted[1],$interfaces_splitted[2]);
			my $firewallipblock = Net::Netmask->new($firewallipnet);
			my $interfacesRlabel = "<". $interfaces_splitted[3] . ">" . " " . $interfaces_splitted[3] . " sec-level " . $interfaces_splitted[4] . "\\n" . $interfaces_splitted[1] . "/\\" . $firewallipblock->bits() . "|";
			push (@temp3, $interfacesRlabel);
		}
	}
}

print "\"". $hostname_cmd[1],"IFsR\""," [shape=Mrecord, fontsize=11, label=\"",@temp3,"\", style=filled, fillcolor=firebrick]\n";
print "\n";
$#temp3 = -1;

# 4/8.) Firewall Interface Table Node - Left side
#
##################################################################################################

print "# 8.) Description: record based node for firewall interface tables for the left side\n";
print "# Syntax: FirewallIFsR [shape=Mrecord, fontsize=11, label=\"<IF3> IF3 sec-level SEC-LEVEL\\n10.1.3.1|<IF4> IF4 sec-level SEC-LEVEL\\n10.1.4.1\", style=filled, fillcolor=firebrick]\n";
print "\n";

foreach my $interfacesL (@interfacesL){
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfaces_splitted[3] eq $interfacesL) {
			my $firewallipnet = join ('/',$interfaces_splitted[1],$interfaces_splitted[2]);
			my $firewallipblock = Net::Netmask->new($firewallipnet);
			my $interfacesLlabel = "<" . $interfaces_splitted[3] . ">" . " " . $interfaces_splitted[3] . " sec-level " . $interfaces_splitted[4] . "\\n" . $interfaces_splitted[1] . "/\\" . $firewallipblock->bits() . "|";
			push (@temp3, $interfacesLlabel);
		}
	}
}

print "\"", $hostname_cmd[1],"IFsL\""," [shape=Mrecord, fontsize=11, label=\"",@temp3,"\", style=filled, fillcolor=firebrick]\n";
print "\n";
$#temp3 = -1;

# 4/9.) Edges for 'firewall interface on the left side' with direct networks only
# and direct networks to routers only for 'firewall interface on the left side'
# and router to network from static route for 'firewall interface on the left side'.
#
##################################################################################################

print "# 9.) Description: edges for 'firewall interface on the left side' to direct net to router and to remote net\n";
print "# Syntax:";
print "# RNetstoIPSecPeer6666 -> IPSecPeer6666 [dir=back]";
print "# RHoststoIPSecPeer6666 -> IPSecPeer6666 [dir=back]";
print "# IPSecPeer6666 -> RNetstorouter202020254 [dir=back]";
print "# Netz5 -> Router1 [dir=back]\n";
print "# Router1 -> Netz3[headlabel=\"10.1.3.2\", dir=back]\n";
print "# Netz3 -> FirewallIFsL:IF1 [dir=back]\n";
print "\n";

# 4/9/A0. Destinations from Crypto ACL to IPSecPeers on the left side of the firewall.
# RnetstoIPSecPeer1010101 -> IPSecPeer1010101 [dir=back]
# RhoststoIPSecPeer1010101 -> IPSecPeer1010101 [dir=back]
#
# cry_acl_dst_groupsu array example
# 10.10.10.1 192.168.15.32 255.255.255.255
# <crypto_peer_ip> <dst_ip> <dst_ip_mask>
# crypto_map_datas array example
# <cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>

foreach my $interfacesL (@interfacesL) {
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
		if ($route_cmd_splitted[1] eq $interfacesL) {
			my $netip_mask = join (':',$route_cmd_splitted[2],$route_cmd_splitted[3]);
			my $netip_block = Net::Netmask->new($netip_mask);
			foreach my $cry_acl_dst_group (@cry_acl_dst_groupsu) {
				my @cry_acl_dst_group_splitted = split(' ',$cry_acl_dst_group);
				my $crypto_peer_ip = $cry_acl_dst_group_splitted[0];
				if ( $netip_block->match($crypto_peer_ip) ) {
					# got the matching route, we can get the next hop ip
					my @crypto_peerip_splitted = split ('\.',$crypto_peer_ip);
					my $cryptonetip_mask = join (':',$cry_acl_dst_group_splitted[1],$cry_acl_dst_group_splitted[2]);
					my $cryptonetip_block = Net::Netmask->new($cryptonetip_mask);
					if ($cryptonetip_block->mask() eq "255.255.255.255") {
						print  "RHoststoIPSecPeer",@crypto_peerip_splitted," -> IPSecPeer", @crypto_peerip_splitted," [dir=back]\n";
					}
					else {
						print "RNetstoIPSecPeer",@crypto_peerip_splitted," -> IPSecPeer", @crypto_peerip_splitted," [dir=back]\n";
					}
				}
			}
		}
	}
}
print "\n";

# 4/9/A1. IPSecPeer to Netz on the left side.
# IPSecPeer15151515 -> Netz0000 [dir=back]
# crypto_map_datas array example "<cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>"
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";

foreach my $interfacesL (@interfacesL) {
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
		if ($route_cmd_splitted[1] eq $interfacesL) {
			my $netip_mask = join (':',$route_cmd_splitted[2],$route_cmd_splitted[3]);
			my $netip_block = Net::Netmask->new($netip_mask);
			foreach my $crypto_map_data (@crypto_map_datas) {
				my @crypto_map_data_splitted = split(' ',$crypto_map_data);
				my $crypto_peer_ip = $crypto_map_data_splitted[3];
				if ( $netip_block->match($crypto_peer_ip) ) {
					# got the matching route, we can get the next hop ip
					my @routeripnodot = split ('\.',$route_cmd_splitted[4]);
					my @crypto_peerip_splitted = split ('\.',$crypto_peer_ip);
					if ($netip_block->mask() eq "255.255.255.255") {
						print  "IPSecPeer",@crypto_peerip_splitted," -> RHoststorouter", @routeripnodot," [dir=back]\n";
					}
					else {
						print "IPSecPeer",@crypto_peerip_splitted," -> RNetstorouter", @routeripnodot," [dir=back]\n";
					}
				}
			}
		}
	}
}
# 4/9/A2.) 'networks from static route' to routers for 'firewall interfaces on the left side'
# Example: Netz00000 -> Router1010103 [dir=back]
# 
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
#
##################################################################################################

my @routeripunsorted; 
my @routeripsorted;
my $routeripunsortedroutetype;

foreach my $interfacesL (@interfacesL) {
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
		if ($route_cmd_splitted[1] eq $interfacesL) {
			if ($route_cmd_splitted[3] eq '255.255.255.255') {
				$routeripunsortedroutetype = join (' ', $route_cmd_splitted[4], 'H');
			}
			else {
				$routeripunsortedroutetype = join (' ', $route_cmd_splitted[4], 'N');
			}
			push (@routeripunsorted, $routeripunsortedroutetype);
		}
	}
}
@routeripsorted = uniq(@routeripunsorted);
foreach my $routeripsorted (@routeripsorted) {
	my @routeripsorted_splitted = split (' ', $routeripsorted);
	my @routeripnodot = split ('\.',$routeripsorted_splitted[0]); # router ip without dots
	if ($routeripsorted_splitted[1] eq 'H') {
		print "RHoststorouter",@routeripnodot," -> Router", @routeripnodot," [dir=back]\n";
	}
	if ($routeripsorted_splitted[1] eq 'N') {
		print "RNetstorouter",@routeripnodot," -> Router", @routeripnodot," [dir=back]\n";
	}
}
print "\n";

# 4/9/B.) Routers to direkt networks for 'interfaces on the left side'
# Example: Router1010103 -> Netz1010101 [dir=back]
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

my @localnet; # local network of the firewall
my $routerip1;

foreach my $interfacesL (@interfacesL) {
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfacesL eq $interfaces_splitted[3]) { # interface name match
			@localnet = split ('\.', $interfaces_splitted[1]); # interface ip
		}
	}
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
			if ($route_cmd_splitted[1] eq $interfacesL) { # interface name match
				if ($routerip1 ne $route_cmd_splitted[4]) { # with the routerip1 will be filtered to only one occurrence of the router ips.
					my @routeripnodot = split ('\.',$route_cmd_splitted[4]); # router ip from route_cmd without points
					print "Router",@routeripnodot," -> ","Netz",@localnet," [dir=back]\n";
				}
			$routerip1 = $route_cmd_splitted[4];
		}
	}
}
$routerip1 = '';
print "\n";

# 4/9/C.) Edge for: Direct netz to firewall interfaces on the left side
# Example: Netz1010101 -> firewall1IFsL:china [dir=back]
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
##################################################################################################

foreach my $interfacesL (@interfacesL){
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfaces_splitted[3] eq $interfacesL) {
			my @interfaceip = split ('\.', $interfaces_splitted[1]);
			print "Netz", @interfaceip, " -> \"", $hostname_cmd[1], "IFsL\":\"", $interfaces_splitted[3] , "\" [dir=back]\n";
		}
	}
}
print "\n";

# 4/10.) Edges for firewall interface table to firewall
#
##################################################################################################

print "# 10.) Description: edges for firewall interface table to firewall\n";
print "# Syntax:\"\n";
print "# FirewallIFsL -> Firewall [dir=none, penwidth=50, color=firebrick]\n";
print "# Firewall -> FirewallIFsR [dir=none, penwidth=50, color=firebrick]\n";
print "\n";

print "\"", $hostname_cmd[1], "IFsL\" -> \"", $hostname_cmd[1], "\" [dir=none, penwidth=50, color=firebrick]\n";
print "\"", $hostname_cmd[1], "\" -> \"", $hostname_cmd[1], "IFsR\" [dir=none, penwidth=50, color=firebrick]\n";
print "\n";

# 4/11.) Edges for 'firewall interface on the right side' with direct networks only
# and direct networks to routers only for 'firewall interface on the right side'
# and router to network from static route for 'firewall interface on the right side'.
#
##################################################################################################

print "# 11.) Description: edges for 'firewall interface on the right side' to direct net to router and to remote net\n";
print "# Syntax:\n";
print "# Firewall1IFsR:IF3 -> Netz3\n";
print "# Netz3 -> Router1 [headlabel=\"10.1.3.2\"]\n";
print "# Router1 -> Netz5\n";
print "\n";

# 4/11/A.) Edges for 'firewall interface on the right side' with direct networks only
# Example: firewall1IFsR:china -> Netz1010101
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
##################################################################################################

foreach my $interfacesR (@interfacesR){
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfaces_splitted[3] eq $interfacesR) {
			my @interfaceip = split ('\.', $interfaces_splitted[1]);
			print "\"", $hostname_cmd[1],"IFsR\":\"", $interfaces_splitted[3], "\" -> Netz", @interfaceip,"\n";
		}
	}
}
print "\n";

# 4/11/B.) Direkt networks to routers for 'firewall interfaces on the right side'
# Example: Netz1010101 -> Router1010103
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

my @localnet; # local network of the firewall

foreach my $interfacesR (@interfacesR) {
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfacesR eq $interfaces_splitted[3]) { # interface name match
			@localnet = split ('\.', $interfaces_splitted[1]); # interface ip
		}
	}
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
			if ($route_cmd_splitted[1] eq $interfacesR) { # interface name match
				if ($routerip1 ne $route_cmd_splitted[4]) { # with the routerip1 will be filtered to only one occurrence of the router ips.
					my @routeripnodot = split ('\.',$route_cmd_splitted[4]); # router ip from route_cmd without points
					print "Netz",@localnet, " -> Router", @routeripnodot,"\n";
				}
			$routerip1 = $route_cmd_splitted[4];
		}
	}
}
$routerip1 = '';
print "\n";

# 4/11/C.) Routers to 'networks from static route' for 'firewall interfaces on the right side'
# Example: Router1010103 -> Netz00000
# 
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################
my @routeripunsortedr; 
my @routeripsortedr;
my $routeripunsortedroutetyper;

foreach my $interfacesR (@interfacesR) {
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
		if ($route_cmd_splitted[1] eq $interfacesR) {
			if ($route_cmd_splitted[3] eq '255.255.255.255') {
				$routeripunsortedroutetyper = join (' ', $route_cmd_splitted[4], 'H');
			}
			else {
				$routeripunsortedroutetyper = join (' ', $route_cmd_splitted[4], 'N');
			}
			push (@routeripunsortedr, $routeripunsortedroutetyper);
		}
	}
}
@routeripsortedr = uniq(@routeripunsortedr);
foreach my $routeripsortedr (@routeripsortedr) {
	my @routeripsortedr_splitted = split (' ', $routeripsortedr);
	my @routeripnodot = split ('\.',$routeripsortedr_splitted[0]); # router ip without dots
	if ($routeripsortedr_splitted[1] eq 'H') {
		print "Router", @routeripnodot," -> RHoststorouter",@routeripnodot,"\n";
	}
	if ($routeripsortedr_splitted[1] eq 'N') {
		print "Router", @routeripnodot," -> RNetstorouter",@routeripnodot,"\n";	
	}
}
print "\n";

# 4/11/D. Destinations from Crypto ACL to IPSecPeers on the right side of the firewall.
# IPSecPeer1010101 -> RnetstoIPSecPeer1010101 [dir=back]
# IPSecPeer1010101 -> RhoststoIPSecPeer1010101 [dir=back]
#
# cry_acl_dst_groupsu array example
# 10.10.10.1 192.168.15.32 255.255.255.255
# <crypto_peer_ip> <dst_ip> <dst_ip_mask>
# crypto_map_datas array example
# <cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>

foreach my $interfacesR (@interfacesR) {
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
		if ($route_cmd_splitted[1] eq $interfacesR) {
			my $netip_mask = join (':',$route_cmd_splitted[2],$route_cmd_splitted[3]);
			my $netip_block = Net::Netmask->new($netip_mask);
			foreach my $cry_acl_dst_group (@cry_acl_dst_groupsu) {
				my @cry_acl_dst_group_splitted = split(' ',$cry_acl_dst_group);
				my $crypto_peer_ip = $cry_acl_dst_group_splitted[0];
				if ( $netip_block->match($crypto_peer_ip) ) {
					# got the matching route, we can get the next hop ip
					my @crypto_peerip_splitted = split ('\.',$crypto_peer_ip);
					my $cryptonetip_mask = join (':',$cry_acl_dst_group_splitted[1],$cry_acl_dst_group_splitted[2]);
					my $cryptonetip_block = Net::Netmask->new($cryptonetip_mask);
					if ($cryptonetip_block->mask() eq "255.255.255.255") {
						print "IPSecPeer",@crypto_peerip_splitted," -> RHoststoIPSecPeer", @crypto_peerip_splitted," [dir=back]\n";
					}
					else {
						print "IPSecPeer",@crypto_peerip_splitted," -> RNetstoIPSecPeer", @crypto_peerip_splitted," [dir=back]\n";
					}
				}
			}
		}
	}
}
print "\n";

# 4/11/E. IPSecPeer to Netz on the right side.
# Netz0000 -> IPSecPeer15151515 [dir=back]
# crypto_map_datas array example "<cry_map_name> <cry_ID> <cry-acl_name> <cry_peer_ip> <cry_transformset_name>"
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";

foreach my $interfacesR (@interfacesR) {
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
		if ($route_cmd_splitted[1] eq $interfacesR) {
			my $netip_mask = join (':',$route_cmd_splitted[2],$route_cmd_splitted[3]);
			my $netip_block = Net::Netmask->new($netip_mask);
			foreach my $crypto_map_data (@crypto_map_datas) {
				my @crypto_map_data_splitted = split(' ',$crypto_map_data);
				my $crypto_peer_ip = $crypto_map_data_splitted[3];
				if ( $netip_block->match($crypto_peer_ip) ) {
					# got the matching route, we can get the next hop ip
					my @routeripnodot = split ('\.',$route_cmd_splitted[4]);
					my @crypto_peerip_splitted = split ('\.',$crypto_peer_ip);
					if ($netip_block->mask() eq "255.255.255.255") {
						print "RHoststorouter",@routeripnodot," -> IPSecPeer", @crypto_peerip_splitted," [dir=back]\n";
					}
					else {
						print "RNetstorouter",@routeripnodot," -> IPSecPeer", @crypto_peerip_splitted," [dir=back]\n";
					}
				}
			}
		}
	}
}

print "}\n";
close (STDOUT);
print "#done\n";

##################################################################################################
# 4.) Create and print the DOT file for graphviz - END
##################################################################################################

##################################################################################################
# 5.) Create the graph in png and svg format - BEGIN
##################################################################################################

my $commandpng = "dot -Tpng -O " . $ARGV[1];
my $commandsvg = "dot -Tsvg -O " . $ARGV[1];

system ($commandpng);
if ( $? == -1 )
{
  print "command failed: $!\n";
}
system ($commandsvg);
if ( $? == -1 )
{
  print "command failed: $!\n";
}

##################################################################################################
# 5.) Create the graph in png and svg format - END
##################################################################################################