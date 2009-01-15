use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Camp',
    license             => 'perl',
    dist_author         => 'End Point Corp. <camps@endpoint.com>',
    dist_version_from   => 'lib/Camp.pm',
    build_requires => {
        # TODO: specify minimum versions
        'Test::More'                => 0,
        'Getopt::Long::Descriptive' => 0,
        'Moose'                     => 0,
        'MooseX::App::Cmd'          => 0,
        'MooseX::SimpleConfig'      => 0,
        'File::HomeDir'             => 0,
        'Config::Any'               => 0,
        'Config::General'           => 0, # this is probably just optional
    },
    script_files        => [
        'scripts/camp',
    ],
    add_to_cleanup      => [ 'camps-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
