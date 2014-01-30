#!/usr/bin/perl
# Author: Akos
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
# -----------------------------------------------------------------------------------------------
# [solved] if name is used it will not work. Do not use names! Like "route inside 1.1.1.0 255.255.255.0 intern-router"
# -----------------------------------------------------------------------------------------------
# Change History
# 18.12.13 name commands are prased too. The route entries with names are parsed to IPs.
# 18.12.13 if there is no vlan on the interface where there is an IP, I write "vlan no"
# 18.12.13 the automatic interface positioning is set based on security level.
# 		   if the security-level > 49 put it on the left side, else put on right side.
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
print "\n==| asa-graphviz-builder_with_tables.pl v. 0.1 beta (10th of July 2013) by Akos \(no\@email.today\) |==\n";

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

		# Parse Hostname

		if ($line =~ /^hostname/m) { # find the lines *starts* with hostname
			@hostname_cmd = split (' ', $line);
		}

		# Parse Interfaces
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

my @name_cmd;
my @vlan_cmd;
my @nameif_cmd;
my @seclevel_cmd;
my @ipaddr_cmd;
my @hostname_cmd;
my @route_cmd;
my $interface_found = 'false'; # indicator for interface command
my @interface_cmd;
my @interfaces;

foreach my $line (@Parse_array) {

	# Parse name commands
	# example:
	# name 192.168.1.1 waf01
	# name 192.168.1.2 waf02
	#
	if ($line =~ /^name\s/m) {
		my @name_cmd_splitted = split (' ', $line);
		push (@name_cmd,$name_cmd_splitted[1]." ".$name_cmd_splitted[2]);
	}
    # Parse Interfaces
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
		if ($vlan_cmd[1] eq /\D/) {$vlan_cmd[1] = "no"};
		my $interfaceparams =  join (' ', $interface_cmd[1],$ipaddr_cmd[2],$ipaddr_cmd[3],$nameif_cmd[1],$seclevel_cmd[1],$vlan_cmd[1]);
		push (@interfaces,$interfaceparams);
		$interface_found = 'false';
	}

	# Parse Static Routes
	#
	if ($line =~ /^route\s/m) { # find the lines *starts* with route
		push(@route_cmd,$line);
	}

	# Parse Hostname

	if ($line =~ /^hostname/m) { # find the lines *starts* with hostname
		@hostname_cmd = split (' ', $line);
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

# 3/4.) Set the interface place for the graph - after interaction with user
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
print "# Syntax: Rnetstorouter1 [shape=Mrecord, fontsize=11, label=\"10.1.1.0/24\\n10.1.2.0/24\", style=filled, fillcolor=red]\n";
print "# Syntax: Rhoststorouter1 [shape=Mrecord, fontsize=11, label=\"10.1.1.1/32\\n10.1.2.20/32\", style=filled, fillcolor=red]\n";
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
			if 	($remotenetipblock->bits() == '32') {
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

# 4/4.) Next-hop Node
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
# firewallinterfaces array example:
# asa-btcore-fr2k Port-channel1.251 192.168.250.1 255.255.255.240 sweden
# asa-btcore-fr2k Port-channel1.252 192.168.250.17 255.255.255.240 china
##################################################################################################

print "# 4.) Description: nodes for next hops\n";
print "# Syntax: Router1 [shape=none, fontsize=11, label=\"\", image=\"router.gif\"]\n";
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

# 4/5) Firewall Interface Table Node - Right side
#
##################################################################################################

print "# 5.) Description: record based node for firewall interface tables for the right side\n";
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

# 4/6.) Firewall Interface Table Node - Left side
#
##################################################################################################

print "# 6.) Description: record based node for firewall interface tables for the left side\n";
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

# 4/7.) Edges for 'firewall interface on the left side' with direct networks only
# and direct networks to routers only for 'firewall interface on the left side'
# and router to network from static route for 'firewall interface on the left side'.
#
##################################################################################################

print "# 7.) Description: edges for 'firewall interface on the left side' to direct net to router and to remote net\n";
print "# Syntax:";
print "# Netz5 -> Router1 [dir=back]\n";
print "# Router1 -> Netz3[headlabel=\"10.1.3.2\", dir=back]\n";
print "# Netz3 -> FirewallIFsL:IF1 [dir=back]\n";
print "\n";

# 4/7/A.) 'networks from static route' to routers for 'firewall interfaces on the left side'
# Example: Netz00000 -> Router1010103 [dir=back]
# 
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0 251
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0 252
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

my @routeripunsorted; 
my @routeripsorted;
my $routeripunsortedroutetype;

foreach my $interfacesR (@interfacesL) {
	foreach my $route_cmd (@route_cmd) {
		my @route_cmd_splitted = split (' ',$route_cmd);
		if ($route_cmd_splitted[1] eq $interfacesR) {
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

# 4/7/B.) Routers to direkt networks for 'interfaces on the left side'
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

# 4/7/C.) Edge for: Direct netz to firewall interfaces on the left side
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

# 4/8.) Edges for firewall interface table to firewall
#
##################################################################################################

print "# 8.) Description: edges for firewall interface table to firewall\n";
print "# Syntax:\"\n";
print "# FirewallIFsL -> Firewall [dir=none, penwidth=50, color=firebrick]\n";
print "# Firewall -> FirewallIFsR [dir=none, penwidth=50, color=firebrick]\n";
print "\n";

print "\"", $hostname_cmd[1], "IFsL\" -> \"", $hostname_cmd[1], "\" [dir=none, penwidth=50, color=firebrick]\n";
print "\"", $hostname_cmd[1], "\" -> \"", $hostname_cmd[1], "IFsR\" [dir=none, penwidth=50, color=firebrick]\n";
print "\n";

# 4/9.) Edges for 'firewall interface on the right side' with direct networks only
# and direct networks to routers only for 'firewall interface on the right side'
# and router to network from static route for 'firewall interface on the right side'.
#
##################################################################################################

print "# 9.) Description: edges for 'firewall interface on the right side' to direct net to router and to remote net\n";
print "# Syntax:\n";
print "# Firewall1IFsR:IF3 -> Netz3\n";
print "# Netz3 -> Router1 [headlabel=\"10.1.3.2\"]\n";
print "# Router1 -> Netz5\n";
print "\n";

# 4/9/A.) Edges for 'firewall interface on the right side' with direct networks only
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

# 4/9/B.) Direkt networks to routers for 'interfaces on the right side'
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

# 4/9/C.) Routers to 'networks from static route'
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