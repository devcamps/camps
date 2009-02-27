#!perl -T

use strict;
use warnings;
use lib 't/lib';

use Test::More tests => 8;

BEGIN {
    my @classes = qw/Camp::Moose::Attribute::PortRange PortRange1 PortRange2/;
    for my $class ( @classes ) {
        use_ok($class);
    }
}

# should have a base port, numnber of camps, top_port, assigned_ports

my $portrange1 = PortRange1->new;
my $attributes = $portrange1->meta->get_attribute_map; 
ok(defined $attributes->{port_range}, "PortRange1 gets its port_range from Camp::Moose::Attribute::PortRange");
my $port_range = $attributes->{port_range} || die "port_range isn't defined";
isa_ok($port_range, 'Camp::Moose::Attribute::PortRange');
$port_range->base_port(5);
for my $meta ( qw/base_port ports_per_camp maximum_port/ ) {
    # XXX can_ok causes failures here. Find out why.
    ok($port_range->can($meta), "PortRange1's port_range has $meta");
}
