package Point;
use Camp::Moose;
use MooseX::Storage;
use Camp::Moose::Attribute;

with Storage(format => 'YAML');

has 'x' => (
    is => 'rw',
    isa => 'Int',
    metaclass => 'DoNotSerialize'
);

has 'y' => (
    is => 'rw',
    isa => 'Int',
);

no Camp::Moose;

1;
