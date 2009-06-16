#!/usr/local/bin/perl

use strict;
use warnings;
use Test::More (tests => 148,);
use User::pwent ();
use Cwd ();
use File::Spec;

my ($class, $path, $local_lib);
BEGIN {
    $class = 'Camp::Config';
    $path = __FILE__;
    $path =~ s/\.t$//;
    # Untaint this path for SETUID security concerns.
    ($local_lib) = Cwd::abs_path( File::Spec->catfile( $path, '../../..' ) ) =~ /^(.*)/;
}
use lib $local_lib;

my $pw = User::pwent::getpwnam('interch');
BAIL_OUT('No "interch" user available on this machine; cannot run tests.')
    unless defined $pw
    and $pw->uid
;

my ($ic_uid, $orig_euid) = ($pw->uid, $>);

BAIL_OUT('Tests must be run as root; you may need to chmod this script to SETUID.')
    unless $orig_euid == 0
;

$> = $ic_uid;
BAIL_OUT('Unable to switch to "interch" user; cannot run tests.')
    unless $> == $ic_uid
;

delete $ENV{CAMP};

my @production_catalogs = qw(
    bcs
    corporate
    dogfunk
    explore64
    manager
    outlet
    steepcheap
    tramdock
    wm
);

my %db_catalog_map = qw(
    manager bcs
);

my %backside_only_catalogs = map { $_ => 1 } qw(
    manager
);

SKIP: {
    # Basic tests and production-specific tests...
    skip(
        'Could not use library; possible environment configuration errors!',
        4       # tests in validate_vars...
        + scalar(@production_catalogs)
        + 6     # tests in validate_daemon_settings...
        + 26    # tests in validate_configuration_possibilities...
        + 10    # tests in this block
    )
        unless use_ok($class, qw(use_libs 1))
    ;
	diag("Using $class from $INC{'Camp/Config.pm'}");
    cmp_ok(
        $INC[0],
        'eq',
        '/usr/lib/interchange/custom/lib',
        'Custom interchange library first in search path',
    );

    cmp_ok(
        $INC[1],
        'eq',
        '/usr/lib/interchange/lib',
        'Base interchange library second in search path',
    );

    cmp_ok(
        $class->base_path,
        'eq',
        '/var/lib/interchange',
        'base_path()',
    );

    cmp_ok(
        $class->ic_path,
        'eq',
        '/usr/lib/interchange',
        'ic_path()',
    );

    cmp_ok(
        $class->user && $class->user->name,
        'eq',
        'interch',
        'user()',
    );

    ok(
        ! $class->per_user_file_layout,
        'per_user_file_layout() false',
    );

    ok(
        !defined($class->camp_number),
        'camp_number() undefined',
    );

    validate_daemon_settings();

    is_deeply(
        [ grep { $class->backside or !$backside_only_catalogs{$_} } $class->known_catalogs ],
        [ grep { $class->backside or !$backside_only_catalogs{$_} } @production_catalogs ],
        'known_catalogs()',
    );

    ok( !defined($class->catalog), 'catalog() undefined' );
    $Vend::Cfg->{CatalogName} = $production_catalogs[0];
    cmp_ok(
        $class->catalog,
        'eq',
        $production_catalogs[0],
        'catalog() set',
    );

    delete $Vend::Cfg->{CatalogName};
    validate_vars();

    validate_configuration_possibilities('system-wide layout',);
}

# let's find a camp that has all the catalogs we need... '
my (@camps, $owner, $number, $ok, $camp_user, $list_err);
eval { @camps = $class->camp_list; };
$list_err = 1
    if $@
        and !@camps
;
for my $camp_data (@camps) {
    ($owner, $number) = @$camp_data{qw(username camp_number)};
    $camp_user = User::pwent::getpwnam( $owner ) or next;
    next if $camp_user->uid == $ic_uid;
    $> = $orig_euid;
    $> = $camp_user->uid;
    next if $> != $camp_user->uid;
    reset_package();
    $ENV{CAMP} = $number;
    local $SIG{__WARN__} = sub { return; };
    eval "use $class qw(use_libs 1);";
    last if $ok = (
        !$@
        and (
            join("\n", @production_catalogs)
            eq
            join("\n", $class->known_catalogs)
        )
    );
}

SKIP: {
    my $test_count
        = scalar(@production_catalogs) # one SQLUSER check per camp in validate_vars()
        + 4     # other checks in validate_vars()
        + 6     # checks in validate_daemon_settings()
        + 26    # checks in validate_configuration_possibilities()
        + 47    # checks local to this block
    ;

    skip(
        "unable to retrieve camp list: $@",
        $test_count,
    ) if $list_err;

    skip(
        'Cannot find a camp with all production catalogs and proper environment configuration!',
        $test_count,
    )
        unless $ok
    ;

    ok(
        $class->per_user_file_layout,
        'per_user_file_layout() true',
    );

    cmp_ok(
        $class->camp_number,
        '==',
        $number,
        'camp_number() per-user layout'
    );

    cmp_ok(
        $class->user && $class->user->name,
        'eq',
        $owner,
        'user() per-user layout',
    );

    cmp_ok(
        $INC[0],
        'eq',
        File::Spec->catfile($camp_user->dir, "camp$number", 'interchange/custom/lib'),
        'camp interchange custom lib path first in search path',
    );

    cmp_ok(
        $INC[1],
        'eq',
        File::Spec->catfile($camp_user->dir, "camp$number", 'interchange/lib'),
        'camp interchange base lib path second in search path',
    );

    cmp_ok(
        $class->base_path,
        'eq',
        File::Spec->catfile($camp_user->dir, "camp$number",),
        'base_path() camp',
    );

    cmp_ok(
        $class->ic_path,
        'eq',
        File::Spec->catfile($camp_user->dir, "camp$number", 'interchange',),
        'ic_path() camp',
    );

    validate_daemon_settings();

    validate_vars();

    validate_configuration_possibilities('per-user layout');

    # Verify proper parsing of things.
    $class->_parse_file(undef, File::Spec->catfile( $path, 'global.cfg' ),);
    my $catalog = $production_catalogs[0];
    $class->_parse_file($catalog, File::Spec->catfile( $path, 'local.cfg' ),);
    cmp_ok(
        $class->variable(undef, 'WHITESPACE_TRIM'),
        'eq',
        'CHOMP',
        'global variable whitespace trimmed',
    );
    cmp_ok(
        $class->variable($catalog, 'WHITESPACE_TRIM'),
        'eq',
        'CHOMP',
        'catalog variable whitespace trimeed',
    );
    cmp_ok(
        $class->variable(undef, 'FANCIER_WHITESPACE',),
        'eq',
        'This has some whitespace!',
        'global variable fancier whitespace handling',
    );
    cmp_ok(
        $class->variable($catalog, 'FANCIER_WHITESPACE',),
        'eq',
        'This has some whitespace!',
        'local variable fancier whitespace handling',
    );
    cmp_ok(
        $class->variable(undef, 'NO_PARSE'),
        'eq',
        '@@IDENTITY@@',
        'global variable parsing: off (top scope)',
    );

# 2007-05-24 Ethan
# The following 8 tests of global variable substitution have been deprecated for
# the time being, as IC does not provide global-level variable substitution, only
# catalog level; keep the tests, though, in case we want this to change, since the
# module supports it except for a single statement that generates an error when attempting
# to turn ParseVariables on in the global level.
#
#    cmp_ok(
#        $class->variable(undef, 'WITH_PARSE'),
#        'eq',
#        'global',
#        'global variable parsing: on (top scope)',
#    );
#    cmp_ok(
#        $class->variable(undef, 'NESTED_NO_PARSE1'),
#        'eq',
#        '@@IDENTITY@@',
#        'global variable parsing: off (nested scope)',
#    );
#    cmp_ok(
#        $class->variable(undef, 'NESTED_PARSE'),
#        'eq',
#        'global',
#        'global variable parsing: on (double-nested scope)',
#    );
#    cmp_ok(
#        $class->variable(undef, 'NESTED_NO_PARSE2',),
#        'eq',
#        '@@IDENTITY@@',
#        'global variable parsing: off (nested scope resumed)',
#    );
#    cmp_ok(
#        $class->variable(undef, 'WITH_PARSE2',),
#        'eq',
#        'global',
#        'global variable parsing: on (top scope resumed)',
#    );
#    cmp_ok(
#        $class->variable(undef, 'FROM_GLOBAL',),
#        'eq',
#        'global',
#        'global variable parsing: global token recognized',
#    );
#    cmp_ok(
#        $class->variable(undef, 'FROM_EITHER',),
#        'eq',
#        'global',
#        'global variable parsing: flex token recognized',
#    );
#    cmp_ok(
#        $class->variable(undef, 'FROM_LOCAL',),
#        'eq',
#        '__IDENTITY__',
#        'global variable parsing: local token unrecognized',
#    );
    cmp_ok(
        $class->variable(undef, 'HERE_NOPARSE_CHECK'),
        'eq',
        'outside',
        'here doc content ignored for directives',
    );
    cmp_ok(
        $class->variable(undef, 'HERE_CHECK'),
        'eq',
        'inside the here doc',
        'here doc content properly read'
    );
    cmp_ok(
        $class->variable($catalog, 'NO_PARSE',),
        'eq',
        '__IDENTITY__',
        'local variable parsing: off (top scope)',
    );
    cmp_ok(
        $class->variable($catalog, 'WITH_PARSE',),
        'eq',
        'local',
        'local variable parsing: on (top scope)',
    );
    cmp_ok(
        $class->variable($catalog, 'NESTED_NO_PARSE1',),
        'eq',
        '__IDENTITY__',
        'local variable parsing: off (nested scope)',
    );
    cmp_ok(
        $class->variable($catalog, 'NESTED_PARSE',),
        'eq',
        'local',
        'local variable parsing: on (double-nested scope)',
    );
    cmp_ok(
        $class->variable($catalog, 'NESTED_NO_PARSE2',),
        'eq',
        '__IDENTITY__',
        'local variable parsing: off (nested scope resumed)',
    );
    cmp_ok(
        $class->variable($catalog, 'WITH_PARSE2',),
        'eq',
        'local',
        'local variable parsing: on (top scope resumed)',
    );
    cmp_ok(
        $class->variable($catalog, 'FROM_GLOBAL',),
        'eq',
        'global',
        'local variable parsing: global token recognized',
    );
    cmp_ok(
        $class->variable($catalog, 'FROM_EITHER',),
        'eq',
        'local',
        'local variable parsing: flex token recognized',
    );
    cmp_ok(
        $class->variable($catalog, 'FROM_LOCAL',),
        'eq',
        'local',
        'local variable parsing: local token recognized',
    );
    cmp_ok(
        $class->smart_variable('GLOBAL_ONLY'),
        'eq',
        'global',
        'smart_variable: global var, no default catalog',
    );
    cmp_ok(
        $class->smart_variable('IDENTITY',),
        'eq',
        'global',
        'smart_variable: global/local var, no default catalog',
    );
    cmp_ok(
        $class->smart_variable('IDENTITY', $catalog,),
        'eq',
        'local',
        'smart_variable: local var, explicit catalog',
    );
    cmp_ok(
        $class->smart_variable('GLOBAL_ONLY', $catalog,),
        'eq',
        'global',
        'smart_variable: global var, explicit catalog',
    );
    $Vend::Cfg->{CatalogName} = $catalog;
    cmp_ok(
        $class->smart_variable('IDENTITY',),
        'eq',
        'local',
        'smart_variable: local var, default catalog',
    );
    cmp_ok(
        $class->smart_variable('GLOBAL_ONLY',),
        'eq',
        'global',
        'smart_variable: global var, default catalog',
    );

    eval {
        $class->_parse_file(
            undef,
            File::Spec->catfile( $path, 'global_parsevariables.cfg' ),
        );
    };
    ok($@, 'global config file throws exception upon ParseVariables directive');

    eval {
        $class->_parse_file(
            undef,
            File::Spec->catfile( $path, 'global_bad_heredoc.cfg' ),
        );
    };
    ok($@, 'unterminated heredoc throws exception');

    my $ifdef_file = File::Spec->catfile( $path, 'ifdef.cfg' );
    $class->_parse_file( undef, File::Spec->catfile( $path, 'global_identity.cfg' ));
    $class->_parse_file( undef, $ifdef_file );
    $class->_parse_file( $catalog, File::Spec->catfile( $path, 'catalog_identity.cfg' ));
    $class->_parse_file( $catalog, $ifdef_file );
    for my $level (undef, $catalog) {
        my $suff = $level ? '-- catalog' : '-- global';
        ok(
            $class->variable( $level, 'SIMPLE_IFDEF' ),
            "#ifdef simple $suff",
        );
        ok(
            $class->variable( $level, 'SIMPLE_IFNDEF' ),
            "#ifndef simple $suff",
        );
        ok(
            $class->variable( $level, 'EXPR_IFDEF_TRUE' ),
            "#ifdef with evaled expression $suff",
        );
        is(
            $class->variable( $level, 'LOCATION'),
            $level ? 'catalog' : 'global',
            "#ifdef reads variables from correct space $suff",
        );
        ok(
            $class->variable( $level, 'GLOBAL_CHECK' ),
            "#ifdef global token $suff",
        );
    }

    eval {
        $class->_parse_file( undef, File::Spec->catfile($path, 'ifdef_nested.cfg') );
    };
    ok( $@, 'nested #ifdef throws exception' );

    eval {
        $class->_parse_file( undef, File::Spec->catfile($path, 'ifdef_unterminated.cfg') );
    };
    ok( $@, 'unterminated #ifdef throws exception' );

    my $newname = 'bogus';
    my $c;
    while ($c++ < 1000 and $class->known_catalogs($newname)) {
        $newname .= 's';
    }
    skip('cannot register test catalog to verify include directive', 4)
        if $class->known_catalogs($newname)
    ;
    $class->register_catalog( $newname, $path );
    # This script is setuid root, so we have to untaint this (hence the regex)
    my ($current_path) = Cwd::getcwd() =~ /^(.*)/;
    eval {
        chdir $path;
        $class->_parse_file(
            $newname,
            File::Spec->rel2abs(
                File::Spec->catfile($path, 'include_outer.cfg'),
                $current_path,
            ),
        );
    };
    if ($@) {
        diag("Error during include parsing: $@");
    }
    chdir $current_path;
    is(
        $class->variable( $newname, 'INCLUDE_TEST' ),
        'inner',
        'include directive: basic include',
    );
    is_deeply(
        [ map { $class->variable($newname, "GLOB_INCLUDE_$_") && 1 } qw(A B C) ],
        [ 1, 1, 1 ],
        'include directive: glob include',
    );

    skip('same user; no check for incorrect user', 2)
        if $> == $orig_euid
    ;

    local $SIG{__WARN__} = sub { return; };
    reset_package();
    $> = $orig_euid;
    ok(!eval("use $class (use_libs => 1);"), 'Exception thrown for incorrect user',);

    skip('ran as interch; cannot do no-environment exception check', 1)
        if $> == $ic_uid
    ;
    $> = $camp_user->uid;
    reset_package();
    delete $ENV{CAMP};
    ok(!eval("use $class (use_libs => 1);"), 'Exception thrown for unprepared environment',);
}

sub reset_package {
    delete $INC{'Camp/Config.pm'};
    return;
}

sub validate_vars {
    ok(
        !defined($class->variable( undef, 'SQLUSER', )),
        'variable() SQLUSER global',
    );

    for my $cat (@production_catalogs) {
        if ($class->frontside and $backside_only_catalogs{$cat}) {
            ok(1, "Catalog $cat is not used in frontside role",);
        }
        else {
            cmp_ok(
                eval { $class->variable( $cat, 'SQLUSER', ) },
                'eq',
                $db_catalog_map{$cat} ? "$db_catalog_map{$cat}" : "${cat}_readonly",
                'variable() SQLUSER catalog ' . $cat,
            );
        }
    }


    my %global_vars = eval { $class->variable( undef ) };
    my %cat_vars = eval { $class->variable( 'bcs' ) };
    ok( %global_vars, 'variable() list context global', );
    ok( %cat_vars, 'variable() list context catalog bcs', );
    cmp_ok(
        join("\n", map { "$_=" . ( defined $global_vars{$_} ? $global_vars{$_} : '' ) } sort {$a cmp $b} keys %global_vars),
        'ne',
        join("\n", map { "$_=" . ( defined $cat_vars{$_} ? $cat_vars{$_} : '' ) } sort {$a cmp $b} keys %cat_vars),
        'variable() global/catalog independence',
    );
    return;
}

sub validate_daemon_settings {
    ok(
        (defined( $class->application_role ) and length( $class->application_role )),
        'application_role() set',
    );

    cmp_ok(
        $class->application_role,
        'eq',
        (($class->frontside && 'frontside') or ($class->backside && 'backside') or undef),
        'frontside()/backside() application role',
    );

    ok(
        ($class->frontside xor $class->backside),
        'frontside()/backside() logical compliment',
    );

    ok(
        ( defined( $class->run_environment ) and length( $class->run_environment ) ),
        'run_environment() set',
    );

    ok(
        (
            $class->qa
            xor $class->staging
            xor $class->production
            xor $class->camp
        ),
        'qa()/staging()/production()/camp() mutual exclusion',
    );

    cmp_ok(
        $class->run_environment,
        'eq',
        (
            $class->qa && 'qa'
            or $class->staging && 'staging'
            or $class->production && 'production'
            or $class->camp && 'camp'
            or undef
        ),
        'run_environment() consistent with boolean convenience methods',
    );
    return;
}

# This does twenty-six tests.
sub validate_configuration_possibilities {
    my $test_prefix = shift;
    $test_prefix = '' if ! defined $test_prefix;
    $test_prefix .= ': ' if $test_prefix =~ /\S/;
    my @roles = qw( frontside backside );
    my @envs = qw( camp production qa staging );
    for my $test_spec (
        {
            method => 'application_role',
            possibilities => \@roles,
            file_prefix => 'role_',
        },
        {
            method => 'run_environment',
            possibilities => \@envs,
            file_prefix => 'run_',
        },
    ) {
        my $method = $class->can( $test_spec->{method} );
        my $original = $class->$method();
        my @run_order = grep { $_ ne $original } @{$test_spec->{possibilities}};
        push @run_order, $original if $original;
        for my $test (@run_order) {
            $class->_parse_file(
                undef,
                File::Spec->catfile( $path, "$test_spec->{file_prefix}$test.cfg", ),
            );
            cmp_ok(
                $class->$method(),
                'eq',
                $test,
                $test_prefix . $test_spec->{method} . "() valid ($test mode)",
            );
            for my $check (@{ $test_spec->{possibilities} }) {
                my $sub = $class->can( $check );
                cmp_ok(
                    ($class->$sub() && 1) || 0,
                    '==',
                    ($check eq $test ? 1 : 0),
                    $test_prefix . $check . "() valid ($test mode)"
                );
            }
        }

    }
}

