#!/usr/bin/perl
# Author: Akos Daniel (daniel.akos77ATgmail.com)
# Filename: router-topo-graphviz-builder.pl
# Current Version: 0.1 beta
# Created: 10th of July 2013
# Last Changed: 10th of July 2013
# -----------------------------------------------------------------------------------------------
# Description:
# -----------------------------------------------------------------------------------------------
# This is a rather crude and quick hacked Perl-script to build a config file
# for neato to make beautiful graphs or topologies automaticaly.
# The script supports only cisco router vlan configs.
# -----------------------------------------------------------------------------------------------
# Known issues:
# -----------------------------------------------------------------------------------------------
# - cfg files are not checked if the are exists
# - Netz Nodes can be duplicated in dot file. neato solves it, but should be cleared here.
# -----------------------------------------------------------------------------------------------
# Change History
# -----------------------------------------------------------------------------------------------
# 0.1 beta: (10th of July 2013)

use strict;
use Net::Netmask; # http://perltips.wikidot.com/module-net:netmask
use List::MoreUtils qw(uniq);
use Array::Utils qw(:all);

##################################################################################################
# 1.) Declare global variables start
##################################################################################################

my @hostnameifdatas;
my @routers_data;
my $outfilename = "topo.dot";
my @hostnames;
my @files = <*6509*.cfg>;

##################################################################################################
# 1.) Declare global variables end
##################################################################################################

##################################################################################################
# 2.) Input parser - Start
##################################################################################################
# Open cfg files one by one and put the important rows from the configurations in one HUGE array

print "\n==| router-topo-graphviz-builder.pl v. 0.1 beta (13th of Aug 2013) by Akos \(daniel.akos77ATgmail.com\) |==\n";
print "Start loading the configuration files:\n";

foreach my $file (@files) {
 
    open (PARSEFILE,$file) || die ("==| Error! Could not open file $ARGV[0]");
    print "\nLoading Router Configuration-file from $file cfg file...";
    my @Parse_array = <PARSEFILE>;
    print "Loading finished, starting parse..\n";

	my $interface_found = 'false'; # indicator for interface command
	my @interface_cmd;
	my @ipaddr_cmd;
	my @vrrp_cmd;
	my @interfaces;
	my @hostname_cmd;
	my @route_cmd;

	################################################################################################
	# Put the interface datas, routes and hostname in an array
	################################################################################################
	
	foreach my $line (@Parse_array) {

		# Parse Interfaces
		# The order of if statements is important. 
		# This is currently the following: interface->vlan->nameif->security-level->ip address

		if ($line =~ /^interface Vlan/m) { # find the lines *starts* with interface
			@interface_cmd = split (' ', $line);
			$interface_found = 'true';
		}
		if ($line =~ /^\sip\saddress/m && $interface_found eq 'true') { # find the lines *starts* with <space>vlan
			@ipaddr_cmd = split (' ', $line);
		}
		if ($line =~ /^\svrrp\s(\d+)\sip/m && $interface_found eq 'true') { # find the lines *starts* with <space>ip address
			@vrrp_cmd = split (' ', $line);
			my $if_data =  join (' ', $interface_cmd[1],$ipaddr_cmd[2],$ipaddr_cmd[3],$vrrp_cmd[1],$vrrp_cmd[3]);
			push (@interfaces,$if_data);
			$interface_found = 'false';
		}
   
		# Parse Hostname

		if ($line =~ /^hostname/m) { # find the lines *starts* with hostname
			@hostname_cmd = split (' ', $line);
			push (@hostnames,$hostname_cmd[1]);
		}

		# Parse routers
		
		if ($line =~ /^ip\sroute\s/m) { # find the lines *starts* with route
			push(@route_cmd,$line);
		}
	}   
	
	# Put hostnames with interface datas together in an array
	foreach my $interface (@interfaces) {
		my $hostnameifdata = join (' ',$hostname_cmd[1],$interface);
		push (@hostnameifdatas,$hostnameifdata);
	}
	
	# Put the router IPs in an array - unsorted
	# route_cmd array example: ip route 164.139.60.0 255.255.255.0 172.16.3.111
	##################################################################################################
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ', $route_cmd);
		my $router_data = join (' ',$hostname_cmd[1],$route_cmd_splitted[4]);
		push (@routers_data,$router_data);
	}
	
	close (PARSEFILE);
}
print "\n";
print "Setup done\n";
##################################################################################################
# 2.) Input parser - End
##################################################################################################

##################################################################################################
# 3.) Create and print the DOT file for neato - Start
##################################################################################################

print "\n";
print "\n";
print "Saving output to $outfilename";
print "\n";
print "\n";

open STDOUT, '>', "$outfilename";

print "\n";
print "graph G {\n";
print "graph [overlap=false, splines=true]";
print "\n";

# 3.1.) Description: node for router
# "router1" [shape=none, label="router1", labelloc="b", image="router.gif"];

foreach my $hostname (@hostnames) {
	print "\"",$hostname,"\" [shape=none, label=\"", $hostname, "\", labelloc=\"b\", image=\"router.gif\"]\n";
}

my @routers_data_uniq = uniq (@routers_data);
my @routers_data_uniq_sort= sort {$a <=> $b} @routers_data_uniq;
foreach my $router_data_uniq_sort (@routers_data_uniq_sort) {
	my @router_data_splitted = split (' ', $router_data_uniq_sort);
	my @routerip_splitted = split ('\.', $router_data_splitted[1]);
	print "\"router",@routerip_splitted,"\" [shape=none, label=\"", $router_data_splitted[1], "\", labelloc=\"b\", image=\"router.gif\"]\n";
}

# 3.2.) Description: nodes for directly connected nets
# Syntax:
# Netz111024 [shape=none, label="1.1.1.0/24", image="cloud.gif"];
# Netz222024 [shape=none, label="2.2.2.0/24", image="cloud.gif"];
# Netz333024 [shape=none, label="3.3.3.0/24", image="cloud.gif"];

# hostnameifdatas array example:
# vss6509-c001 Vlan114 192.168.14.4 255.255.255.0 114 192.168.14.1
##################################################################################################

my @netnodes;
foreach my $hostnameifdata (@hostnameifdatas) {
	my @hostnameifdata_splitted = split (' ', $hostnameifdata);
	my $routeripnet = join ('/',$hostnameifdata_splitted[2],$hostnameifdata_splitted[3]);
	my $routeripblock = Net::Netmask->new($routeripnet);
	my @routeripblockbase_splitted = split ('\.', $routeripblock->base());
	my $netnode = join('',"Netz",@routeripblockbase_splitted,$routeripblock->bits()," [shape=none, label=\"",$routeripblock->base(),"/",$routeripblock->bits(),"\", image=\"cloud.gif\"]\n");
	push (@netnodes, $netnode);
}
my @netnodes_uniq = uniq (@netnodes);
foreach my $netnodes_uniq (@netnodes_uniq) {
	print $netnodes_uniq;
}

# 3.3.) edges for netz nodes and router nodes
#
# router1 -- Netz111024 [taillabel="Ethernet0\n1.1.1.10/\24"];
# router1 -- Netz333024 [taillabel="Ethernet1\n3.3.3.10/\24"];

# hostnameifdatas array example:
# vss6509-c001 Vlan114 192.168.14.4 255.255.255.0 114 192.168.14.1
# routers_data array example
# vss6509-c001 172.16.3.111
##################################################################################################

foreach my $hostnameifdata (@hostnameifdatas) {
	my @hostnameifdata_splitted = split (' ', $hostnameifdata);
	my $routeripnet = join ('/',$hostnameifdata_splitted[2],$hostnameifdata_splitted[3]);
	my $routeripblock = Net::Netmask->new($routeripnet);
	my @routeripblockbase_splitted = split ('\.', $routeripblock->base());
	print "\"",$hostnameifdata_splitted[0],"\" -- Netz",@routeripblockbase_splitted,$routeripblock->bits()," [labeldistance=10 ,taillabel=\"",$hostnameifdata_splitted[4],"\\n",$hostnameifdata_splitted[2],"/",$routeripblock->bits(),"\"]\n";
}

print "}\n";

##################################################################################################
# 3.) Create and print the DOT file for neato - End
##################################################################################################