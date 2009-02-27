package PortRange2;
use Camp::Moose;

has_port_range port => (
    base_port       => 8900,
    ports_per_camp  => 5,
);

1;
