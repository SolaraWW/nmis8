#
#  Copyright Opmantek Limited (www.opmantek.com)
#
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#
#  This file is part of Network Management Information System ("NMIS").
#
#  NMIS is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  NMIS is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with NMIS (most likely in a file named LICENSE).
#  If not, see <http://www.gnu.org/licenses/>
#
#  For further information on NMIS or for a license other than GPL please see
#  www.opmantek.com or email contact@opmantek.com
#
#  User group details:
#  http://support.opmantek.com/users/
#
# *****************************************************************************
#
# a small update plugin for converting the lldp index into interface name.

package lldpTable;
our $VERSION = "1.1.0";

use strict;

use func; # required for logMsg

use NMIS;


sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $IFD = $S->ifDescrInfo(); # interface info indexed by ifDescr

	return (0,undef) if (ref($NI->{lldp}) ne "HASH");
	my $changesweremade = 0;

	info("LLDP plugin update-phase Working on $node LLDP Table");

	my $LNT = loadLocalNodeTable();

	for my $key (keys %{$NI->{lldp}})
	{
		my $entry = $NI->{lldp}{$key};
		my @parts;

		# make the addresses pretty if they are 0xABCDE
		if ( $entry->{lldpRemPortIdSubtype} eq "macAddress" and $entry->{lldpRemPortId} =~ /^0x/ ) {
			$entry->{lldpRemPortId} = beautify_physaddress($entry->{lldpRemPortId});
		}
		elsif ( $entry->{lldpRemPortIdSubtype} eq "interfaceName" and $entry->{lldpRemPortId} =~ /^0x/ ) {
			$entry->{lldpRemPortId} = join( '', map { sprintf "%x", $_ } unpack( 'C*', $entry->{lldpRemPortId} ) );
		}

		if ( $entry->{lldpRemChassisIdSubtype} eq "macAddress" and $entry->{lldpRemChassisId} =~ /^0x/ ) {
			$entry->{lldpRemChassisId} = beautify_physaddress($entry->{lldpRemChassisId});
		}
		elsif ( $entry->{lldpRemChassisIdSubtype} eq "networkAddress" and $entry->{lldpRemChassisId} =~ /^0x/ ) {
			$entry->{lldpRemChassisId} = join( '.', unpack( 'C4', $entry->{lldpRemChassisId}));
		}

		# deal with remote neighbours
		my $lldpNeighbour = $entry->{lldpRemSysName};

		my @possibleNames;
		push(@possibleNames,$lldpNeighbour);
		push(@possibleNames,lc($lldpNeighbour));
		#may need some other munging for other optional naming schemes here e.g. FQDN
		# IOS with LLDP returns complete FQDN so is required
		if ( $lldpNeighbour =~ /\./ ) {
			my @fqdn = split(/\./,$lldpNeighbour);
			push(@possibleNames,$fqdn[0]);
			push(@possibleNames,lc($fqdn[0]));
		}

		$changesweremade = 1;

		my $possNeighbour;
		my $gotNeighbourName = 0;		

		foreach $possNeighbour (@possibleNames) {
			if ( defined $LNT->{$possNeighbour} and defined $LNT->{$possNeighbour}{name} and $LNT->{$possNeighbour}{name} eq $possNeighbour ) {
				dbg("$lldpNeighbour found as $possNeighbour in LNT for $node");
				$changesweremade = 1;
				$entry->{lldpRemSysName_raw} = $entry->{lldpRemSysName};
				$entry->{lldpRemSysName} = $possNeighbour;
				$entry->{lldpRemSysName_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_node_view&node=$possNeighbour";
				$entry->{lldpNeighbour_id} = "node_view_$possNeighbour";
				last;
			}
		}

		# did I get one, if not, look harder be a brute!
		if ( not $gotNeighbourName ) {
			foreach my $possNeighbour (@possibleNames) {
				foreach my $aNode (keys %{$LNT}) {
					if ( $possNeighbour eq $LNT->{$aNode}{host} ) {
						# but the neighbour is actually the name from the LNT
						$changesweremade = 1;
						$entry->{lldpRemSysName_raw} = $entry->{cdpCacheDeviceId};
						$entry->{lldpRemSysName} = $aNode;
						$entry->{lldpRemSysName_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_node_view&node=$aNode";
						$entry->{lldpNeighbour_id} = "node_view_$aNode";
						$gotNeighbourName = 1;
						last;						
					}
				}
			}
		}

		if ( @parts = split(/\./,$entry->{index}) ) {

			if ( @parts == 3 ) {
				$entry->{unused} = shift(@parts);
				$entry->{lldpLocPortNum} = shift(@parts);
				$entry->{lldpDeviceIndex} = shift(@parts);				
			}
			elsif ( @parts == 4 ) {
				$entry->{unused} = shift(@parts);
				$entry->{lldpLocPortNum} = shift(@parts);
				$entry->{unused} = shift(@parts);
				$entry->{lldpDeviceIndex} = shift(@parts);				
			}

			# is the lldpLocPortNum actually the ifIndex?  easy.
			if ( defined $IF->{$entry->{lldpLocPortNum}}{ifDescr} ) {
				dbg("Found a ifDescr entry for lldpLocPortNum=$entry->{lldpLocPortNum}: $IF->{$entry->{lldpLocPortNum}}{ifDescr}");
				$entry->{ifDescr} = $IF->{$entry->{lldpLocPortNum}}{ifDescr};
				$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$entry->{lldpLocPortNum}&node=$node";
				$entry->{ifDescr_id} = "node_view_$node";
			}
			else {
				# nope it is some obscure double look up.
				# so did I find an interface in the lldpLocPortDesc lldpLocPortId data?
				my @lldpLocalThing = qw(lldpLocPortDesc lldpLocPortId);
				foreach my $lldpLocalInt (@lldpLocalThing) {
					if ( defined $NI->{lldpLocal} and defined $NI->{lldpLocal}{$entry->{lldpLocPortNum}} ) {
						# yes, so get a local portnum and get the ifDescr, then get the ifIndex using the reverse index.
						dbg("Found a lldpLocal entry for lldpLocPortNum=$entry->{lldpLocPortNum}");
						my $lldpLocPortNum = $entry->{lldpLocPortNum};
						my $ifDescr = $NI->{lldpLocal}{$lldpLocPortNum}{$lldpLocalInt};
						if ( defined $IFD->{$ifDescr}{ifIndex} ) {
							$entry->{lldpIfIndex} = $IFD->{$ifDescr}{ifIndex};	
						}
						else {
							dbg("No lldpIfIndex found from lldpLocal entry for lldpLocalInt=$lldpLocalInt ifDescr=$ifDescr");
						}
						
					}

					if ( defined $IF->{$entry->{lldpIfIndex}}{ifDescr} ) {
						dbg("Found a ifDescr entry for lldpIfIndex=$entry->{lldpIfIndex}: $IF->{$entry->{lldpIfIndex}}{ifDescr}");
						$entry->{ifDescr} = $IF->{$entry->{lldpIfIndex}}{ifDescr};
						$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$entry->{lldpIfIndex}&node=$node";
						$entry->{ifDescr_id} = "node_view_$node";
						# exit the foreach loop
						last;
					}
				}				
			}
		}
	}

	return ($changesweremade,undef); # report if we changed anything
}	

sub munge_mac {
    my $mac = shift;
    return unless defined $mac;
    return unless length $mac;
    $mac = join( ':', map { sprintf "%02x", $_ } unpack( 'C*', $mac ) );
    return $mac if $mac =~ /^([0-9A-F][0-9A-F]:){5}[0-9A-F][0-9A-F]$/i;
    return;
}

1;
