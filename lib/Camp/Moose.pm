package Camp::Moose;

use strict;
use warnings;

use Moose;
use Camp::Moose::Meta;
use Camp::Moose::Object;

sub import {
    my $CALLER = caller();

    strict->import;
    warnings->import;

    return if $CALLER eq 'main';
    Moose::init_meta( $CALLER, 'Camp::Moose::Object', 'Camp::Moose::Meta' );
    Moose->import({ into => $CALLER });

    return 1;
}

1;

