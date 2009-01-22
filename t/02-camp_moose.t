#!perl -T

use strict;
use warnings;
use Test::More tests => 2;

my $class;

package Foo;
BEGIN {
    $class = 'Camp::Moose';
    Test::More::use_ok($class);
}

has serializable => (
    is      => 'rw',
    persist => 1,
);

has ephemeral => (
    is      => 'rw',
);

package main;

is(
    join('; ', map { $_->name } Foo->meta->compute_all_persistent_attributes),
    'serializable',
    'compute_all_persistent_attributes() and persist setting',
);

# my $obj = Foo->new( serializable => 'save me', ephemeral => 'lose me' );

