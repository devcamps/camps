#!perl -T

use strict;
use warnings;
use lib 't/lib';

use Test::More tests => 12;

BEGIN {
    my @classes = qw/Camp::Moose::Attribute::PortRange PortRange1 PortRange2/;
    for my $class ( @classes ) {
        use_ok($class);
    }
}

# should have a base port, number of camps, top_port, assigned_ports

my $portrange1 = PortRange1->new;
my $attributes = $portrange1->meta->get_attribute_map; 
ok(defined $attributes->{port_range}, "PortRange1 gets its port_range from Camp::Moose::Attribute::PortRange");
my $port_range = $attributes->{port_range};
isa_ok($port_range, 'Camp::Moose::Attribute::PortRange');
$port_range->base_port(5);
for my $meta ( qw/base_port ports_per_camp maximum_port/ ) {
    # XXX can_ok causes failures here. Find out why.
    ok($port_range->can($meta), "PortRange1's port_range has $meta");
}

# now, test the sugar that's used in PortRange2. these are tested separately so
# Camp::Moose::Attribute::PortRange is tested before
# Camp::Moose::has_port_range. this way Camp::Moose::has_port_range's
# dependency on C::M::A::PR is tested first, so failures in the latter are
# easier to spot.
my $portrange2 = PortRange2->new;
$attributes = $portrange2->meta->get_attribute_map;
ok(defined $attributes->{port}, 'PortRange2 gets its port from Camp::Moose::has_port_range');
my $port = $attributes->{port};
isa_ok($port, 'Camp::Moose::Attribute::PortRange');
is($port->base_port, 8900, 'PortRange2 base_port initialized correctly');
is($port->ports_per_camp, 5, 'PortRange2 ports_per_camp initialized correctly');

# we don't need to test anything further than this, as we've already made sure
# that C::M::A::PR works at this point. 
