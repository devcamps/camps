#!perl -T

use strict;
use warnings;
use Test::More tests => 1;

my $class;

package Foo;
BEGIN {
    $class = 'Camp::Moose';
    Test::More::use_ok($class);
}

has serializable => (
    is      => 'rw',
);

has ephemeral => (
    is      => 'rw',
    metaclass => 'DoNotSerialize',
);

package main;

# with persist gone, not sure how to test this without actually testing
# MooseX::Storage.

# my $obj = Foo->new( serializable => 'save me', ephemeral => 'lose me' );
