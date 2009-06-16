#!/usr/local/bin/perl

use lib '/home/camp/lib';
use Test::More (tests => 105);
use Cwd ();
use File::Temp ();
use File::pushd;
use File::Spec;
use Scalar::Util qw(blessed);

my ($class, $subclass, $test_dir, $test_lib);
BEGIN {
    $class = 'Camp::Config';
    $subclass = 'TestApp::Config';
#printf STDERR "File is %s\n", __FILE__;
    if ( File::Spec->rel2abs(__FILE__) =~ m{^(.+?)\.t$} ) {
#printf STDERR "Path '%s' matches; test dir is: %s\n", __FILE__, $1;
        $test_dir = $1;
    }
    die "Failed to determine test include/lib directory!\n"
        unless defined $test_dir
    ;
    $test_lib = $test_dir . '/lib';
}
use lib $test_lib;
use_ok( $class, (no_init => 1) );
use_ok( $subclass, (no_init => 1) );

diag("Validate the private, core methods of $class");

isa_ok( $class->new, $class );
isa_ok( $subclass->new, $subclass );

{
    my @objects = (
        [ $class->_resolve_invocant, 'base class', $class ],
        [ $subclass->_resolve_invocant, 'subclass', $subclass ],
        [ $class->new->_resolve_invocant, 'base class instance', $class ],
        [ $subclass->new->_resolve_invocant, 'subclass instance', $subclass ],
    );

    my %seen;
    for my $set (@objects) {
        my ($obj, $target, $isa_type) = @$set;
        ok( blessed($obj) eq $isa_type, "_resolve_invocant() for $target" );
        $seen{ $obj + 0 }++;
    }

    ok(
        scalar( keys(%seen) ) == @objects,
        '_resolve_invocant() results in unique blessed references'
    );

    ok(
        $class->_resolve_invocant() == $class->_resolve_invocant(),
        '_resolve_invocant() returns consistent singleton object per class'
    );
}

# Use this loop to validate the basic functions of each object and to validate
# that object state is properly encapsulated for standard objects and package
# singletons

for my $test_set (
    [ $class->new, $class->new, 'basic objects' ],
    [ $class, $subclass, 'package singletons' ],
) {
    my ($obj_a, $obj_b, $test) = @$test_set;

    # setting set/get sanity/encapsulation
    $obj_a->_setting_set('foo', 'a');
    $obj_b->_setting_set('foo', 'b');
    is( $obj_a->_setting_get('foo'), 'a', "_setting_(set|get) 1 ($test)" );
    is( $obj_b->_setting_get('foo'), 'b', "_setting_(set|get) 2 ($test)" );

    # catalog registration sanity/encapsulation
    ok(!($obj_a->known_catalogs('foo')), "unknown catalog 1 ($test)");
    ok(!($obj_b->known_catalogs('foo')), "unknown catalog 2 ($test)");
    $obj_a->register_catalog( 'foo', '/foo/a' );
    $obj_b->register_catalog( 'foo', '/foo/b' );
    ok( $obj_a->known_catalogs('foo'), "known catalog 1 ($test)");
    ok( $obj_b->known_catalogs('foo'), "known catalog 2 ($test)");
    is( scalar($obj_a->catalog_path('foo')), '/foo/a', "catalog_path() 1 ($test)" );
    is( scalar($obj_b->catalog_path('foo')), '/foo/b', "catalog_path() 2 ($test)" );

    # variable sanity/encapsulation
    $obj_a->_variable_set(undef, 'some_var', 'global_a');
    $obj_b->_variable_set(undef, 'some_var', 'global_b');
    $obj_a->_variable_set('foo', 'some_var', 'catalog_a');
    $obj_b->_variable_set('foo', 'some_var', 'catalog_b');
    is( $obj_a->variable( undef, 'some_var' ), 'global_a', "variable set/get global level 1 ($test)" );
    is( $obj_b->variable( undef, 'some_var' ), 'global_b', "variable set/get global level 2 ($test)" );
    is( $obj_a->variable( 'foo', 'some_var' ), 'catalog_a', "variable set/get catalog level 1 ($test)" );
    is( $obj_b->variable( 'foo', 'some_var' ), 'catalog_b', "variable set/get catalog level 2 ($test)" );
}

# Basic initialization
SKIP: {
    # eliminate any signs of camphood so we will use the adhoc paths.
    local $ENV{CAMP};
    my $dir = File::Temp::tempdir( CLEANUP =>  1 );
    my $prev_dir = File::pushd::pushd($dir);
    my $catalog = 'test';
    my $obj = $subclass->new;
diag(sprintf('catalog(): %s    $Vend::Cfg->{CatalogName}: %s', $obj->catalog, $Vend::Cfg && $Vend::Cfg->{CatalogName}));
    eval { $obj->initialize };
diag(sprintf('catalog(): %s    $Vend::Cfg->{CatalogName}: %s', $obj->catalog, $Vend::Cfg && $Vend::Cfg->{CatalogName}));
    diag("full initialization threw exception: $@") if $@;
    is_deeply(
        [ $obj->known_catalogs ],
        [ $catalog ],
        'initialize(): full interchange/catalog process with adhoc paths',
    );

    is(
        ($obj->can('run_environment') && $obj->run_environment),
        'production',
        'run_environment() accessor'
    );

    validate_run_environment($obj, 'run_environment() consistent with boolean convenience methods');

    cmp_ok(
        eval { $obj->base_path },
        'eq',
        File::Spec->catfile($test_dir, 'catalogs'),
        'base_path()',
    );
    diag("Exception thrown calling base_path(): $@") if $@;

    cmp_ok(
        eval { $obj->ic_path },
        'eq',
        File::Spec->catfile($test_dir, 'interchange'),
        'ic_path()',
    );
    diag("Exception thrown calling ic_path(): $@") if $@;

    ok(defined(eval{ $obj->user }), 'user()');
    diag("Exception thrown calling user(): $@") if $@;

    my $layout_check = eval { $obj->camp_layout };
    diag("Exception thrown calling camp_layout(): $@") if $@;
    ok( !($@ or $layout_check), 'camp_layout()' );

    ok(
        !(defined(eval { $obj->camp_number }) or $@),
        'camp_number() undefined',
    );
    diag("Exception thrown calling camp_number(): $@") if $@;

    # Validate the various configuration options behavior
    # (just run_environment and related convenience methods for now)
    validate_configuration_possibilities($obj);

    # Verify proper parsing of things.
    $obj->_parse_file(undef, File::Spec->catfile( $test_dir, 'global.cfg' ),);
    $obj->_parse_file($catalog, File::Spec->catfile( $test_dir, 'local.cfg' ),);
diag(sprintf('catalog(): %s    $Vend::Cfg->{CatalogName}: %s', $obj->catalog, $Vend::Cfg && $Vend::Cfg->{CatalogName}));
    cmp_ok(
        $obj->variable(undef, 'WHITESPACE_TRIM'),
        'eq',
        'CHOMP',
        'global variable whitespace trimmed',
    );
    cmp_ok(
        $obj->variable($catalog, 'WHITESPACE_TRIM'),
        'eq',
        'CHOMP',
        'catalog variable whitespace trimeed',
    );
    cmp_ok(
        $obj->variable(undef, 'FANCIER_WHITESPACE',),
        'eq',
        'This has some whitespace!',
        'global variable fancier whitespace handling',
    );
    cmp_ok(
        $obj->variable($catalog, 'FANCIER_WHITESPACE',),
        'eq',
        'This has some whitespace!',
        'local variable fancier whitespace handling',
    );
    cmp_ok(
        $obj->variable(undef, 'NO_PARSE'),
        'eq',
        '@@IDENTITY@@',
        'global variable parsing: off (top scope)',
    );
    cmp_ok(
        $obj->variable(undef, 'HERE_NOPARSE_CHECK'),
        'eq',
        'outside',
        'here doc content ignored for directives',
    );
    cmp_ok(
        $obj->variable(undef, 'HERE_CHECK'),
        'eq',
        'inside the here doc',
        'here doc content properly read'
    );
    cmp_ok(
        $obj->variable($catalog, 'NO_PARSE',),
        'eq',
        '__IDENTITY__',
        'local variable parsing: off (top scope)',
    );
    cmp_ok(
        $obj->variable($catalog, 'WITH_PARSE',),
        'eq',
        'local',
        'local variable parsing: on (top scope)',
    );
    cmp_ok(
        $obj->variable($catalog, 'NESTED_NO_PARSE1',),
        'eq',
        '__IDENTITY__',
        'local variable parsing: off (nested scope)',
    );
    cmp_ok(
        $obj->variable($catalog, 'NESTED_PARSE',),
        'eq',
        'local',
        'local variable parsing: on (double-nested scope)',
    );
    cmp_ok(
        $obj->variable($catalog, 'NESTED_NO_PARSE2',),
        'eq',
        '__IDENTITY__',
        'local variable parsing: off (nested scope resumed)',
    );
    cmp_ok(
        $obj->variable($catalog, 'WITH_PARSE2',),
        'eq',
        'local',
        'local variable parsing: on (top scope resumed)',
    );
    cmp_ok(
        $obj->variable($catalog, 'FROM_GLOBAL',),
        'eq',
        'global',
        'local variable parsing: global token recognized',
    );
    cmp_ok(
        $obj->variable($catalog, 'FROM_EITHER',),
        'eq',
        'local',
        'local variable parsing: flex token recognized',
    );
    cmp_ok(
        $obj->variable($catalog, 'FROM_LOCAL',),
        'eq',
        'local',
        'local variable parsing: local token recognized',
    );
    cmp_ok(
        $obj->smart_variable('GLOBAL_ONLY'),
        'eq',
        'global',
        'smart_variable: global var, no default catalog',
    );
diag(sprintf('catalog(): %s    $Vend::Cfg->{CatalogName}: %s', $obj->catalog, $Vend::Cfg && $Vend::Cfg->{CatalogName}));
    cmp_ok(
        $obj->smart_variable('IDENTITY',),
        'eq',
        'global',
        'smart_variable: global/local var, no default catalog',
    );
    cmp_ok(
        $obj->smart_variable('IDENTITY', $catalog,),
        'eq',
        'local',
        'smart_variable: local var, explicit catalog',
    );
    cmp_ok(
        $obj->smart_variable('GLOBAL_ONLY', $catalog,),
        'eq',
        'global',
        'smart_variable: global var, explicit catalog',
    );
    $Vend::Cfg->{CatalogName} = $catalog;
    cmp_ok(
        $obj->smart_variable('IDENTITY',),
        'eq',
        'local',
        'smart_variable: local var, default catalog',
    );
    cmp_ok(
        $obj->smart_variable('GLOBAL_ONLY',),
        'eq',
        'global',
        'smart_variable: global var, default catalog',
    );

    eval {
        $obj->_parse_file(
            undef,
            File::Spec->catfile( $test_dir, 'global_parsevariables.cfg' ),
        );
    };
    ok($@, 'global config file throws exception upon ParseVariables directive');

    eval {
        $obj->_parse_file(
            undef,
            File::Spec->catfile( $test_dir, 'global_bad_heredoc.cfg' ),
        );
    };
    ok($@, 'unterminated heredoc throws exception');

    my $ifdef_file = File::Spec->catfile( $test_dir, 'ifdef.cfg' );
    $obj->_parse_file( undef, File::Spec->catfile( $test_dir, 'global_identity.cfg' ));
    $obj->_parse_file( undef, $ifdef_file );
    $obj->_parse_file( $catalog, File::Spec->catfile( $test_dir, 'catalog_identity.cfg' ));
    $obj->_parse_file( $catalog, $ifdef_file );
    for my $level (undef, $catalog) {
        my $suff = $level ? '-- catalog' : '-- global';
        ok(
            $obj->variable( $level, 'SIMPLE_IFDEF' ),
            "#ifdef simple $suff",
        );
        ok(
            $obj->variable( $level, 'SIMPLE_IFNDEF' ),
            "#ifndef simple $suff",
        );
        ok(
            $obj->variable( $level, 'EXPR_IFDEF_TRUE' ),
            "#ifdef with evaled expression $suff",
        );
        is(
            $obj->variable( $level, 'LOCATION'),
            $level ? 'catalog' : 'global',
            "#ifdef reads variables from correct space $suff",
        );
        ok(
            $obj->variable( $level, 'GLOBAL_CHECK' ),
            "#ifdef global token $suff",
        );
    }

    eval {
        $obj->_parse_file( undef, File::Spec->catfile($test_dir, 'ifdef_nested.cfg') );
    };
    ok( $@, 'nested #ifdef throws exception' );

    eval {
        $obj->_parse_file( undef, File::Spec->catfile($test_dir, 'ifdef_unterminated.cfg') );
    };
    ok( $@, 'unterminated #ifdef throws exception' );

    my $newname = 'bogus';
    my $c;
    while ($c++ < 1000 and $obj->known_catalogs($newname)) {
        $newname .= 's';
    }
    skip('cannot register test catalog to verify include directive', 4)
        if $obj->known_catalogs($newname)
    ;
    $obj->register_catalog( $newname, $test_dir );
    # This script is setuid root, so we have to untaint this (hence the regex)
    my ($current_path) = Cwd::getcwd() =~ /^(.*)/;
    eval {
        chdir $test_dir;
        $obj->_parse_file(
            $newname,
            File::Spec->rel2abs(
                File::Spec->catfile($test_dir, 'include_outer.cfg'),
                $current_path,
            ),
        );
    };
    if ($@) {
        diag("Error during include parsing: $@");
    }
    chdir $current_path;
    is(
        $obj->variable( $newname, 'INCLUDE_TEST' ),
        'inner',
        'include directive: basic include',
    );
    is_deeply(
        [ map { $obj->variable($newname, "GLOB_INCLUDE_$_") && 1 } qw(A B C) ],
        [ 1, 1, 1 ],
        'include directive: glob include',
    );

    eval { $subclass->full_reset };
    diag("Exception thrown in $subclass full_reset(): $@") if $@;
    is_deeply(
        { %{ $subclass->_resolve_invocant } },
        {},
        'full_reset() clears object',
    );

    my @inc_before = @INC;
    use_ok($subclass, qw(use_libs 1)) or skip("Failed to import $subclass", 3);
    cmp_ok(
        scalar(@INC),
        '==',
        scalar(@inc_before) + 2,
        'import(use_libs => 1) modified @INC',
    ) or skip('import(use_libs => 1) did not modify @INC', 2);

    is(
        $INC[0],
        File::Spec->catfile($subclass->ic_path(), 'custom', 'lib'),
        'import(use_libs => 1) custom/lib top path',
    );

    is(
        $INC[1],
        File::Spec->catfile($subclass->ic_path(), 'lib'),
        'import(use_libs => 1) lib second path',
    );
}

sub validate_run_environment {
    my ($obj, $test) = @_;
    return cmp_ok(
        $obj->run_environment,
        'eq',
        (
            $obj->qa && 'qa'
            or $obj->staging && 'staging'
            or $obj->production && 'production'
            or $obj->camp && 'camp'
            or undef
        ),
        $test,
    );
}

# This does twenty tests.
sub validate_configuration_possibilities {
    my ($obj, $test_prefix) = @_;
    my $orig_env = eval { $obj->run_environment };
    diag("Exception thrown getting run_environment: $@") if $@;
    $test_prefix = '' if ! defined $test_prefix;
    $test_prefix .= ': ' if $test_prefix =~ /\S/;
    my @envs = qw( camp production qa staging );
    for my $test (@envs) {
        eval { $obj->_setting_set('run_environment', $test) };
        diag("Exception thrown setting run_environment: $@") if $@;
        $obj->_parse_file(
            undef,
            File::Spec->catfile( $test_dir, "run_$test.cfg", ),
        );
        cmp_ok(
            eval { $obj->run_environment() },
            'eq',
            $test,
            $test_prefix . 'run_environment() valid'
        );
        diag("Exception thrown calling run_environment: $@") if $@;
        for my $check (@envs) {
            my $sub = $obj->can( $check );
            cmp_ok(
                (eval { $obj->$sub() } && 1) || 0,
                '==',
                ($check eq $test ? 1 : 0),
                "$test_prefix$check() valid"
            );
            diag("Exception thrown calling $test(): $@") if $@;
        }
    }
}
