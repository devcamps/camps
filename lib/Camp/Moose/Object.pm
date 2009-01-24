package Camp::Moose::Object;

use base qw(Moose::Object);
use Moose;
use MooseX::Storage;
use Camp::Moose::Attribute;

with Storage(base => 'Camps', format => 'YAML');

sub serialize {
    my ($self) = @_;
    $self->freeze;
}

1;

