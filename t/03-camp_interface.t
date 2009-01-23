#!perl -T

use strict;
use warnings;
use Test::More tests => 1;

my $class;

BEGIN {
    $class = 'Camp::Interface';
    use_ok($class);
}


