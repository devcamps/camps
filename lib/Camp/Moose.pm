package Camp::Moose;

use strict;
use warnings;

use Moose;
use Moose::Exporter;
use Camp::Moose::Meta;
use Camp::Moose::Object;

Moose::Exporter->setup_import_methods(
    as_is   => [ \&has_port_range ],
    also    => 'Moose',
);

Moose->init_meta( for_class => caller(), base_class => 'Camp::Moose::Object', metaclass => 'Camp::Moose::Meta' );

sub has_port_range {
}

1;
