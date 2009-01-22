#!perl -T

use strict;
use warnings;
use Test::More tests => 1;

my ($class, $result);
BEGIN {
    $class = 'Camp::Resource';
    use_ok($class);
}

