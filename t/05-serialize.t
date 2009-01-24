#!perl -T

use strict;
use warnings;

use Test::More tests => 7;
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
lives_ok { $p->freeze } "Point can freeze things";
my $p_yaml = $p->freeze;
my $yaml_hash = Load($p_yaml);
is(exists $yaml_hash->{y}, 1, "Point->y serialized");
is($yaml_hash->{y}, 10, '$p->y serialized properly');
is(!exists $yaml_hash->{x}, 1, '$p->x did not serialize');


#my $dir = File::Temp->newdir;
#my $deploy_path = File::Spec->rel2abs(
#    File::Spec->catfile(
#        $dir->dirname,
#        'camps'
#    )
#);
#
#BAIL_OUT("Test deployment path $deploy_path should not exist, yet it does!")
#    if -d $deploy_path;
#
#$deployment = $class->new( path => $deploy_path );
#
#is(
#    $deployment->path,
#    $deploy_path,
#    'path() post-constructor',
#);
#
#is(
#    $deployment->resource_path,
#    File::Spec->catfile( $deploy_path, 'resources' ),
#    'resource_path() default',
#);
#
#is(
#    $deployment->types_path,
#    File::Spec->catfile( $deploy_path, 'types' ),
#    'types_path() default',
#);
#
#is(
#    $deployment->config_path,
#    File::Spec->catfile( $deploy_path, 'camps_deployment.yaml' ),
#    'config_path() default',
#);
#
#$deployment->initialize;
#
#ok(
#    -d $_->[1],
#    "$_->[0]() exists post-initialize"
#) for map {
#    my $sub = $deployment->can($_);
#    [ $_, $deployment->$sub ];
#}
#qw(
#    path
#    resource_path
#    types_path
#);
#
#my %path = map {
#        $_ => File::Spec->catfile( $dir->dirname, $_ );
#    }
#    qw(
#        path
#        resource_path
#        types_path
#    );
#
#for my $path_name (qw( path resource_path types_path )) {
#    $deployment = $class->new( %path );
#    mkdir( $path{$path_name} );
#    dies_ok(
#        sub { $deployment->initialize },
#        "initialize() dies if $path_name() already exists",
#    );
#}
