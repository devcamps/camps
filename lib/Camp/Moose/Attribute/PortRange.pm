package Camp::Moose::Attribute::PortRange;

use Camp::Moose;
extends 'Camp::Moose::Attribute';

has base_port => (
    is      => 'rw',
);

has ports_per_camp => (
    is      => 'rw',
    default => 1,
);

has maximum_port => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        return shift->_determine_maximum_port;
    },
);

no Camp::Moose;

sub _determine_maximum_port {
    my $self = shift;
    return;
}

package Moose::Meta::Attribute::Custom::PortRange;
sub register_implementation { 'Camp::Moose::Attribute::PortRange' };

1;

=pod

=head1 NAME

B<Camp::PortRange> -- a class representing a range of ports

=head1 DESCRIPTION

The B<Camp::PortRange> object provides basic resource-oriented port allocation management behavior.
Given a start port number and a number of ports to use per camp, the port range determines the numeric
range of ports necessary to encompass all possible camps within your deployment.

When used as an attribute for a resource class/subclass, the object represents the range.  When used
within an actual camp, the port range can determine the actual ports allocated for that camp.

The camp port allocation is uses a simple algorithm.  Given a camp number I<$n>, a base port I<$b>,
and ports-per-camp I<$p>:

 Camp starting port: $n * $p + $b
 Camp max port: ($n * $p + $b) + $p - 1

Meaning that, for a base port of 9000 and 2 ports per camp:

=over

=item camp 0 gets ports 9000 - 9001

=item camp 1 gets ports 9002 - 9003

=item camp 10 gets ports 9020 - 9021

=back

=head1 ATTRIBUTES

=over

=item B<base_port>

An integer value that specifies the starting port of the range.

=item B<ports_per_camp>

An integer value specifying the number of ports to allocate for each camp.

=item B<maximum_port>

A calculated value that gives the top port in the allocated range.

=back

=head1 AUTHORS

Initial design by Ethan Rowe (ethan at end point dot com)

=cut

