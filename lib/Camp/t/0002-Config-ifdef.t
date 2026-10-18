#!/usr/bin/env perl

use strict;
use warnings;
use Test::More (tests => 123);
use File::Spec;

my ($class, $test_dir, $local_lib);
BEGIN {
    $class = 'Camp::Config';
    if ( File::Spec->rel2abs(__FILE__) =~ m{^((.+)/Camp/t/[^/]+?)\.t$} ) {
        ($test_dir, $local_lib) = ($1, $2);
    }
    die "Failed to determine test directory!\n"
        unless defined $test_dir
    ;
}
use lib $local_lib;
use_ok( $class, (no_init => 1) );

my $catalog = 'test';

# Parses global.cfg and then each named file at the catalog level into a fresh
# object.  Returns the object, the warnings issued, and any exception.
sub parse_files {
    my @files = @_;
    my $obj = $class->new;
    $obj->register_catalog( $catalog, $test_dir );
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    eval {
        $obj->_parse_file( undef, File::Spec->catfile($test_dir, 'global.cfg') );
        $obj->_parse_file( $catalog, File::Spec->catfile($test_dir, $_) ) for @files;
    };
    return ($obj, \@warnings, $@);
}

my %opener = (bare => 'ifdef', hash => '#ifdef');
my %nopener = (bare => 'ifndef', hash => '#ifndef');
my %closer = (bare => 'endif', hash => '#endif');

# Conditionals that parse cleanly, identical in both styles.
my @clean_cases = (
    [ IFDEF_TRUE              => 'on',  'ifdef with variable true' ],
    [ IFDEF_FALSE             => 'off', 'ifdef with variable false' ],
    [ IFDEF_UNSET             => 'off', 'ifdef with variable unset' ],
    [ IFNDEF_TRUE             => 'off', 'ifndef with variable true' ],
    [ IFNDEF_FALSE            => 'on',  'ifndef with variable false' ],
    [ IFNDEF_UNSET            => 'on',  'ifndef with variable unset' ],
    [ INDENTED                => 'on',  'indented directives with spaces' ],
    [ INDENTED_SKIP           => 'off', 'indented directives with tabs skip block' ],
    [ INDENTED_AFTER          => 'on',  'indented closer ends block' ],
    [ MIXED_CASE              => 'on',  'mixed-case directives' ],
    [ EXPR_TRUE               => 'on',  'ifdef expression true' ],
    [ EXPR_FALSE              => 'off', 'ifdef expression false' ],
    [ GLOBAL_VAR              => 'on',  'ifdef @VAR reads global variable' ],
    [ GLOBAL_VAR_CATALOG_ONLY => 'off', 'ifdef @VAR ignores catalog variable' ],
    [ CATALOG_VAR_GLOBAL_ONLY => 'off', 'ifdef VAR ignores global variable' ],
    [ IFDEFAULT               => 'on',  'ifdefault is not a conditional' ],
    [ HEREDOC => "ifdef FALSE\n#ifdef FALSE\nendif\n#endif", 'conditional directives in here-doc kept as value' ],
);

for my $style (qw(bare hash)) {
    my ($obj, $warnings, $err) = parse_files("$style.cfg");
    ok( !$err, "$style.cfg parses" ) or diag($err);
    is_deeply( $warnings, [], "$style.cfg issues no warnings" );
    for my $case (@clean_cases) {
        my ($var, $expected, $test) = @$case;
        is( $obj->smart_variable($var, $catalog), $expected, "$test ($style)" );
    }
    is(
        $obj->smart_variable('HEREDOC_TRUE', $catalog),
        "$closer{$style}\nVariable HEREDOC_LEAK on",
        "$closer{$style} in here-doc kept as value in true block",
    );
    ok(
        !defined $obj->smart_variable('HEREDOC_LEAK', $catalog),
        "here-doc body in true $opener{$style} block not parsed",
    );
}

for my $style (qw(bare hash)) {
    my ($open, $nopen, $close) = ($opener{$style}, $nopener{$style}, $closer{$style});
    my ($other_close) = grep { $_ ne $close } values %closer;

    # Syntax errors in the condition
    my ($obj, $warnings, $err) = parse_files("syntax_error_$style.cfg");
    ok( !$err, "$open syntax error does not die" );
    is( $obj->smart_variable('SYNTAX_IFDEF', $catalog), 'off', "$open syntax error skips block" );
    is( $obj->smart_variable('SYNTAX_IFNDEF', $catalog), 'on', "$nopen syntax error processes block, as Interchange does" );
    is( scalar(@$warnings), 2, "$open syntax errors warn once each" );
    like( $warnings->[0] || '', qr/^syntax error in ifdef condition at line 4 of \S+syntax_error_$style\.cfg/, "$open syntax error warning names line and file" );
    like( $warnings->[1] || '', qr/^syntax error in ifdef condition at line 10 of /, 'second syntax error warning names line' );

    # Mismatched closers
    ($obj, $warnings, $err) = parse_files("mismatch_$style.cfg");
    ok( !$err, "$open closed by $other_close does not die" );
    is( $obj->smart_variable('MISMATCH', $catalog), 'off', "$open block stays open through $other_close" );
    is( $obj->smart_variable('MISMATCH_AFTER', $catalog), 'on', "$close closes $open block" );
    is( scalar(@$warnings), 1, "$other_close inside $open warns once" );
    like( $warnings->[0] || '', qr/^\Q$other_close\E cannot close open \Q$open\E block at line 4 of /, "$other_close mismatch warning" );

    # Stray closers
    ($obj, $warnings, $err) = parse_files("stray_$style.cfg");
    ok( !$err, "stray $close does not die" );
    is( $obj->smart_variable('STRAY_AFTER', $catalog), 'on', "parsing continues after stray $close" );
    is( scalar(@$warnings), 1, "stray $close warns once" );
    like( $warnings->[0] || '', qr/^\Q$close\E found with no starting \Q$open\E at line 2 of /, "stray $close warning names its own style" );

    # Here-docs inside false blocks.  As in Interchange (Vend::Config), a false
    # block discards the line opening a here-doc before the here-doc is recognized,
    # so its body lines are parsed as ordinary lines and a closer among them ends
    # the block.
    ($obj, $warnings, $err) = parse_files("heredoc_false_$style.cfg");
    ok( !$err, "here-doc in false $open block does not die" );
    ok( !defined $obj->smart_variable('HEREDOC_FALSE', $catalog), "here-doc in false $open block not read" );
    is( $obj->smart_variable('HEREDOC_LEAK', $catalog), 'on', "$close in here-doc body ends false $open block" );
    is( scalar(@$warnings), 1, "trailing $close after false $open block warns once" );
    like( $warnings->[0] || '', qr/^\Q$close\E found with no starting \Q$open\E at line 9 of /, "trailing $close after false $open block is a stray closer" );

    # Unterminated conditionals
    (undef, undef, $err) = parse_files("unterminated_$style.cfg");
    like( $err, qr/unterminated_$style\.cfg' contained unterminated \Q$open\E!/, "unterminated $nopen dies naming $open" );
}

# Overlapping conditionals of the same style
for my $case (
    [ overlap_bare => 'ifdef',  'ifdef'   ],
    [ overlap_hash => '#ifdef', '#ifndef' ],
) {
    my ($file, $outer, $inner) = @$case;
    my (undef, undef, $err) = parse_files("$file.cfg");
    like( $err, qr/cannot overlap open \Q$outer\E block at line 2 of /, "$inner inside $outer dies" );
}

# Openers of the other style inside an open block are ignored with a warning, so
# their closers are mismatched closers for the open block.
for my $case (
    [ bare => 'ifdef',  'endif',  '#ifdef', '#endif' ],
    [ hash => '#ifdef', '#endif', 'ifndef', 'endif'  ],
) {
    my ($style, $outer, $outer_close, $inner, $inner_close) = @$case;

    # Outer condition true; the inner condition is false, so INNER is only set
    # if the inner opener is ignored.
    my ($obj, $warnings, $err) = parse_files("nested_other_style_$style.cfg");
    ok( !$err, "$inner inside true $outer does not die" ) or diag($err);
    is( scalar(@$warnings), 2, "$inner inside true $outer warns for opener and closer" );
    like( $warnings->[0] || '', qr/^\Q$inner\E cannot open a block inside open \Q$outer\E block at line 4 of /, "$inner inside true $outer warning" );
    like( $warnings->[1] || '', qr/^\Q$inner_close\E cannot close open \Q$outer\E block at line 6 of /, "$inner_close inside true $outer warning" );
    is( $obj->smart_variable('INNER', $catalog), 'on', "lines inside ignored $inner follow true $outer" );
    is( $obj->smart_variable('AFTER', $catalog), 'on', "$outer_close closes $outer containing $inner" );

    # Outer condition false
    ($obj, $warnings, $err) = parse_files("nested_other_style_false_$style.cfg");
    ok( !$err, "$inner inside false $outer does not die" ) or diag($err);
    is( scalar(@$warnings), 2, "$inner inside false $outer warns for opener and closer" );
    like( $warnings->[0] || '', qr/^\Q$inner\E cannot open a block inside open \Q$outer\E block at line 3 of /, "$inner inside false $outer warning" );
    like( $warnings->[1] || '', qr/^\Q$inner_close\E cannot close open \Q$outer\E block at line 5 of /, "$inner_close inside false $outer warning" );
    is( $obj->smart_variable('INNER', $catalog), 'off', "lines inside ignored $inner follow false $outer" );
    is( $obj->smart_variable('AFTER', $catalog), 'on', "$outer_close closes false $outer containing $inner" );

    # The ignored opener's condition is never evaluated.
    ($obj, $warnings, $err) = parse_files("nested_other_style_syntax_error_$style.cfg");
    ok( !$err, "$inner with syntax error inside $outer does not die" ) or diag($err);
    is( scalar(@$warnings), 1, "$inner with syntax error inside $outer warns only once" );
    like( $warnings->[0] || '', qr/^\Q$inner\E cannot open a block inside open \Q$outer\E block at line 5 of /, "$inner with syntax error inside $outer is ignored unevaluated" );
    is( $obj->smart_variable('INNER', $catalog), 'on', "lines inside ignored $inner with syntax error follow $outer" );
    is( $obj->smart_variable('AFTER', $catalog), 'on', "$outer_close closes $outer containing $inner with syntax error" );
}

# Real-world case: live value with a later DEVELOPMENT override
is(
    ( parse_files('braintree.cfg') )[0]->smart_variable('BRAINTREE_ENVIRONMENT', $catalog),
    'production',
    'live value kept when DEVELOPMENT unset',
);
is(
    ( parse_files('development.cfg', 'braintree.cfg') )[0]->smart_variable('BRAINTREE_ENVIRONMENT', $catalog),
    'sandbox',
    'DEVELOPMENT override applied when DEVELOPMENT set',
);
