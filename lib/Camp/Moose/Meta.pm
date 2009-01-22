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

sub compute_all_persistent_attributes {
    my $self = shift;
    return grep { $_->can('persists') && $_->persists } $self->compute_all_applicable_attributes;
}

1;

