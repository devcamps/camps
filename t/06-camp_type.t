#!perl -T

use strict;
use warnings;

use Test::More tests => 1;
my ($class, $type);
BEGIN {
    $class = 'Camp::Type';
    use_ok($class);
}

