package Point;
use Camp::Moose;
use MooseX::Storage;
use Camp::Moose::Attribute;

with Storage(base => 'Camps', format => 'YAML');

has 'x' => (
    is => 'rw',
    isa => 'Int',
    persist => 0,
);

has 'y' => (
    is => 'rw',
    isa => 'Int',
    persist => 1,
);

no Camp::Moose;

1;
