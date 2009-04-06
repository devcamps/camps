package Camp::Config;

use strict;
use warnings;
use Cwd ();
use File::Spec ();
use User::pwent;
use DBI;
use Safe;
use Scalar::Util qw/blessed/;

our $VERSION = '3.00';

my %package_singletons;
my @setting_names = qw(
    camp_layout
    user
    camp_number
    ic_path
    base_path
);

sub _initialized {
    my $invocant = shift;
    return @_
        ? $invocant->_resolve_invocant->{_initialized}++
        : $invocant->_resolve_invocant->{_initialized};
}

sub _resolve_invocant {
    my $invocant = shift;
    return $invocant if blessed $invocant;
    return $package_singletons{$invocant} ||= $invocant->new;
}

sub new {
    my $invocant = shift;
    die "Can only call new() on a package name!\n" if ref $invocant;
    return bless({}, $invocant);
}

sub full_reset {
    my $invocant = shift;
    my $obj = $invocant->_resolve_invocant;
    %$obj = ();
    return;
}

sub _settings {
    my $invocant = shift;
    return $invocant->_resolve_invocant->{_settings} ||= {};
}

sub _reset_settings {
    my $invocant = shift;
    %{$invocant->_settings} = ();
    return;
}

sub _variables {
    my $invocant = shift;
    return $invocant->_resolve_invocant->{_variables} ||= {};
}

sub _server_variables {
    my $invocant = shift;
    return $invocant->_variables->{_global} ||= {};
}

sub _catalog_variable_store {
    my $invocant = shift;
    return $invocant->_variables->{_catalogs} ||= {};
}

sub _catalog_variables {
    my ($invocant, $catalog) = @_;
    die "Please specify a catalog when referencing catalog variables.\n"
        unless defined $catalog;
    die "Cannot reference catalog variables for unknown catalog '$catalog'.\n"
        unless $invocant->known_catalogs($catalog);
    return $invocant->_catalog_variable_store->{$catalog} ||= {};
}

sub _catalogs {
    my $invocant = shift;
    return $invocant->_resolve_invocant->{_known_catalogs} ||= {};
}

sub _default_catalog {
    my $invocant = shift;
    my @catalogs = $invocant->known_catalogs();
    return $catalogs[0] if scalar @catalogs == 1;
    return;
}

sub _scoped_parse_flag {
    my $invocant = shift;
    return $invocant->_resolve_invocant->{_scoped_parse_var_flag_stack} ||= [];
}

sub _setting_get {
    my ($invocant, $setting) = @_;
    die "You must specify a setting name!\n" if ! defined($setting);
    return $invocant->_settings->{$setting};
}

sub _setting_set {
    my ($invocant, $setting, $value) = @_;
    die "You must specify a setting name!\n" if ! defined($setting);
    if (defined $value) {
        $invocant->_settings->{$setting} = $value;
    }
    else {
        delete $invocant->_settings->{$setting};
    }
    return $value;
}

for my $setting (@setting_names) {
    my $name = __PACKAGE__ . '::' . $setting;
    my $sub = sub {
        my $invocant = shift;
        $invocant->initialize;
        return $invocant->_setting_get($setting);
    };
    no strict 'refs';
    *$name = $sub;
}

my @variable_accessor_names = qw(
    run_environment
);

for my $variable_name (@variable_accessor_names) {
    my $name = __PACKAGE__ . '::' . $variable_name;
    $variable_name = uc($variable_name);
    my $sub = sub {
        my $invocant = shift;
        $invocant->initialize;
        return lc( $invocant->variable(undef, $variable_name) );
    };
    no strict 'refs';
    *$name = $sub;
}

my @environment_tokens = qw(
    qa
    staging
    production
    camp
);

for my $token (@environment_tokens) {
    my $name = __PACKAGE__ . '::' . $token;
    my $sub = sub {
        my $invocant = shift;
        return ($invocant->run_environment() eq $token);
    };
    no strict 'refs';
    *$name = $sub;
}

sub _validate_run_environment {
    my $invocant = shift;
    my $i;
    for my $token (@environment_tokens) {
        my $sub = $invocant->can($token);
        $i++ if $invocant->$sub();
    }
    die "Invalid run environment. Please fix RUN_ENVIRONMENT in your Interchange configuration.\n"
        unless defined($i) and $i == 1;
    return 1;
}

sub initialize {
    my $invocant = shift;
    if (! $invocant->_initialized(1) ) {
        $invocant->inspect_environment;
        $invocant->parse_all_files;

        $invocant->set_catalog($invocant->_default_catalog())
            unless $invocant->catalog();
    }

    return;
}

sub inspect_environment {
    my $invocant = shift;
    $invocant->_reset_settings;

    $invocant->_camp_check();

    if ($invocant->camp_layout) {
        $invocant->_set_up_camp_layout;
    }
    else {
        $invocant->_set_up_adhoc_layout;
    }

    die qq{Cannot interpret operating environment; did you run "chcamp"?\n}
        unless defined $invocant->user;
    return;
}

{
    my $used_master;
    sub _camp_check {
        my $invocant = shift;
        $invocant->_setting_set('camp_layout');
        if (!$used_master++) {
            eval 'use Camp::Master ()';
        }
        # Return if no camp module exists.
        return unless defined( *Camp::Master::initialize{CODE} );

        my $camp_number;
        unless ($camp_number = $ENV{CAMP}) {
            $camp_number = $1 if Cwd::getcwd =~ m{/camp(\d+)(?:/|$)};
        }
        return unless defined $camp_number and $camp_number =~ /^\d+$/;

        $ENV{CAMP} = $camp_number;
        $invocant->_setting_set('camp_layout', 1);
        $invocant->_setting_set('camp_number', $camp_number);
        return 1;
    }
}

sub _set_up_camp_layout {
    my $invocant = shift;
    # Just use the camp system to get the relevant settings.
    Camp::Master::initialize( camp => $invocant->camp_number );
    my $camp_config = Camp::Master::config_hash();

    $invocant->_setting_set('base_path', $camp_config->{path} );
    $invocant->_setting_set('ic_path', $camp_config->{icroot} );
    $invocant->_validate_camp_user( Camp::Master::camp_user_obj() );
    return;
}

sub _validate_camp_user {
    my ($invocant, $user_obj) = @_;
    $invocant->_setting_set('user', $user_obj )
        if $> == $user_obj->uid;
    return $invocant->_setting_get('user');
}

sub _set_up_adhoc_layout {
    my $invocant = shift;
    $invocant->_setting_set('base_path', $invocant->adhoc_base_path);
    $invocant->_setting_set('ic_path', $invocant->adhoc_ic_path);
    $invocant->_validate_adhoc_user;
    return;
}

sub _validate_adhoc_user {
    my $invocant = shift;
    my $obj = getpwuid($>);
    die sprintf(
        "Invalid user; must run as interch, not %s\n",
        $obj->name
    ) if $obj->name ne 'interch';

    $invocant->_setting_set('user', $obj);
    return $invocant->_setting_get('user');
}

sub adhoc_base_path {
    return '/var/lib/interchange';
}

sub adhoc_ic_path {
    return '/usr/lib/interchange';
}

# NOTE: need to sort out how to handle include_paths in OOPy style.
sub include_paths {
    my $invocant = shift;
    my $path = $invocant->ic_path;
    die 'cannot determine base path for include paths!'
        unless $path;

    for ((qw(lib custom/lib))) {
        my $lib = File::Spec->catfile($path, $_);
        eval 'use lib $lib;';
    }
    return $path;
}

sub import {
    my $invocant = shift;
    my %opt = @_;

    $invocant->initialize
        if !$opt{no_init};

    if ($opt{use_libs}) {
        $invocant->include_paths;
    }
    return;
}

sub catalog {
    my $table = $main::{'Vend::'};
    return unless defined $table->{Cfg};
    return ${$table->{Cfg}}->{CatalogName};
}

sub set_catalog {
    my ($invocant, $catalog) = @_;
    if (defined $catalog) {
        die "Cannot switch to catalog '$catalog'; it is not a known catalog.\n"
            unless $invocant->known_catalogs($catalog);
        $Vend::Cfg->{CatalogName} = $catalog;
    }
    else {
        my $table = $main::{'Vend::'};
        delete $Vend::Cfg->{CatalogName} if defined $table and defined $table->{Cfg};
    }
    return $catalog;
}

sub variable {
    my $invocant = shift;
    my $catalog = shift;
    my $all = wantarray && !@_;
    my $var;
    $var = shift if !$all;
    die "Catalog '$catalog' is not registered.\n"
        if defined($catalog)
            and !$invocant->known_catalogs($catalog);
    my $source = defined $catalog ? $invocant->_catalog_variables($catalog) : $invocant->_server_variables;
    die "Cannot find variables repository!\n" unless defined $source;
    return %$source if $all;
    die "No variable specified for retrieval!\n" if ! defined $var;
    return $source->{$var};
}

sub dbh {
    my ($invocant, $catalog, $options) = @_;

    $invocant->set_catalog($catalog) if $catalog;
    $catalog = $invocant->catalog();

    $options =
        {
            AutoCommit => 1,
            RaiseError => 1,
        }
        unless ref $options eq 'HASH';

    my $dbh = DBI->connect(
            $invocant->db_dsn($catalog),
            $invocant->db_user($catalog),
            $invocant->db_password($catalog),
            $options
        ) or die "Unable to obtain database handle: $DBI::errstr\n";

    return $dbh;
}

sub db_dsn {
    my ($invocant, $catalog) = @_;
    return $invocant->smart_variable('SQLDSN', $catalog);
}

sub db_user {
    my ($invocant, $catalog) = @_;
    return $invocant->smart_variable('SQLUSER', $catalog);
}

sub db_password {
    my ($invocant, $catalog) = @_;
    return $invocant->smart_variable('SQLPASS', $catalog);
}

sub _variable_set {
    my ($invocant, $catalog, $variable, $value) = @_;

    die "Catalog '$catalog' is unknown; please register it\n"
        if defined $catalog
            and ! $invocant->known_catalogs($catalog);

    my $target = defined($catalog) ? $invocant->_catalog_variables($catalog) : $invocant->_server_variables;

    return $target->{$variable} = $invocant->_substitute_variables($catalog, $value);
}

sub _substitute_variables {
    my ($invocant, $catalog, $value) = @_;
    die "Catalog '$catalog' is unknown; please register it\n"
        if defined $catalog
            and ! $invocant->known_catalogs($catalog);

    my $scoped_parse_var_flag = $invocant->_scoped_parse_flag;

    return $value if !(defined($value) and $scoped_parse_var_flag->[-1]);

    my ($tokens, $cat_var, $server_var);
    if (defined $catalog) {
        $cat_var = $invocant->_catalog_variables($catalog);
        $tokens = qr{(@|_(?=_))(@|_)};
    }
    else {
        $tokens = qr{(@)(@|_)};
    }
    $server_var = $invocant->_server_variables;
    $value
        =~ s/($tokens)([A-Z0-9_]+?)\3\2/
                my $no_op = "$1$4$3$2";
                # print STDERR "Substituting '$no_op' in for $variable...\n";
                my $result;
                if ($1 eq '__') {
                    $result = exists( $cat_var->{$4} )
                        ? $cat_var->{$4}
                        : $no_op
                    ;
                }
                elsif ($1 eq '@_') {
                    $result = (defined($cat_var) && exists( $cat_var->{$4} ))
                        ? $cat_var->{$4}
                        : exists( $server_var->{$4} )
                            ? $server_var->{$4}
                            : $no_op
                    ;
                }
                else {
                    $result = exists( $server_var->{$4} )
                        ? $server_var->{$4}
                        : $no_op
                    ;
                }
            /gxe
    ;
    return $value;
}

sub _parse_file {
    my ($invocant, $catalog, $file) = @_;

    die "Catalog '$catalog' is unknown; please register it"
        if defined $catalog
            and ! $invocant->known_catalogs($catalog);

    my $scoped_parse_var_flag = $invocant->_scoped_parse_flag;

    print STDERR "Parsing file $file" . (defined($catalog) && " catalog $catalog") . "\n"
        if $Camp::Config::DEBUG;

    my $entry_scope = $#$scoped_parse_var_flag;
    my ($marker, $key, $val, $mark_type, $ifdef);
    open my $CONF, '<', $file or die "Can't open configuration file '$file' from directory '" . Cwd::getcwd() . "': $!\n";
    while (<$CONF>) {
        if (defined $marker) {
            if (/^$marker\n?$/) {
                $marker = undef;
            }
            else {
                $val .= $_;
                next;
            }
        }
        elsif (/^\s*#if(n?)def\s*(.*)/) {
            die sprintf("#ifdefs cannot overlap at line %d of %s!\n", $., $file) if defined $ifdef;
            $ifdef = $invocant->_ifdef($catalog, $2, $1);
            next;
        }
        elsif (/^s*#endif\s*$/) {
            warn sprintf("#endif found with no starting #ifdef at line %d of %s!\n", $., $file) unless defined $ifdef;
            $ifdef = undef;
            next;
        }
        else {
            next if defined $ifdef and !$ifdef;
            next if /^\s*#/ or /^\s*$/ or !/\S/;
            chomp;

            ($key, $val) = /^\s*(\w+)\s+(.*)/;
            $key = defined($key) ? lc($key) : $_;
            if (defined($val) and $val =~ /^(.*)<(<|&)(\w+)\s*/) {
                # here doc
                $val = $1;
                $mark_type = $2;
                $marker = $3;
                next;
            }
        }

        if (
            !defined($catalog)
            and $key eq 'catalog'
            and $val =~ /^(\w+)\s+(\S+)/
        ) {
            $invocant->register_catalog($1, $2);
        }
        elsif (
            $key eq 'parsevariables'
            or $key =~ /^\s*<ParseVariables\s+(Y(?:es)?|No?)>$/i
        ) {
            my ($scoped, $setting);
            if ($key ne 'parsevariables') {
                $scoped = 1;
                $setting = $1;
            }
            else {
                $setting = $val;
                die "Invalid value for ParseVariables ('$val'); use Yes/No values.\n"
                    unless $setting =~ /^\s*(?:y(?:es)?|no?)\s*$/i;
            }
            chomp $setting;
            die "ParseVariables directive only applies to catalog-level configuration files!\n"
                if ! defined $catalog;
            push @$scoped_parse_var_flag, $scoped_parse_var_flag->[-1]
                if $scoped;
            $scoped_parse_var_flag->[-1] = ($setting =~ /y/i);
        }
        elsif ($key =~ /^\s*<\/ParseVariables>\s*$/i) {
            pop @$scoped_parse_var_flag if $#$scoped_parse_var_flag > $entry_scope;
        }
        elsif (
            $key eq 'variable'
            and $val =~ s/^(\w+)(\s+|\s*$)//
        ) {
            my $variable = $1;
            $val =~ s/\s+$// if defined $val;
            $val = $invocant->_substitute_variables($catalog, $val);
            $invocant->_variable_set($catalog, $variable, $val);
        }
        elsif (
            $key eq 'include'
            and my @incfiles = grep -f $_, glob($val)
        ) {
            for (@incfiles) {
                $invocant->_parse_file($catalog, $_);
            }
        }

        $mark_type = $key = $val = $marker = undef;
    }

    die "Configuration file '$file' contains unterminated <<HERE doc (<$mark_type$marker)!\n" if defined $marker;
    die "Configuration file '$file' contained unterminated #ifdef!\n" if defined $ifdef;
    close $CONF or die "Error closing $file\n";

    @$scoped_parse_var_flag = @$scoped_parse_var_flag[0..$entry_scope];
    return;
}

sub _ifdef {
    my ($invocant, $catalog, $ifdef, $not, $file, $line) = @_;
    my ($result, $var, $expr, $value);
    $ifdef =~ /^\s*(\@?)(\w+)\s*(.*)/;
    ($var, $expr) = ($2, $3);
    $catalog = undef if $1;
    $value = $invocant->variable($catalog, $var) || '';
    if (!$expr) {
        $result = ! (not $value);
    }
    else {
        my $safe = new Safe;
        $result = $safe->reval( "q{$value} $expr" );
        if ($@) {
            warn sprintf('syntax error in #ifdef at %d of %s: %s', $line, $file, $@);
            $result = undef;
        }
    }
    return $not ? !$result : $result;
}

sub register_catalog {
    my ($invocant, $name, $path) = @_;
    die "Invalid catalog name '$name'!" unless defined $name and length $name;
    die 'Invalid catalog path!' unless defined $path and length $path;
    die "Catalog '$name' is already registered!" if $invocant->known_catalogs($name);
    print STDERR "Registering catalog $name at $path.\n" if $Camp::Config::DEBUG;
    $invocant->_catalogs->{$name} = $path;
    return;
}

sub _catalog_by_name {
    my ($invocant, $catalog) = @_;
    die "You must supply a catalog name to lookup catalog by name.\n"
        unless defined $catalog and length $catalog;
    return $invocant->_catalogs->{$catalog};
}

sub known_catalogs {
    my $invocant = shift;
    if (@_) {
        my $name = shift;
        return defined($invocant->_catalog_by_name($name)) && 1;
    }
    return sort {$a cmp $b} keys %{$invocant->_catalogs} if wantarray;
    die "You must supply a catalog name when calling in a scalar context!\n";
}

sub smart_variable {
    my $invocant = shift;
    my $variable = shift;
    die "No variable specified!\n"
        unless defined $variable;
    my $catalog = shift;
    $catalog = $invocant->catalog if ! defined $catalog;
    my $result;
    if (defined($catalog)) {
        die "Catalog '$catalog' is unknown; please register it"
            if defined $catalog
                and ! $invocant->known_catalogs($catalog);
        my $repository = $invocant->_catalog_variables($catalog);
        $result
            = exists($repository->{$variable})
                ? $repository->{$variable}
                : $invocant->_server_variables->{$variable};
    }
    else {
        $result = $invocant->_server_variables->{$variable};
    }
    return $result;
}

my @global_files = qw(
    interchange.cfg
);

my @catalog_files = qw(
    catalog.cfg
);

sub catalog_path {
    my ($invocant, $catalog) = @_;
    $invocant->set_catalog($catalog) if $catalog;
    $catalog = $invocant->catalog();

    return $invocant->_catalog_by_name($catalog);
}

sub parse_all_files {
    my $invocant = shift;
    $invocant->initialize;
    my $scoped_parse_var_flag = $invocant->_scoped_parse_flag;
    @$scoped_parse_var_flag = (0);
    # Note that we'll continually return to $cwd such that areas likely to throw an error
    # that could be trapped by an eval will still probably result in the current working
    # directory remaining consistent outside of this sub.
    # Note that we have to untaint this sucker, which is the purpose of the regex.
    my ($cwd) = Cwd::getcwd() =~ /^(.*)/;
    for my $file (@global_files) {
        chdir( $invocant->ic_path );
        eval {
            $invocant->_parse_file(
                undef,
                File::Spec->catfile( $invocant->ic_path, $file ),
            );
        };
        if ($@) {
            chdir $cwd;
            die "Unable to parse interchange config file $file:\n\t$@\n";
        }
    }

    chdir $cwd;

    $invocant->_validate_run_environment;

    for my $catalog ($invocant->known_catalogs) {
        # Set the catalog temporarily (needed for catalog_path(), at least).
        $invocant->set_catalog($catalog);
        chdir $invocant->catalog_path();
        push @$scoped_parse_var_flag, $scoped_parse_var_flag->[-1];
        for my $file (@catalog_files) {
            eval {
                $invocant->_parse_file(
                    $catalog,
                    File::Spec->catfile( $invocant->catalog_path($catalog), $file ),
                );
            };
            warn "Unable to parse file $file for catalog $catalog:\n\t$@\n"
                if $@;
        }
        pop @$scoped_parse_var_flag;
        chdir $cwd;
        # Unset the catalog that was set above.
        $invocant->set_catalog();
    }
    return;
}

sub env_variables {
    my $invocant = shift;
    my @vars = @_;
    my @out;
    for (@vars) {
        my $var = $invocant->smart_variable($_) || '';
        push @out, "export $_=" . $var;
    }
    push @out, 'export CAMP_BASE_PATH=' . $invocant->base_path();

    my $out = join "\n", @out;
    return $out;
}


1;

=pod

=head1 NAME

Camp::Config -- Standard module for determining operating environment and configuration settings

=head1 DESCRIPTION

B<Camp::Config> is a basic utility module that understands the camp layout
of the Camp development environments as well as the layout of production
environments for both interchange and associated catalogs; it allows for easy
manipulation of your Perl lib search paths (to include interchange/lib and
interchange/custom/lib in your scripts without hardcoding paths), and also reads
standard Interchange configuration files for variables at both the daemon
and catalog level.  In addition, it provides methods for accessing this information,
such that Perl modules may safely rely on configuration variables and such without
needing to rely on Interchange actually being present.

=head1 USAGE

One of the simpler, more obvious usages of B<Camp::Config> is within
test scripts.  Test scripts need to run in any camp, as well as in production.  This
has traditionally caused problems for scripts that need to test modules within the
Interchange standard and custom library paths, as there was no convenient way around
hardcoding the I<use lib ...> calls within the test script.  B<Camp::Config>,
by knowing about the environment in which it is running, takes care of this for
you.

An unfriendly, unportable hard-coded implementation, like this:

 #!/usr/local/bin/perl
 use lib "$ENV{HOME}/camp45/interchange/lib";
 use lib "$ENV{HOME}/camp45/interchange/custom/lib";
 use Test::More tests => 2010;
 use Vend::Util;
 use Camp::Catalogs::Foo;
 ...

can now be implemented in the following easy, portable fashion:

 #!/usr/local/bin/perl
 use Camp::Config use_libs => 1;
 use Test::More tests => 2010;
 use Vend::Util ();
 use Camp::Catalogs::Foo;
 ..

That replaced two lines of code with one, so it's not a huge savings.  But it's
not nearly as annoying as typing raw paths.  Plus, this will work on any camp
or on production without requiring a single alteration.  That's the point, as it
allows you to store the code verbatim in version control and use it in any
environment without modification.

Note that the 'use_libs => 1' passed to the I<use> call is necessary to tell
B<Camp::Config> to alter the library search paths at import.  This also
could be accomplished via:

 use Camp::Config;
 use Test::More tests => 2010;
 BEGIN {
     Camp::Config->include_paths;
 }
 use Vend::Util;
 use Camp::Catalogs::Foo;
 ...

In the above case, a BEGIN block would be necessary since I<use> calls are checked
at compile time; the subsequent I<use> calls would fail if the B<include_paths()>
method wasn't called.  This is obviously less user-friendly than simply using
the module with the I<use_libs> option, so just go with that option unless you have
a really good reason.

That's really only the beginning of the benefits of using a module for determining
this kind of thing.  As stated earlier, B<Camp::Config> parses the standard
Interchange configuration files at the daemon/global level and the catalog
level, and understands the I<Variable> directive (including variable interpolation
therein) along with the I<ParseVariables> directive.  As such, Perl modules to be
used within Interchange (or outside of it, in fact) can use Camp::Config's
interface to access this information and be confident of working both in IC and
externally (for purposes of testing, or for use in external scripts, etc.).  It also
can follow I<include> directive calls, meaning that all configuration files involved
with the daemon and catalogs are seen.

For instance, we might want to use Module::Refresh to reload modules at a certain
point in a process, but only if in camp mode:

 package My::Awesome::Package;
 use strict;
 use warnings;
 use Camp::Config;
 # don't even load the module if we're not in development.
 eval "use Module::Refresh"
     if Camp::Config->camp
 ;

 sub refresh {
     return unless Camp::Config->camp;
     return Module::Refresh->refresh;
 }

 sub do_awesome_stuff {
     my $self = shift;
     $self->refresh;
     ....here's where you implement your awesomeness...
 }

 Module::Refresh->new if Camp::Config->camp;
 ...

Or, perhaps we need to know information about the current catalog and some database-oriented
variables.

 sub introspect {
     my $self = shift;
     $self->{catalog} = Camp::Config->catalog;
     $self->{db_user} = Camp::Config->smart_variable( 'SQLUSER' );
     $self->{db_dsn}  = Camp::Config->smart_variable( 'SQLDSN' );
     return;
 }

As these examples hopefully demonstrate, B<Camp::Config> exposes all our
Interchange-space configuration variables and such through a simple interface that
can be used within and beyond Interchange, eliminating the need for duplication
of configuration information and increasing the portability and maintainability of
code.

=head1 ASSUMPTIONS ABOUT ENVIRONMENT

B<Camp::Config> relies on a combination of environment variables (managed
by the B<chcamp> utility) and Interchange global variables to determine the
particulars of the runtime environment in which it is invoked.  Three pieces of
information are determined from this:

=over

=item File layout

File layouts are either 'per-user' (meaning the "camp" setup in which a
particular camp lives in a directory immediately under the owner's home directory)
or 'system-wide' (meaning the RPM-style IC install expected when the user is 'interch').

=item Application role

A given Interchange daemon expects to either be "frontside" (public-facing, without
the in-house management apps activated) or "backside" (in-house facing, with all
management and inventory functionality available).  This has traditionally been thought
of as "office", but the terms "frontside" and "backside" are more consistent with the
way the engineering teams are organized and these roles are discussed.

=item Run environment

Indicates the basic purpose for which the Interchange is being run.
Distinguishes between development (or camp), QA, staging, production.

=back

Upon compiling, the module looks first to see if a per-user camp layout
is active (based on how B<chcamp> sets this) and, if so,
verifies that the running user is the owner of that camp.  If no camp is specified
in the environment, B<Camp::Config> checks to see if the running user is
'interch', meaning that we are operating with a system-wide file layout.

When determined to be in per-user mode (meaning within a camp, with a valid camp
owner as the effective UID of the process), paths will be set relative to that
camp:

=over

=item *

I<base_path> => "home/$username/camp$camp_number"

=item *

I<ic_path> => I<base_path> . '/interchange'

=back

When the file layout is system-wide RPM-style, the paths are set up for
an RPM-install Interchange:

=over

=item *

I<base_path> => '/var/lib/interchange'

=item *

I<ic_path> => '/usr/lib/interchange'

=back

Note that the I<base_path> is where catalogs, scripts, etc. are expected to reside,
and is not necessarily the "root" of the environment (though it effectively is in the
case of camps); the I<ic_path> is where the interchange code/configuration lives.

Library paths added by the I<use_libs> option at import, or by calls to B<include_paths()>,
are relative to I<ic_root> and are:

=over

=item *

lib

=item *

custom/lib

=back

(Added in the above order, meaning the latter path takes precedence.)

The environment determination is done at compile time, meaning that any environment
problems/inconsistencies will prevent compilation of code that uses this module.  This
means that camps require a "chcamp" call up front to set the active camp, or that
production environments must be launched with no camp set by the interch user.

In addition to environment stuff, configuration files are also processed at compile
time, meaning that the IC-level file(s) are processed first in order to determine
IC-level variables and identify known catalogs, followed by processing of catalog-level
files per-catalog.

Consistent with how Interchange itself operates, B<Camp::Config> begins config-file
parsing at I<interchange.cfg> (in your B<ic_path()>).  Per catalog found, catalog config
parsing begins at the I<catalog.cfg> file (in the B<catalog_path()>).  Catalog parsing
begins only after all Interchange-level parsing is complete.  At each level, B<include>
directives are followed on-demand (meaning that the file (or files) included is parsed
before proceeding with the rest of the outer file that contained the include).

The entire process will die if any IC-level files are missing; however, warnings
will be issued for any missing catalog-level files, without throwing exceptions.

Within any of the configuration files parsed, B<Camp::Config> will look for
I<Variable> and I<Include> declarations; for IC-level files, I<Catalog>
directives are parsed as well; for catalog-level files, the <ParseVariables> directive
is also supported.  The behaviors of I<Variable> and I<ParseVariables>
are designed to be consistent with Interchange itself, to ensure that variables
have the same value/meaning within B<Camp::Config> and the various
IC-space repositories.  Block-style declarations can be used with I<ParseVariables>
and this module will understand it (though Camp's Interchange does not have support
for this yet; this is in more recent Interchange versions, however).

The Interchange-level configuration file(s) B<must> specify meaningful values
for B<APPLICATION_ROLE> and B<RUN_ENVIRONMENT>.  After parsing the IC-level files
for global variables, the settings in these variables will be validated and
initialization will fail if the settings are invalid.  Therefore, like B<chcamp>,
any process relying on B<Camp::Config> for operation will have compilation
errors if the variables aren't properly prepared.  The valid values for each:

=over

=item B<APPLICATION_ROLE>

"backside", "frontside"

=item B<RUN_ENVIRONMENT>

"camp", "production", "qa", "staging"

=back

=head1 HERE DOCS

B<Camp::Config> is heredoc-aware, meaning that (like Interchange itself) it handles
heredocs as they come up within a config file, even if it doesn't understand the directive
to which the heredoc applies.  In this way, B<Camp::Config> knows to treat content
within a heredoc as a value associated with a directive, rather than processing that
content for directives.  Similarly, heredocs can be used with the directives that
B<Camp::Config> does understand.

B<Camp::Config> will throw an exception if any file parsed contains an unterminated
heredoc.

=head1 CONDITIONS (IFDEF, IFNDEF)

B<Camp::Config> understands B<#ifdef> and B<#ifndef> statements, and treats them
exactly as does Interchange itself.  For clarity's sake, these declarations take the following
form:

 #if(n)def VARIABLE_NAME [ perl_expression ]
 ...other directives...
 #endif

The I<VARIABLE_NAME> is expected to correspond to a variable of the same scope as the
level of parsing (meaning that for global files it would correspond to a global variable
and for catalog files it would correspond to a catalog variable).  At the catalog level,
the I<VARIABLE_NAME> may be prefixed by an at symbol ("@") to indicate that the variable
is global rather than catalog-level.

If the optional I<perl_expression> is provided, it will be evaled with the value of
of I<VARIABLE_NAME>, such variable FOO with value "bar" in the following directive:

 #ifdef FOO eq 'pooh'

would eval as

 'bar' eq 'pooh'

and thus be false.

If the expression is left out, the check is based on the perly truth of the variable named;
when provided, the check is based on the perly truth of the eval operation.  The B<#ifdef>
directive will be true if the result is true; the B<#ifndef> directive will be true if the
result is false.  Configuration lines within a true B<#if(n)def> block will be processed,
and within a false block ignored.  The blocks must be terminated by B<#endif>.

B<Camp::Config> will throw an exception if any file parsed contains an unterminated
B<#ifdef> block.

=head1 METHODS

Though this module does not currently provide objects, all methods are object-style,
meaning they should be invoked with "$package->method()" syntax; no subs are
exported.  This was done to keep it consistent with the vast majority of modules
being implemented for B<MVC2.0>.

=over

=item B<per_user_file_layout()>

Returns a boolean value with truth indicating that the Interchange uses a
per-user "camp" file layout, and false indicating an RPM-style system-wide
file layout.

=item B<run_environment()>

Returns 'camp', 'production', 'qa', or 'staging' depending on the B<RUN_ENVIRONMENT>
Interchange global variable value.

=item B<camp()>

Returns true if the B<run_environment()> is 'camp'.

=item B<production()>

Returns true if the B<run_environment()> is 'production'.

=item B<qa()>

Returns true if the B<run_environment()> is 'qa'.

=item B<staging()>

Returns true if the B<run_environment()> is 'staging'.

=item B<application_role()>

Returns 'frontside' or 'backside' depending on the B<APPLICATION_ROLE> Interchange
global variable value.

=item B<backside()>

Returns true if the B<application_role()> is 'backside'.

=item B<frontside()>

Returns true if the B<application_role()> is 'frontside'.

=item B<user()>

Returns an User::pwent object representing the password-file information about
the owner of the current camp/environment.

=item B<camp_number()>

Returns the current development camp number when in development mode; returns
I<undef> in production mode.

=item B<ic_path()>

Returns the path of the environment's interchange install.

=item B<base_path()>

Returns the "base path" for the environment, where all catalogs, common files,
scripts, etc. are expected to live.

=item B<catalog()>

Returns the name of the active catalog, based on internal values in the Interchange
global space; returns undef if no catalog is active (meaning that you're probably not
running in Interchange, or running in Interchange before catalogs are initialized).

=item B<catalog_path( $catalog )>

Returns the catalog root path of I<$catalog>, throwing an error if I<$catalog> is
not known to B<Camp::Config>.

=item B<variable( $catalog, [ $variable ] )>

In scalar context: Returns the value (or undef if nonexistent) of I<$variable>
within catalog I<$catalog>; use I<undef> for I<$catalog> if the IC-level variable
is desired.  Note that B<variable()> does B<not> cascade values from IC level down
to catalog level; the value returned will be specific to I<$catalog> only.

In list context, with no I<$variable> specified: returns a name/value pair list
of all variables known within I<$catalog>.  This is literally a name/value pair
list; it cannot be used to change the values within the underlying hash.

=item B<smart_variable( $variable, [ $catalog ] )>

Similar to the scalar-context version of B<variable()>, except that this performs
a cascade such that if the requested I<$variable> does not exist within the catalog,
the value in the IC-level space will be returned.  This makes it approximately
equivalent to variable identifiers of the style I<@_IDENTIFIER_@> in ITL.

The I<$catalog> argument is optional; when not specified, the default behavior is
to use the value of the B<catalog()> method.  If I<$catalog> is given I<undef>,
or if left unspecified and B<catalog()> returns I<undef>, then only the IC variables
will be consulted.

=item B<known_catalogs( [ $name ] )>

If optional I<$name> is specified, returns a boolean indicating whether that catalog
is known to B<Camp::Config>.

If I<$name> is not provided, returns an alphabetically-sorted list of known catalog
names in list context, or an arrayref of the same in scalar context.

=item B<include_paths()>

Modifies the @INC search paths to include the relevant Interchange-relative
libary paths, based on B<ic_path> for the current environment.

=item B<import( %options )>

Like the B<import()> sub of most any exporter, this isn't intended to be used
directly, but as part of a I<use> call.  The I<%options> available are subject
to change:

=item B<dbh( $catalog, $options )>

Attempts to get you a database handle for the current catalog.  If you pass
in the optional I<$catalog> variable, it will attempt to use that.  If you do
not pass it, then it will use the catalog set for the class, or failing that, will
attempt to use the catalog registered with the camp if there is only one.  If
there are more than one catalog, it will give up.

This subroutine uses db_dsn(), db_user(), and db_password() to get the dsn, username,
and password respectively for the catalog.

I<$options> is an optional hash ref that contains the options that will be passed directly
to the DBI->connect() routine.  If nothing is passed in, it will default to using
AutoCommit => 1 and RaiseError => 1.

The database handle is not set in the class or cached, you will get a new one
each time you call this routine.

=item B<db_dsn( $catalog )>

Returns the value set in the SQLDSN variable for the catalog specified.
I<$catalog> is optional.  It uses the smart_variable subroutine, so all
of the caveats for that apply here.

=item B<db_user( $catalog )>

Returns the value set in the SQLUSER variable for the catalog specified.
It uses the smart_variable subroutine, so all
of the caveats for that apply here.

=item B<db_password( $catalog )>

Returns the value set in the SQLPASS variable for the catalog specified.
I<$catalog> is optional.  It uses the smart_variable subroutine, so all
of the caveats for that apply here.

=over

=item I<use_libs>

If provided with a true value ("use Camp::Config (use_libs => 1)"),
B<Camp::Config> will invoke B<include_paths()> at import time to
modify the process' Perl library search path to include the Interchange-aware
paths.

=item I<no_init>

If provided with a true value ("use Camp::Config (no_init => 1,)"),
B<Camp::Config> will load in without running its own initialization
process, meaning that the Interchange files aren't parsed and the environment
isn't validated.  Use of this isn't really recommended, but it's there for utilities
like B<chcamp>.

=back

=back

=head1 CREDITS

Original author: Ethan Rowe (ethan@endpoint.com) End Point Corporation

This module has tests.  It also probably has bugs.  It is, after all, software.

=cut
