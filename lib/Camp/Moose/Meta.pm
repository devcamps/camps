package Camp::Moose::Meta;

use strict;
use warnings;

use Camp::Moose::Attribute;
use base qw(Moose::Meta::Class);

sub initialize {
    my $self = shift;
    my $pkg = shift;
    return $self->SUPER::initialize(
        $pkg,
        attribute_metaclass => 'Camp::Moose::Attribute',
        @_,
    );
}

1;

