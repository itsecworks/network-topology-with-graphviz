#!/usr/bin/perl
# Author: Akos (daniel.akos@media.saturn.com)
# Filename: asa-graphviz-builder_with_gifs.pl
# Current Version: 0.1 beta
# Created: 10th of July 2013
# Last Changed: 10th of July 2013
# -----------------------------------------------------------------------------------------------
# Description:
# -----------------------------------------------------------------------------------------------
# This is a rather crude and quick hacked Perl-script to build a config file
# for dot to make beautiful topologies automaticaly. This script paints cloud for the routed
# networks and a pc for host routes.
# -----------------------------------------------------------------------------------------------
# Known issues:
# -----------------------------------------------------------------------------------------------
# if name is used it will not work. Do not use names! Like "route inside 1.1.1.0 255.255.255.0 intern-router"
# -----------------------------------------------------------------------------------------------
# Change History
# -----------------------------------------------------------------------------------------------
# 0.1 beta: (10th of July 2013)
# Not Updated any more, just for external requests. (I use tables for the routed networks and hosts.)
# Use asa-graphviz-builder_with_tables.pl instead.

use strict;
use Net::Netmask; # http://perltips.wikidot.com/module-net:netmask
use List::MoreUtils qw(uniq);
use Array::Utils qw(:all);
use Term::Query qw( query);

##################################################################################################
# Declare variables start
##################################################################################################

my @hostname_cmd;
my @route_cmd;
my $interface_found = 'false'; # indicator for interface command
my @interface_cmd;
my @interfaces;
my @nameif_cmd;
my @seclevel_cmd;
my @ipaddr_cmd;
my $temp;
my @temp3;
my @routerip;
my $routerip1;
my @interfacesL;
my @interfacesR;
my @interfacesALL;

##################################################################################################
# Declare variables end
##################################################################################################

##################################################################################################
# Syntax start
##################################################################################################

my $numberofargs = @ARGV;
my $outfilename = $ARGV[1];
print "\n==| asa-graphviz-builder.pl v. 0.1 beta (10th of July 2013) by Akos \(daniel.akosATmedia.saturn.com\) |==\n";

if ($numberofargs < 2) {

    print "\nSyntax:\n";
    print "-------\n";
    print "asa-graphviz-builder.pl <Input filename> <Output filename>\n";
    print "\n";
    print "Mandatory arguments:\n";
    print "-------------------\n";
    print " <Input filename> : Name of inputfile. This file should contain the Cisco ASA configuration\n";
    print " <Output filename> : Name of outputfile\n";
    die ("\n");

    } # End if

##################################################################################################
# Syntax end
##################################################################################################

##################################################################################################
# Setup start - Save the interfaces, routes and hostname in a variable
##################################################################################################

### A.) Open input-file and put the contents in one HUGE array
##################################################################################################

open (PARSEFILE,$ARGV[0]) || die ("==| Error! Could not open file $ARGV[0]");

print "\nLoading ASA Configuration-file from $ARGV[0]...";

my @Parse_array = <PARSEFILE>;
my $Parsefile_size = @Parse_array;
print "Done\n";

close (PARSEFILE);

### B.) Save the interfaces, routes and hostname in arrays and variable
##################################################################################################

foreach my $line (@Parse_array) {

    # Parse Interfaces
    # The order of if statements is important. 
    # This is currently the following: interface->nameif->security-level->ip address

   if ($line =~ /^interface/m) { # find the lines *starts* with interface
      @interface_cmd = split (' ', $line);
      $interface_found = 'true';
	}
   if ($line =~ /^\snameif/m && $interface_found eq 'true') { # find the lines *starts* with <space>nameif
      @nameif_cmd = split (' ', $line);
	}
   if ($line =~ /^\ssecurity-level/m && $interface_found eq 'true') { # find the lines *starts* with <space>security-level
      @seclevel_cmd = split (' ', $line);
   }
   if ($line =~ /^\sip\saddress/m && $interface_found eq 'true') { # find the lines *starts* with <space>ip address
      @ipaddr_cmd = split (' ', $line);
	  $temp =  join (' ', $interface_cmd[1],$ipaddr_cmd[2],$ipaddr_cmd[3],$nameif_cmd[1],$seclevel_cmd[1]);
	  push (@interfaces,$temp);
	  $temp= '';
      $interface_found = 'false';
   }
   
   # Parse Static Routes
   
   if ($line =~ /^route\s/m) { # find the lines *starts* with route
      push(@route_cmd,$line);
   }
   
   # Parse Hostname

   if ($line =~ /^hostname/m) { # find the lines *starts* with hostname
      @hostname_cmd = split (' ', $line);
	}
}
$temp ='';


### C.) Set the interface place for the graph - after interaction with user
##################################################################################################
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
##################################################################################################

my @sides;
my $side;
my $prompt;
my @interfacesL;
my @interfacesR;
my $temp8;

@sides = split(' ','left right');

foreach my $interfaces (@interfaces) {
	my @interfaces_splitted = split (' ', $interfaces);
	push (@temp3,$interfaces_splitted[3]);
}
@interfacesALL = uniq (@temp3);
$#temp3 = -1;

print "Your firewall has the following interfaces: \n";
foreach my $interfacesALL (@interfacesALL) {
	print $interfacesALL, "\n";
}
print "\n";
print "On the graph he interfaces behind he firewall are on the left side and\n";
print "the interfaces befor the firewall are on the right side \n";
print "\n";
foreach my $interfacesALL (@interfacesALL) {
	$prompt = join (' ','On which side of the firewall is the interface ',$interfacesALL,'?');
	if ($interfacesALL eq 'inside') {
		$side = &query($prompt,'rkd',\@sides,'left');
	}
	else {
		$side = &query($prompt,'rkd',\@sides,'right');
	}
	if ($side eq 'left') {
		push (@interfacesL,$interfacesALL);
	}
	elsif ($side eq 'right') {
		push (@interfacesR,$interfacesALL);
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
# Setup end
##################################################################################################

##################################################################################################
# Create and print the DOT file for graphviz
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

# 1.) Firewall Node
#
##################################################################################################

print "# 1.) Description: node for the firewall\n";
print "# Syntax: firewall1 [shape=none, fontsize=11, label=\"firewall1\", labelloc=\"b\", image=\"firewall.gif\"]\n";
print "\n";
print "\"",$hostname_cmd[1], "\" [shape=none, fontsize=11, label=\"", $hostname_cmd[1], "\", labelloc=\"b\", image=\"firewall.gif\"]\n";
print "\n";

# 2.) Direct Net Node
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
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
	
	print "Netz",@interfaceip," [shape=none, fontsize=11, label=\"", $interfaceipblock->base(),"/",$interfaceipblock->bits(),"\\n\", image=\"cloud.gif\"]\n";	
}
print "\n";

# 3.) Static Net Node
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

print "# 3.) Description: nodes for static route nets\n";
print "# Syntax: Nets1 [shape=none, fontsize=11, labelloc=\"b\", label=\"10.1.1.3/32\\ndomainname2\", image=\"host.gif\"]\n";
print "# Syntax: Nets1 [shape=none, fontsize=11, labelloc=\"b\", label=\"10.1.1.0/24\\ndomainname2\", image=\"cloud_routed_net.gif\"]\n";
print "\n";

foreach my $route_cmd (@route_cmd) {
	my @route_cmd_splitted = split (' ', $route_cmd);
	my $remotenetip = join ('/',$route_cmd_splitted[2],$route_cmd_splitted[3]);
	my $remotenetblock = Net::Netmask->new($remotenetip);
	my @remotenetiponly = split ('\.', $route_cmd_splitted[2]);
	if 	($remotenetblock->bits() == 32) {
		print "Netz",@remotenetiponly,$remotenetblock->bits()," [shape=none, fontsize=11, labelloc=\"b\", label=\"", $route_cmd_splitted[2],"/",$remotenetblock->bits(),"\\n\", image=\"host.gif\"]\n";
	}
	else {
		print "Netz",@remotenetiponly,$remotenetblock->bits()," [shape=none, fontsize=11, label=\"", $route_cmd_splitted[2],"/",$remotenetblock->bits(),"\\n\", image=\"cloud_routed_net.gif\"]\n";
	}
}
print "\n";

# 4.) Next-hop Node
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

print "# 4.) Description: nodes for next hops\n";
print "# Syntax: Router1 [shape=none, fontsize=11, label=\"\", image=\"router.gif\"]\n";
print "\n";

foreach my $route_cmd (@route_cmd) {
	my @route_cmd_splitted = split (' ', $route_cmd);
	push (@temp3,$route_cmd_splitted[4]);
}
@routerip = uniq (@temp3);
$#temp3 = -1;

foreach my $routerip (@routerip) {
	my @routerip_splitted = split ('\.', $routerip);
	print "Router",@routerip_splitted," [shape=none, fontsize=11, label=\"",$routerip,"\", labelloc=\"b\", image=\"router.gif\"]\n";
}
print "\n";

# 5) Firewall Interface Table Node - Right side
#
##################################################################################################

print "# 5.) Description: record based node for firewall interface tables for the right side\n";
print "# Syntax: FirewallIFsR [shape=Mrecord, fontsize=11, label=\"<IF1> IF1\\n10.1.1.1|<IF2> IF2\\n10.1.2.1\", style=filled, fillcolor=firebrick]\n";
print "\n";

# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
##################################################################################################

foreach my $interfacesR (@interfacesR){
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfaces_splitted[3] eq $interfacesR) {
			my $firewallipnet = join ('/',$interfaces_splitted[1],$interfaces_splitted[2]);
			my $firewallipblock = Net::Netmask->new($firewallipnet);
			my $interfacesRlabel = "<". $interfaces_splitted[3] . ">" . " " . $interfaces_splitted[3] . "\\n" . $interfaces_splitted[1] . "/\\" . $firewallipblock->bits() . "|";
			push (@temp3, $interfacesRlabel);
		}
	}
}

print "\"". $hostname_cmd[1],"IFsR\""," [shape=Mrecord, fontsize=11, label=\"",@temp3,"\", style=filled, fillcolor=firebrick]\n";
print "\n";
$#temp3 = -1;

# 6.) Firewall Interface Table Node - Left side
#
##################################################################################################

print "# 6.) Description: record based node for firewall interface tables for the left side\n";
print "# Syntax: FirewallIFsR [shape=Mrecord, label=\"<IF3> IF3\\n10.1.3.1|<IF4> IF4\\n10.1.4.1\", style=filled, fillcolor=firebrick]\n";
print "\n";

foreach my $interfacesL (@interfacesL){
	foreach my $interfaces (@interfaces) {
		my @interfaces_splitted = split (' ',$interfaces);
		if ($interfaces_splitted[3] eq $interfacesL) {
			my $firewallipnet = join ('/',$interfaces_splitted[1],$interfaces_splitted[2]);
			my $firewallipblock = Net::Netmask->new($firewallipnet);
			my $interfacesLlabel = "<" . $interfaces_splitted[3] . ">" . " " . $interfaces_splitted[3] . "\\n" . $interfaces_splitted[1] . "/\\" . $firewallipblock->bits() . "|";
			push (@temp3, $interfacesLlabel);
		}
	}
}

print "\"", $hostname_cmd[1],"IFsL\""," [shape=Mrecord, fontsize=11, label=\"",@temp3,"\", style=filled, fillcolor=firebrick]\n";
print "\n";
$#temp3 = -1;

# 7.) Edges for 'firewall interface on the left side' with direct networks only
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

# 7/A.) 'networks from static route' to routers
# Example: Netz00000 -> Router1010103 [dir=back]
# 
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

foreach my $route_cmd (@route_cmd) {
	my @route_cmd_splitted = split (' ', $route_cmd);
	foreach my $interfacesL (@interfacesL) {
		if ($interfacesL eq $route_cmd_splitted[1]) {
			my @routerip = split ('\.',$route_cmd_splitted[4]); # router ip from route_cmd without points
			my @remotenet = split ('\.', $route_cmd_splitted[2]); # remote network of the firewall
			my $routeripnet = join ('/',$route_cmd_splitted[2],$route_cmd_splitted[3]);
			my $routeripblock = Net::Netmask->new($routeripnet);
			print "Netz",@remotenet,$routeripblock->bits()," -> Router", @routerip,"[dir=back]\n";
		}
	}
}
print "\n";

# 7/B.) Routers to direkt networks for 'interfaces on the left side'
# Example: Router1010103 -> Netz1010101 [dir=back]
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

my @localnet; # local network of the firewall

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
					my @routerip = split ('\.',$route_cmd_splitted[4]); # router ip from route_cmd without points
					print "Router",@routerip," -> ","Netz",@localnet,"[dir=back]\n";
				}
			$routerip1 = $route_cmd_splitted[4];
		}
	}
}

# 7/C.) Edge for: Direct netz to firewall interfaces on the left side
# Example: Netz1010101 -> firewall1IFsL:china [dir=back]
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
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

# 8.) Edges for firewall interface table to firewall
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

# 9.) Edges for 'firewall interface on the right side' with direct networks only
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

# 9/A.) Edges for 'firewall interface on the right side' with direct networks only
# Example: firewall1IFsR:china -> Netz1010101
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
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

# 9/B.) Direkt networks to routers for 'interfaces on the right side'
# Example: Netz1010101 -> Router1010103
#
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
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
					my @routerip = split ('\.',$route_cmd_splitted[4]); # router ip from route_cmd without points
					print "Netz",@localnet, " -> Router", @routerip,"\n";
				}
			$routerip1 = $route_cmd_splitted[4];
		}
	}
}
print "\n";

# 9/C.) Routers to 'networks from static route'
# Example: Router1010103 -> Netz00000
# 
# interfaces array example:
# Port-channel1.251 192.168.250.1 255.255.255.240 sweden 0
# Port-channel1.252 192.168.250.17 255.255.255.240 china 0
#
# route_cmd array example: route austria-hungary 213.33.126.80 255.255.255.240 192.168.250.148 1";
##################################################################################################

foreach my $route_cmd (@route_cmd) {
	my @route_cmd_splitted = split (' ', $route_cmd);
	foreach my $interfacesR (@interfacesR) {
		if ($interfacesR eq $route_cmd_splitted[1]) {
			my @routerip = split ('\.',$route_cmd_splitted[4]); # router ip from route_cmd without points
			my @remotenet = split ('\.', $route_cmd_splitted[2]); # remote network of the firewall
			my $routeripnet = join ('/',$route_cmd_splitted[2],$route_cmd_splitted[3]);
			my $routeripblock = Net::Netmask->new($routeripnet);
			print "Router", @routerip," -> Netz",@remotenet,$routeripblock->bits(),"\n";
		}
	}
}
print "}\n";
close (OUTFILE);
print "#done\n";