#!perl -T

use strict;
use warnings;

use Test::More tests => 6;

my ($class, $port_range);
BEGIN {
    $class = 'Camp::PortRange';
    use_ok($class);
}

# should have a base port, numnber of camps, top_port, assigned_ports
$port_range = $class->new;

ok(
    !defined($port_range->base_port),
    'base_port() defaults to undefined',
);

is(
    $port_range->ports_per_camp,
    1,
    'ports_per_camp() defaults to 1',
);

ok(
    !defined($port_range->maximum_port),
    'maximum_port() undefined by default (with base_port() undefined',
);

is(
    $port_range->base_port(8000),
    8000,
    'base_port() setter passthrough',
);

is(
    $port_range->base_port,
    8000,
    'base_port() get',
);


