#!perl -T

use strict;
use warnings;

use Test::More tests => 14;
use Test::Exception;
use Best [
    [ qw[YAML::Syck YAML] ],
        [ qw[Load Dump] ]
        ];
use lib 't/lib';

my ($class);
BEGIN {
    my @classes = qw(
        MooseX::Storage::Base::Camps 
        MooseX::Storage::Engine::Camps 
        Point
    );
    for my $class ( @classes ) {
        use_ok($class);
    }
}

# We can load Point correctly which means that everything is set up. Get on with
# real testing.

my $p = Point->new(x => 5, y => 10);
lives_ok { $p->freeze } 'Point can freeze things';
my $p_yaml = $p->freeze;
my $yaml_hash = Load($p_yaml);
is(exists $yaml_hash->{y}, 1, 'Point->y serialized');
is($yaml_hash->{y}, 10, '$p->y serialized properly');
is(!exists $yaml_hash->{x}, 1, '$p->x did not serialize');

# it works manually, now make sure $p->serialize() works
lives_ok { $p->serialize } 'Point can call serialize()';
my $p_serialized = $p->serialize;
is(exists $yaml_hash->{y}, 1, 'Point->y serialized');
is($yaml_hash->{y}, 10, '$p->y serialized properly');
is(!exists $yaml_hash->{x}, 1, '$p->x did not serialize');

lives_ok { Point->thaw($p_serialized) } 'Point can call thaw';
my $o = Point->thaw($p_serialized);
isa_ok($o, 'Point', 'Point->thaw blesses the YAML value properly');
is($o->y, $p->y, 'freeze/thaw roundtrips ->y correctly');
