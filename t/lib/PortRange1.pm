package PortRange1;
use Camp::Moose;
use Camp::Moose::Attribute::PortRange;

has port_range => (
    is          => 'rw',
    isa         => 'ArrayRef[Int]',
    metaclass   => 'PortRange',
);

1;
