#!perl
use strict;
use warnings;
use inc::Module::Install;

name            'camps';
all_from        'lib/Camp.pm';
install_script  'scripts/camp';

requires        'Config::Any'                => 0;
requires        'Config::General'            => 0;
requires        'File::HomeDir'              => 0;
requires        'File::Path'                 => 0;
requires        'File::Spec'                 => 0;
requires        'File::Temp'                 => 0;
requires        'Getopt::Long::Descriptive'  => 0;
requires        'Moose'                      => 0;
requires        'MooseX::SimpleConfig'       => 0;
requires        'MooseX::App::Cmd'           => 0;
requires        'MooseX::SimpleConfig'       => 0;
requires        'MooseX::Storage'            => 0;
requires        'Best'                       => 0;

my $yaml_implementation = get_yaml_implementation();
requires        $yaml_implementation         => 0;

test_requires   'Test::Exception'            => 0;
test_requires   'Test::More'                 => 0;
test_requires   'Test::Pod'                  => '1.22';
test_requires   'Pod::Coverage'              => '0.18';
test_requires   'Test::Pod::Coverage'        => '1.08';

WriteAll;

# Depend on an already installed YAML implementation. If there isn't any YAML
# module installed, require YAML::Syck due to the fact that it's XS if we can't
# find any of the implementations we want.
sub get_yaml_implementation {
    my @implementations = qw(
        YAML::Syck
        YAML
        YAML::XS
    );
    for my $imp ( @implementations ) {
        eval { require $imp; };
        return $imp unless $@;
    }
    return 'YAML::Syck';
}
