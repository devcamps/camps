package Camp::Master;

use strict;
use warnings;
use Cwd;
use IO::Handle;
use Fcntl qw(:mode);
use File::Basename ();
use File::Path;
use File::pushd;
use File::Temp ();
use File::Spec;
use Data::Dumper;
use User::pwent;
use DBI;
use Exporter;
use base qw(Exporter);

our $VERSION = '3.06';

@Camp::Master::EXPORT = qw(
    base_path
    base_tmpdir
    base_user
    camp_db_config
    camp_db_type
    camp_list
    camp_type_list
    camp_user
    camp_user_info
    camp_user_obj
    camp_user_tmpdir
    config_hash
    create_camp_path
    create_camp_subdirectories
    dbh
    db_path
    default_camp_type
    do_system
    do_system_soft
    get_next_camp_number
    has_ic
    has_rails
    has_app
    initialize
    install_templates
    mysql_path
    pgsql_path
    prepare_apache
    prepare_camp
    prepare_database
    prepare_ic
    prepare_rails
    process_copy_paths
    register_camp
    resolve_camp_number
    role_password
    roles
    roles_path
    role_sql
    run_post_mkcamp_command
    server_control
    set_camp_comment
    set_camp_user
    svn_repository
    type
    type_path
    unregister_camp
    vcs_checkout
    vcs_refresh
    vcs_remove_camp
    vcs_type
);


=head1 NAME

Camp::Master - library routines for management of camps

=head1 VERSION

3.06

=cut


my (
    @base_edits,
    @edits,
    %edits,
    $has_app,
    $has_rails,
    $has_ic,
    $initialized,
    $type,
    $vcs_type,
    $base_camp_user,
    $base_user_obj,
    $camp_user,
    $camp_user_obj,
    $camp_user_info,
    $dbh,
    $conf_hash,
    $roles,
    $camp_db_config,
);

@base_edits = qw(
);
$base_camp_user = 'camp';

sub initialize {
    my %options = @_;
    if (!$initialized or $options{force}) {
        $initialized
            = $conf_hash = $has_rails = $has_ic = $type = $vcs_type
            = $camp_user = $camp_user_info = $roles
            = $camp_db_config
            = undef;
        @edits = %edits = ();
        $conf_hash = undef;
        if (defined $options{camp} and $options{camp} =~ /^\d+$/) {
            my $hash = get_camp_info( $options{camp} );
            set_type( $hash->{camp_type} );
            set_camp_user( $hash->{username} );
            set_vcs_type($hash->{vcs_type});
            read_camp_config();
            $initialized++;
            # initialize the config hash to the requested camp number.
            $hash = config_hash( $options{camp} );
        }
        else {
            set_type( $options{type} ) if defined $options{type};
            set_vcs_type($options{vcs_type}) if defined $options{vcs_type};
            set_camp_user( $options{user} ) if defined $options{user};
            read_camp_config();
            $initialized++;
        }
    }
    return $initialized;
}

sub set_type {
    my $new_type = shift;
    die "Invalid type '$new_type' requested!\n"
        unless validate_type( $new_type )
    ;
    return $type = $new_type;
}

sub type {
    die "No type set!\n" unless defined $type;
    return $type;
}

sub set_vcs_type {
    my $new_type = shift;
    die "Invalid vcs_type '$new_type' requested!\n"
        unless validate_vcs_type($new_type);
    return $vcs_type = $new_type;
}

sub vcs_type {
    my $vcs = vcs_type_is_set();
    die "No vcs_type set!  Please set the version control system for your camp/camp-type.\n" unless $vcs;
    return $vcs;
}

sub vcs_type_is_set {
    return $vcs_type && validate_vcs_type($vcs_type);
}

sub validate_vcs_type {
    my $new_type = shift;
    my ($type) = ($new_type =~ /\A(svn|git)\z/);
    return $type;
}

sub read_camp_config {
    warn "Reading camp config file though already initialized...\n" if $initialized;
    my $file = File::Spec->catfile( type_path(), 'camp-config-files', );
    open(my $CONFIG, '<', $file) or die "Type-specific config file missing: $file\n";
    @edits = @base_edits;
    while (<$CONFIG>) {
        s/^\s+//;
        s/\s+$//;
        next unless /\S/;
        next if /^\s*#/;
        push @edits, $_;
    }
    close $CONFIG or die "Error closing $file: $!\n";
    %edits = map { $_ => 1, } @edits;
    $has_rails = $has_ic = undef;
    return @edits;
}

sub camp_db_type {
    my %settings = camp_db_config();
    my $dsn = $settings{dsn};
    die "The camp database config file must specify a DSN!\n" unless defined $dsn;
    my ($type) = $dsn =~ /^dbi:([^\s:]+):/i;
    die "The camp database DSN appears to be invalid: $dsn\n" unless defined $type;
    return lc $type;
}

sub camp_type_db_type {
    my $conf = config_hash();
    return $conf->{db_type};
}

=pod

=head1 CAMP MASTER DATABASE CONFIGURATION

The camp system relies on a single master database to hold the known camp users,
camp types, and existing camps.  All camps within the system are registered within
this database, along with the type of camp, the version control system used for
that camp, the owner, etc.  The camp system will not function without this
database.

Connectivity info for this database must be provided to the camp system.  The
camp master database configuration file, B<camp-db-config>, serves this purpose.

It is expected to live at B<$camp_base/camp-db-config>.

Entries consist of the form I<$key:$value>, one per line.

The following key/value pairs are expected to be provided by this file:

=over

=item I<dsn>

The DBI DSN for the master camp database.  See the DBI docs for DBI well-formedness;
it depends in no small part on the database driver used (currently, only Pg and mysql
drivers are supported).

=item I<user>

The username to use when connecting to the master camp database.

=item I<password>

The password to use when connecting to the master camp database.  If your database is
configured to allow access without a password, then you may leave this option out;
however, that is typically not recommended, since the connection attempts will happen
from different UNIX user accounts.

=back

Therefore, a typical B<camp-db-config> file might look like:

 dsn:dbi:Pg:dbname=camps
 user:camp
 password:fuggedabowwditt

=cut

sub camp_db_config {
    return %$camp_db_config if defined $camp_db_config;
    my $file = File::Spec->catfile( base_path(), 'camp-db-config' );
    die "No camp database configuration found ($file)!\n"
        unless -f $file
    ;
    open my $FILE, '<', $file or die "Failed to open $file to determine camp db type: $!\n";
    while (<$FILE>) {
        next if /^\s*#/ or !/\S/;
        chomp;
        my ($key, $val) = /^\s*(\S+?):(.*?)\s*$/;
        die "Invalid key/value pair in $file at line $.!: $_\n" unless defined $key;
        ${ $camp_db_config ||= {} }{$key} = $val;
    }
    close $FILE or die "Error closing $file: $!\n";
    die "No settings found in $file for camp db access!\n" unless defined $camp_db_config and %$camp_db_config;
    return %$camp_db_config;
}

sub validate_type {
    my $new_type = shift;
    my $type_path = type_path( $new_type );
    die "Type '$new_type' is invalid; no base directory found at $type_path!\n"
        unless -d $type_path
    ;
    return 1;
}

sub base_path {
    return base_user_path();
}

sub base_tmpdir {
    my $dir = File::Spec->catfile(base_path(), 'tmp');
    -d $dir
        or mkpath($dir)
        or die "base_tmpdir '$dir' didn't exist and couldn't be created\n";
    return $dir;
}

sub type_path {
    my $local_type = @_ ? shift : type();
    return File::Spec->catfile( base_path(), $local_type, );
}

sub create_camp_subdirectories {
    my $conf = config_hash();

    my $dirs = $conf->{camp_subdirectories};
    ref($dirs) eq 'ARRAY' and @$dirs or return 1;

    -d $conf->{path} or die "Error in camp_subdirectories: main camp path '$conf->{path}' doesn't exist\n";

    my $cwd = pushd($conf->{path}) or die "Couldn't chdir $conf->{path}: $!\n";

    return File::Path::mkpath(@$dirs, { verbose => 1 });
}

sub copy_paths_config_path {
    return File::Spec->catfile( type_path(), 'copy-paths.yml' );
}

=pod

=head1 COPY PATHS CONFIGURATION

Your camp type may specify arbitrary paths that should be copied/symlinked into camp instances
via the copy-paths.yml file.  As the extension suggests, this is expected to be a YAML file.

The structure of the file is as follows:

=over

=item *

Each path to copy (file or directory, it matters not) gets a "document" within the YAML structure.
This essentially means that you start each path's entry with the standard "---" YAML document
header.  The result of this is that Camp::Master sees the path entries as an array.

=item *

Each path entry is a hash.  Each path hash B<must> provide the following key/value pairs:

=over

=item I<source>

The source path to copy from.  This can be relative to the camp type path, or absolute.

=item I<target>

The target path to copy to.  This is always relative to the camp instance base.

=back

In addition, the following optional items may be provided:

=over

=item I<default_link>

If provided with a Perly true value (non-blank, non-zero), the I<target> will be created
as a symlink to I<source> rather than a full copy.  This is sensible for large docroots,
image directories, etc.

If left unspecified for a given path, this effectively defaults to false.

=item I<always>

If provided with a Perly true value (non-blank, non-zero), the default behavior determined
by I<default_link> is always used and the camp creator isn't given a choice in the matter.

=item I<exclude>

May be provided with a single scalar entry or an array of such entries; each should
correspond to an rsync/tar-style "--exclude" pattern, which will be provided to the
rsync call that performs the copy.  This naturally only comes into play if copying the
source rather than symlinking.

=item I<parse_source>

If provided with a Perly true value, the source path will be parsed for camp configuration
tokens (see CAMP CONFIGURATION VARIABLES).  If not specified, parsing does not occur.

=item I<parse_target>

If provided with a Perly true value, the target path will be parsed for camp configuration
tokens (see CAMP CONFIGURATION VARIABLES).  If not specified, parsing does not occur.

=item I<allow_errors>

If provided with a Perly true value, rsync errors will be ignored. Otherwise, rsync errors
are fatal and abort the mkcamp process.

=item I<remote_source>

If provided will assume that the source location is on a remote server. Value should be
the protocol used to connect to the remote location, 'ssh' is the only valid value at
the moment.

=back

Because the YAML stream is converted to an array, the paths are processed in order of specification
within the stream.  Therefore, you can have dependencies between paths and they'll work out as
long as you arrange them in the proper order in the file.

When a new camp instance is created, each path is processed in order.  Per path, the camp creator is
offered the opportunity to specify whether the camp should receive a full copy or a symlink of the
source path in question; the default response will be noted based on the I<default_link> setting
for that path.  However, if the I<always> option is set for the path, the user is not given the
choice and the default simple happens automatically.

Here's an example of a file:

 # The /var/www/html docroot will be symlinked to $camp/htdocs by default,
 # but the user is given the choice to override with a copy.
 ---
 source: /var/www/html
 target: htdocs
 default_link: 1
 # The /var/cgi-bin/foo.com script directory will by copied (since no default_link
 # is specified) by default to $camp/cgi-bin.  The user is given the choice to
 # symlink instead.
 ---
 source: /var/cgi-bin/foo.com
 target: cgi-bin
 # The /var/www/image_repository is symlinked to $camp/image_repository; the user
 # is not given a choice about this, because always is set.
 ---
 source: /var/www/image_repository
 target: image_repository
 default_link: 1
 always: 1
 ---
 source: remote@endpoint.com:/var/www/image_repository
 target: image_repository
 default_link: 1
 always: 1
 allow_errors: 1
 remote_source: ssh

=back

=cut

sub process_copy_paths {
    my ($defaults_only) = @_;
    my $conf = config_hash();
    my $file = copy_paths_config_path();
    if (! -f $file) {
        print "No copy-paths file to process.\n";
        return;
    }
    use_yaml();
    my @data = parse_yaml( $file );
    if (! @data) {
        print "No copy-paths entries found in copy-paths file.\n";
        return;
    }

    die "The copy-paths data structures are invalid; only hashes are allowed within the array!\n"
        if grep {
            !( ref($_) eq 'HASH'
            and defined($_->{source})
            and defined($_->{target}) )
        } @data;

    for my $copy (@data) {
        my $link = defined($copy->{default_link}) && $copy->{default_link};

        my $src = $copy->{source};
        $src = substitute_hash_tokens($src, $conf) if $copy->{parse_source};
        my $src_trail;
        $src_trail++ if $src =~ m{/$};
        $src = File::Spec->catfile( type_path(), $src )
            if ! File::Spec->file_name_is_absolute($src) && ! defined $copy->{remote_source};
        $src .= '/' if $src_trail and $src !~ m{/$};

        my $target = $copy->{target};
        $target = substitute_hash_tokens($target, $conf) if $copy->{parse_target};
        my $target_trail;
        $target_trail++ if $target =~ m{/$};
        $target = File::Spec->catfile( $conf->{path}, $target );
        $target .= '/' if $target_trail and $target !~ m{/$};

        if (!$defaults_only and !( defined($copy->{always}) && $copy->{always} )) {
            my ($decision, $flag);
            while (!defined($decision) or !($decision =~ s/^\s*([yn]?)\s*$/$1/i)) {
                printf "Do you want to copy $src to $target (if no, symlinks are used)? y/n (%s) ", $link ? 'n' : 'y';
                $decision = <STDIN>;
                chomp $decision;
            }
            $link = lc($decision) eq 'n' if $decision;
        }
        if ($link) {
            print "Symlinking $target to $src.\n";
            if (-e $target) {
                print "NOTE: $target already exists; no symlink will be added; skipping!\n";
                next;
            }
            symlink($src, $target) or die "Failed to symlink: $!\n";
        }
        else {
            print "Rsyncing $src to $target.\n";
            if (-l $target) {
                print "WARNING: $target already exists and is a symlink; skipping!\n";
                next;
            }
            my @exclude;
            if (defined $copy->{exclude}) {
                my $ref = ref($copy->{exclude});
                if (!$ref) {
                    @exclude = ($copy->{exclude});
                }
                elsif ($ref eq 'ARRAY') {
                    @exclude = @{$copy->{exclude}};
                }
                else {
                    die "The 'exclude' entry must be a simple scalar or an array.\n";
                }
            }
            unshift @exclude, vcs_exclude_patterns();
            my $exclude_args = join ' ', map { "--exclude='$_'" } @exclude;

            my $cmd_string = 'rsync';
            if (defined $copy->{remote_source}) {
                if ($copy->{remote_source} eq 'ssh') {
                    $cmd_string .= " -e $copy->{remote_source}";
                }
                else {
                    die "Unrecognized remote source type: $copy->{remote_source}\n";
                }
            }
            $cmd_string .= qq{ --stats -a --delete $exclude_args $src $target};

            my $do_system = ($copy->{allow_errors} ? \&do_system_soft : \&do_system);
            $do_system->($cmd_string);
        }
    }
    return @data;
}

sub db_path {
    return _db_type_dispatcher( '_db_path' )->(@_);
}

sub _db_path_pg {
    return pgsql_path(@_);
}

sub _db_path_mysql {
    return mysql_path(@_);
}

sub pgsql_path {
    return File::Spec->catfile( type_path(), 'pgsql', );
}

sub mysql_path {
    return File::Spec->catfile( type_path(), 'mysql', );
}

sub roles_path {
    return File::Spec->catfile( db_path(), 'roles', );
}

sub db_config_path {
    return _db_type_dispatcher( 'db_config_path' )->(@_);
}

sub db_config_path_pg {
    -f $_ && return($_)
        for map { File::Spec->catfile( $_, 'postgresql.conf', ) } (
                db_path(),
                File::Spec->catfile( base_path(), 'pgsql', ),
            )
    ;
    die "Cannot locate pgsql/postgresql.conf in type definition or base camp user!\n";
}

sub db_config_path_mysql {
    -f $_ && return($_)
        for map { File::Spec->catfile( $_, 'my.cnf' ) } (
                db_path(),
                File::Spec->catfile( base_path(), 'mysql', ),
            )
    ;
    die "Cannot locate mysql/my.cnf in type definition or base camp user!\n";
}

sub has_app {
    die "Cannot call has_app() until package has been initialized!\n" unless $initialized;
    my $conf = config_hash();
    return $has_app if defined $has_app;
    return $has_app = (grep { defined and /\S/ } map { $conf->{"app_$_"} } qw( init start stop )) ? 1 : 0;
}

sub has_rails {
    die "Cannot call has_rails() until package has been initialized!\n" unless $initialized;
    return $has_rails if defined $has_rails;
    return $has_rails = (grep m!^rails/[-\w]+/config/mongrel_cluster.yml$!, @edits,) ? 1 : 0;
}

sub has_ic {
    die "Cannot call has_ic() until package has been initialized!\n" unless $initialized;
    return $has_ic if defined $has_ic;
    return $has_ic = $edits{'interchange/bin/interchange'} || $edits{'local/bin/interchange'} ? 1 : 0;
}

sub base_user_path {
    return base_user()->dir();
}

sub base_user {
    die "No base user specified!\n" unless defined $base_camp_user and $base_camp_user =~ /\S/;
    return $base_user_obj ||= getpwnam( $base_camp_user );
}

sub dbh {
    return $dbh if defined $dbh and $dbh->ping;
    my %settings = camp_db_config();
    my ($dsn, $user, $pass) = @settings{qw( dsn user password )};
    die "Must specify a DSN and user to access camp database!\n"
        unless defined $dsn and defined $user
    ;
    local $ENV{PGPORT};
    $dbh = DBI->connect(
        $dsn,
        $user,
        $pass,
        {
            RaiseError => 1,
            AutoCommit => 1,
        },
    );
    return $dbh;
}

sub set_camp_user {
    my ($user_id) = @_;
    die "A user name or UID must be provided for set_camp_user()!\n"
        unless defined $user_id and $user_id =~ /\S/
    ;
    if ($user_id =~ /^\d+$/) {
        # by UID
        $camp_user_obj = getpwuid( $user_id );
    }
    else {
        # by name
        $camp_user_obj = getpwnam( $user_id );
    }
    die "No user found by name/UID '$user_id'!\n"
        unless $camp_user_obj
    ;
    $camp_user = $camp_user_obj->name;
    $camp_user_info = set_camp_user_info( $camp_user );
    return;
}

sub set_camp_user_info {
    my $user = shift;
    my $row = dbh()->selectrow_hashref('SELECT name AS admin_name, email AS admin_email FROM camp_users WHERE username = ?', undef, $user,);
    die "admin '$user' is unknown; aborting!\n"
        unless ref($row) and $row->{admin_name}
    ;
    $row->{system_user} = $user;
    return $row;
}

sub get_camp_info {
    my $camp = shift;
    my $row = dbh()->selectrow_hashref('SELECT * FROM camps WHERE camp_number = ?', undef, $camp,);
    die "Camp '$camp' is unknown!\n"
        unless ref($row) and $row->{camp_type} and $row->{vcs_type};
    return $row;
}

sub get_all_camp_info {
    my $username = shift;
    my $dbh = dbh();
    my $sth;
    my $out = '';
    if ($username) {
        $out = "Camp #\tCamp Type\tCamp Creation Date\t\tComment\n";
        $sth = $dbh->prepare('SELECT * FROM camps WHERE username = ? ORDER BY camp_number');
        $sth->execute($username);
    }
    else {
        $out = "Camp #\tUsername\tCamp Type\tCamp Creation Date\t\tComment\n";
        $sth = $dbh->prepare('SELECT * FROM camps ORDER BY camp_number');
        $sth->execute();
    }

    my @rows;
    my $username_maxlen = 0;
    while ( my $row = $sth->fetchrow_hashref() ) {
        $username_maxlen = length($row->{username})  if ($row->{username} && length($row->{username}) > $username_maxlen);
        push @rows, $row;
    }
    $sth->finish();
    my $fmt = ($username) ? "   %s\t%s\t\t%s\t\t%s\n" : "   %s\t%-${username_maxlen}s\t%s\t\t%s\t\t%s\n";
    my @fields = ($username) ? qw/camp_number camp_type create_date comment/ : qw/camp_number username camp_type create_date comment/;
    for my $r (@rows) {
        $out .= sprintf($fmt, @{$r}{@fields});
    }
    return $out;
}

sub set_camp_comment {
    my ($number, $comment) = @_;
    dbh()->do('UPDATE camps SET comment = ? WHERE camp_number = ?', undef, $comment, $number);
    return;
}

sub camp_user {
    die "No camp user set!\n"
        unless defined $camp_user_obj
    ;
    return $camp_user;
}

sub camp_user_obj {
    die "No camp user object set!\n"
        unless defined $camp_user_obj
    ;
    return $camp_user_obj;
}

sub camp_user_info {
    die "No camp user info set!\n"
        unless defined $camp_user_info
    ;
    return $camp_user_info;
}

sub camp_user_tmpdir {
    my $dir = File::Spec->catfile(camp_user_obj()->dir(), 'tmp');
    -d $dir
        or mkpath($dir)
        or die "camp_user_tmpdir '$dir' didn't exist and couldn't be created\n";
    return $dir;
}

sub _camp_db_type_dispatcher {
    my $name = shift;
    my $config = config_hash();
    my $type   = $config->{db_type};
    my $sub = __PACKAGE__->can( "${name}_$type" );
    die "No function $name for database type $type!\n" unless $sub;
    return $sub;
}

sub _db_type_dispatcher {
    my $name = shift;
    my $type;
    if ($conf_hash) {
        $type = $conf_hash->{db_type};
    }
    else {
        $type = camp_db_type();
    }
    my $sub = __PACKAGE__->can( "${name}_$type" );
    die "No function $name for database type $type!\n" unless $sub;
    return $sub;
}

sub get_next_camp_number {
    return _db_type_dispatcher( '_get_next_camp_number' )->( @_ );
}

sub _get_next_camp_number_pg {
    my $db = dbh();
    my $sth_chk = $db->prepare(q{SELECT camp_number FROM camps WHERE camp_number = ?});
    my ($count, $camp,);
    while (++$count <= 100) {
        my ($number) = $db->selectrow_array(q{SELECT nextval('camp_number')});
        $sth_chk->execute( $number );
        return $number unless $sth_chk->fetch;
    }
    die "Infinite loop while fetching camp number!\n";
}

sub _get_next_camp_number_mysql {
    my $db = dbh();
    my ($id) = $db->selectrow_array(<<'SQL');
SELECT MIN( cn.number )
FROM camp_numbers cn
LEFT JOIN camps c
    ON cn.number = c.camp_number
WHERE c.camp_number IS NULL
SQL
    return $id;
}

sub substitute_hash_tokens {
    my ($string, $hash, $prefix) = @_;
    $prefix = defined($prefix) ? $prefix : 'CAMP';
    # substitute tokens, longest tokens first since short ones could be substrings
    for my $key (sort { length($b) <=> length($a) } keys %$hash) {
        my $val = $hash->{$key};
        my $token = uc( length($prefix) ? "${prefix}_$key" : $key );
        $string =~ s/__${token}__/$val/g;
    }
    return $string;
}

sub _config_hash_db {
    my ($hash, $camp_number) = @_;
    return if $hash->{skip_db};
    _determine_db_type_and_path( $hash ) or die "Failed to determine database type!\n";
    return if $hash->{db_type} eq 'none';

    if ($hash->{db_type} =~ /^(?:pg|mysql)$/) {
        $hash->{db_host}       = 'localhost';
        $hash->{db_port}       = 8900 + $camp_number;
        $hash->{db_encoding}   = 'UTF-8',
        $hash->{db_data}       = File::Spec->catfile( $hash->{db_path}, 'data' );
        $hash->{db_tmpdir}     = File::Spec->catfile( $hash->{db_path}, 'tmp' );
    }
    else {
        die "Unknown database type!\n";
    }

    if ($hash->{db_type} eq 'pg') {
        $hash->{db_log}        = File::Spec->catfile( $hash->{db_tmpdir}, 'postgresql.log', );
        $hash->{db_conf}       = File::Spec->catfile( $hash->{db_data}, 'postgresql.conf', );
    }
    elsif ($hash->{db_type} eq 'mysql') {
        $hash->{db_log}        = File::Spec->catfile( $hash->{db_tmpdir}, 'mysql.log', );
        $hash->{db_conf}       = File::Spec->catfile( $hash->{path}, 'my.cnf', );
        $hash->{db_socket}     = File::Spec->catfile( $hash->{db_tmpdir}, "mysql.$camp_number.sock" );
    }

    return;
}

sub _determine_db_type_and_path {
    my $conf = shift;
    my %paths = qw(
        pgsql   pg
        mysql   mysql
    );

    my @found = grep { -d File::Spec->catfile( type_path(), $_ ) } keys %paths;
    return $conf->{db_type} = 'none' if !@found;
    die "Found more than one database type; only one may be used!\n"
        if @found > 1;
    $conf->{db_path} = File::Spec->catfile( $conf->{path}, $found[0] );
    $conf->{db_type} = $paths{$found[0]};
    return $conf->{db_type};
}

=pod

=head1 CAMP CONFIGURATION VARIABLES

Camp configuration occurs at two levels:

=over

=item Base camp level

Configuration information provided at the B<$camp_base> trickles down to all
camp types underneath that base.

=item Camp type level

Each camp type has a subdirectory under the B<$camp_base>, and configuration
information provided at this level applies only to the camp type in question,
overriding any conflicting settings coming in from the base camp level.

=back

The configuration information is parsed at the base camp level first, then the
type-specific level second.

In each level, the B<local-config> file is processed.  This is expected to
consist of key/value pairs of the form:

 some_key:some_value

Empty lines and lines starting with the pound character are ignored, meaning
that you can embed comments in your configuration files.

All values specified in these files undergo token substitution, such that
any configuration variable can be substituted into a value by using the
token:

 __CAMP_VARIABLENAME__

For instance, if the B<local-config> file has a line:

 my_variable:some_useless_value

then a subsequent line:

 other_variable:__CAMP_MY_VARIABLE__foo

will result in the "my_variable" key having value "some_useless_valuefoo".

These variables are used both by Camp::Master itself, and in the various templates
that Camp::Master renders at camp creation time; the token substitution logic is
the same in each case.  This allows your template files to undergo rendering and
have camp-specific information substituted in, localing the file to the camp being
created (which is the entire point of the camp system).

Prior to parsing the base level and camp level configuration files, a number
of configuration entries are determined automatically by Camp::Master.

=over

=item base_path

The B<$camp_base> (defaults to /home/camp)

=item type_path

The path to the camp type's directory under B<$camp_base>.

=item type

The type of camp.

=item root

The camp owner's home directory path.

=item path

The local path of the camp being operated upon (for instance, /home/some_user/camp16)

=item number

The camp number

=item name

The camp's name (for instance, "camp23")

=item docroot

The Apache docroot for the camp.

=item http_port

The custom port the camp will use for HTTP traffic.

=item https_port

The custom port the camp will use for HTTPS traffic.

=item httpd_path

The camp-specific directory where Apache configuration and log files will go.

=item httpd_lib_path

The path to the Apache modules that must be referenced when launching camp Apache.

Defaults to /usr/lib/httpd.

=item httpd_cmd_path

The path to the Apache executable for controlling the Apache server.

Defaults to /usr/sbin/httpd.

=item httpd_define

A space-separated list of parameter names that should be defined for Apache at startup time (via -D on the command line). These can be tested for in Apache configuration with the IfDefine parameter. See L<http://httpd.apache.org/docs/2.2/mod/core.html#ifdefine> for details.

=item httpd_specify_conf

Specify location of configuration file under "httpd_path" and include that in command strings.

For example, "conf/apache2.conf", used when executable has been compiled with a specific full path. To detect need for this option see httpd -V output and check for "SERVER_CONFIG_FILE" with a value similar to "/etc/apache2/apache2.conf" (any path beginning with "/").

=item skip_apache

A boolean (0/1) setting that determines whether to skip Apache-specific httpd server setup, for example when using nginx.

=item httpd_start

When setting skip_apache, set this to the command to start your webserver. An example with nginx:

 /usr/sbin/nginx -c __CAMP_PATH__/nginx/nginx.conf

=item httpd_stop

When setting skip_apache, set this to the command to stop your webserver. An example with nginx:

 pid=`cat __CAMP_PATH__/var/run/nginx.pid 2>/dev/null` && kill $pid

=item httpd_restart

pid=`cat __CAMP_PATH__/var/run/nginx.pid 2>/dev/null` && kill -HUP $pid || /usr/sbin/nginx -c __CAMP_PATH__/nginx/nginx.conf

=item skip_ssl_cert_gen

A boolean (0/1) setting that determines whether to skip generation of a self-signed SSL certificate for the HTTP server.

Default is 0 (false).

=item icroot (I<Interchange only>)

The main interchange directory within the camp.

=item cgidir (I<Interchange only>)

The path where the interchange linker programs should reside; defaults to cgi-bin
under the camp's path.

=item catroot (I<Interchange only>)

The main path for your Interchange catalog; requires that the I<catalog> variable
be provided in your configuration file.

Defaults to I<path> + '/catalogs/' + I<catalog>.

=item ic_socket (I<Interchange only>)

The path where the Interchange socket file will reside

Defaults to I<icroot> + '/var/run/socket'

=item railsdir (I<Rails only>)

The path where rails will live within the camp; defaults to "rails" under the camp's path.

=item mongrel_base_port (I<Rails only>)

The lowest port to be used by the Mongrel cluster for balancing Rails children

=item proxy_name (I<Rails only>)

The ProxyBalancer name used for the Mongrel listeners within the camp Apache.

=item proxy_balance_members (I<Rails only>)

Rendered Apache ProxyBalancer member configuration directives suitable for placement
directly within a virtualhost's <Proxy balancer://...>...</Proxy> container.  Defaults
to using three mongrel listeners with ports incremented by one starting at the
mongrel_base_port.

=item app_init

When using an application server other than those natively supported in camps, set this to the command to initialize your application server. This will run only once during camp creation. For example (using a custom init script):

 __CAMP_PATH__/bin/init-magento

=item app_start

When using an application server other than those natively supported in camps, set this to the command to start your application server. For example (using a custom startup script):

 __CAMP_PATH__/bin/start-unicorn

=item app_stop

Command to stop your application server. An example for Ruby's Unicorn:

 pid=`cat __CAMP_PATH__/var/run/unicorn.pid 2>/dev/null` && kill $pid

=item app_restart

Command to restart your application server. An example for Ruby's Unicorn:

 pid=`cat __CAMP_PATH__/var/run/unicorn.pid 2>/dev/null` && kill -HUP $pid || __CAMP_PATH__/bin/start-unicorn

=item post_mkcamp_command

Command to be run after the mkcamp process is completed.

=item db_type

The type of database server used for the camp; will be either 'pg' for Postgres or 'mysql'
for MySQL.

The database type is determined by the subdirectories within the camp type path; the camp
type path must have either a pgsql directory or a mysql directory (for pg or mysql, respectively).

=item db_path

The main database path for the camp's database server; dependent on the database type,
will be either 'pgsql' or 'mysql' for Postgres and MySQL respectively.

=item db_host

The database hostname; defaults to 'localhost'.

=item db_port

The custom port to use for your camp's database server.  Defaults to 8900 + camp number.

=item db_encoding

The encoding to use when initializing the database cluster.  Defaults to UTF-8.

=item db_data

The directory where the camp's database is expected to store binary data.  Defaults to
db_path + '/data'.

=item db_tmpdir

A temporary directory for varying, ephemeral data like logs, pids, etc., specific for
the camp's database server.  Defaults to db_path + '/tmp'.

=item db_log

The base database server logfile path; for Postgres, this is in fact the logfile to be
used; MySQL uses multiple logging paths ordinarily, so it can be used as a prefix for a full
path with MySQL (it probably could be used for all logging too).

Defaults:

=over

=item I<Pg>

db_tmpdir + 'postgresql.log'

=item I<MySQL>

db_tmpdir + 'mysql.log'

=back

=item db_conf

The database server configuration file within the camp.

Defaults:

=over

=item I<Pg>

db_data + 'postgresql.conf'

=item I<MySQL>

db_path + 'my.cnf'

=back

=item db_socket (I<MySQL only>)

Path for the camp's database server UNIX socket.  Defaults to db_tmpdir + 'mysql.$camp_number.sock'

=back

All of the above variables are calculated for you.  This calculation is one of the first things performed
by Camp::Master; therefore, they can be safely overridden in your base or type configuration files as
appropriate for your camp deployment.

A few variables B<must be provided> by your configuration files in order for the camp system to function
properly:

=over

=item db_source_scripts

Space-separated list of paths to SQL files that should be run upon preparing a camp's database server.
You may specify as many as you need, but at least one should be provided.

The paths may be absolute or relative; if relative, they are expected to be relative to the camp type's
directory.

Each script specified in the space-separated list is run within its own db client shell; they are executed
in order of specification.  No assumptions are made for transaction handling; if you want transactions,
put them in the scripts themselves.

It's important to know the context in which these run, which differs between database server types due to
fundamental structural differences between those servers and how they organize things:

=over

=item I<Postgres>

In Postgres, each script is run via a connection to the "postgres" user's "postgres" database.  Therefore,
your scripts need to provide I<\connect> information in order to make changes against a different database.

=item I<MySQL>

In MySQL, the scripts connect using the db_default_database and db_default_user variables, which effectively
makes these variables required for MySQL deployments.

=back

=item db_source_scripts_parse

Scripts listed in C<db_source_scripts> are normally processed verbatim. List again here any scripts
here that you would like to first have preprocessed with variable token substitution. This is useful
if, for example, you would like to reference the camp number or camp owner's name in the script.

The paths should be specified identically to how they're listed in C<db_source_scripts> or they will not
be tokenized.

=item db_mysql_scripts (I<MySQL only>)

Space-separated list of paths to SQL files that should be run upon preparing a camp's MySQL database server,
prior to processing the roles for that database; this gives an opportunity to initialize the database to
a known set of users/permissions, for instance, or initalize things in other ways needed prior to role
creation.

=item db_sleep_time

Allows specification of a number of seconds to sleep between starting the database server at camp creation
time and processing the roles and I<db_source_scripts>; necessary for UNIX socket connections in which the
server needs a few seconds to start up and initialize its socket file.

Sane values appear to be in the 5-15 second range.  Defaults to 5 seconds; set to 0 or blank to turn off.

=item db_dbnames

Space-separated list of database names that are expected to live within your camp's database server.

This was formerly used to set up Postgres password access to each
database in your user account's .pgpass file, but now each database
user's password is applied to all databases ("*") there. It is still up
to you to configure Postgres to allow appropriate access.

=item camp_subdirectories

A space-separated list of directories that are expected to reside under your camp (naturally, these paths
are expected to be relative to the camp directory itself).  These directories will be cleared out if
you rebuild an existing camp (with the mkcamp script), which is the main reason they need to be provided
to Camp::Master.

=item catalog_linker_filenames (I<Interchange only>)

Space-separated list of filenames that need to be put in place within your camp as Apache/Interchange
linker programs.  Specify at least one for your main catalog.

=item catalog (I<Interchange only>)

The name of the catalog for your camp's Interchange deployment.  Specify one, even if you have multiple
catalogs; the I<catroot> variable is set based on this.  For the majority of End Point Interchange
deployments, multiple catalogs are a non-issue.

=back

Some optional variables may also be provided to affect the functioning of your camp deployment:

=over

=item db_locale (I<postgres only>)

The locale to use when initializing the database cluster.  There is no default, meaning that
the cluster would by default initialize to whatever locale Postgres itself uses as the default.

=item db_default_database

The default database to use when connecting to your database via its respective camp DB client
wrapper (I<psql_camp> or I<mysql_camp>).  Also determines the database used for I<db_source_scripts>
import on MySQL.

=item db_default_user

The default user to use when connecting to your database via its respective camp DB client
wrapper (I<psql_camp> or I<mysql_camp>).  Also determines the user used for I<db_source_scripts>
import on MySQL.

=item db_pg_ssl_active (I<postgres only>)

Boolean used to indicate that Postgres instance has SSL activated and therefore a certificate should be generated. Default: off.

=item db_pg_ssl_C (I<postgres only>)

The country to use for your camp's Postgres SSL certificate (defaults to value of ssl_C).

=item db_pg_ssl_ST (I<postgres only>)

The statename to use for your camp's Postgres SSL certificate (defaults to value of ssl_ST).

=item db_pg_ssl_L (I<postgres only>)

The locality to use for your camp's Postgres SSL certificate (defaults to value of ssl_L).

=item db_pg_ssl_O (I<postgres only>)

The organization name to use for your camp's Postgres SSL certificate (defaults to value of ssl_O).

=item ssl_C

The country to use for your camp's SSL certificate (defaults to US).

=item ssl_ST

The statename to use for your camp's SSL certificate (defaults to 'New York').

=item ssl_L

The locality to use for your camp's SSL certificate (defaults to 'New York').

=item ssl_O

The organization name to use for your camp's SSL certificate (defaults to 'End Point Corporation').

=item vcs_default_type

Specifies the default version control system to use for the camp type. This is optional, but is
certainly highly convenient for camp users and makes things easier to manage. The main reason to
use a different version control system would be for using git-svn in a camp against a Subversion
repository.

If this is set for a camp type, then it is not necessary for a user to specify their VCS type
when creating an instance of that camp.  The value of I<vcs_default_type> has no bearing on existing
camps; each extant camp's original VCS type is recorded in the camp database and will not change
without heroic efforts on the part of the camp's owner.

=item repo_path

Use this to specify the SCM repository path.  This is not specific to VCS type and has been preserved
for legacy purposes.  SVN and Git repository paths can be specified in type-specific manner using
I<repo_path_svn> and I<repo_path_git>, respectively; when those are used, they override the
I<repo_path> value.

There is no default value for I<repo_path>, so don't count on it being present in your code
unless you are quite sure of what you're doing.

=item repo_path_svn

Use this to specify the main project Subversion repository path; is is assumed that it will be
accessed via the "file://" protocol, meaning that you need only provide the path to the repository (and
any subdirectories within that repository).

When determining the Subversion repository location, B<Camp::Master> consults, in this order:

=over

=item *

I<repo_path_svn>

=item *

I<repo_path>

=item *

Default: I<type_path> . '/svnrepo/trunk'

=back

There is no default value for I<repo_path_svn>, however, so do not count on this being available for
token substitution unless you explicitly set it in the relevant local-config.  The default repository
location described above is enforced through logic, but not within the master configuration hash.

=item repo_path_git

Use this to specify the main project Git repository path; no assumptions about the path/URL are
made, so you are free to specify a file path (which is most likely as of this writing), a git://*
URL, an rsync://* URL, etc.

Similar to determination of Subversion repository location, B<Camp::Master> consults the following
items in order when finding a camp type's Git repository location:

=over

=item *

I<repo_path_git>

=item *

I<repo_path>

=item *

Default: I<type_path> . '/repo.git'

=back

There is no default value for I<repo_path_git>, so you cannot count on its presence unless you
know what you're doing and are working with a camp type that definitely specifies a value for it.

=item git_clone_options

Options to pass literally to the "git clone ..." call when building a new camp and cloning from
the source Git repo.  See the "git-clone" man pages for valid options.  There is no default,
meaning that the effective default behavior is invoking git-clone without options.

Git is efficient in its use of disk space, but by using the various options like local, shared,
or reference can potentially be even more efficient and speedy.

=item git_branch

Specifies a branch to track and checkout after cloning.  Use this in the case that your Git
repository's active branch differs from the branch the camp type needs to work with.  This would
likely be the case if you're using a single master Git repository to track several lines of
development; one camp type would work with the default branch "master", while other camp types
would need to specify alternate branches.

This assumes that you're using a remote name of "origin".  Since I<git_clone_options> allows you
to specify a different name for your clone, I<git_branch> introduces some extra semantics: if
the value of I<git_branch> contains a forward slash ("/"), the word characters preceding the first
slash are treated as the remote name.

If you use I<git_clone_options> "-o foo" to specify a remote name of "foo" rather than "origin",
you can have your camp type check out branch "bar" via I<git_branch> of "foo/bar".  However, if
you're using the default clone remote name of "origin", then I<git_branch> "bar" would suffice to
checkout branch "bar".

This also means that if the desired branch has forward slashes in the name, you'll need to include
the remote name as the first portion of your I<git_branch> value.  So, if you want a branch named
"releases/1.1", you would need a I<git_branch> value of "origin/releases/1.1".

=back

=cut

sub config_hash {
    if (! defined $conf_hash) {
        my $camp_number = shift;
        die "Must provide a camp number for initialization of config_hash()!\n"
            unless defined $camp_number and $camp_number =~ /^\d+$/;
        $conf_hash = {
            %{ camp_user_info() },
            number      => $camp_number,
            '0number'   => sprintf('%02d',$camp_number),
            name        => "camp$camp_number",
            root        => camp_user_obj()->dir(),
            type        => type(),
            type_path   => type_path(),
            base_path   => base_path(),
        };
        $conf_hash->{path} = File::Spec->catfile( $conf_hash->{root}, $conf_hash->{name} );
        if (has_ic()) {
            $conf_hash->{icroot} = File::Spec->catfile($conf_hash->{path}, 'interchange');
            $conf_hash->{cgidir} = File::Spec->catfile($conf_hash->{path}, 'cgi-bin');
            $conf_hash->{ic_socket} = File::Spec->catfile($conf_hash->{icroot}, 'var/run/socket');
        }
        $conf_hash->{docroot}   = File::Spec->catfile($conf_hash->{path}, 'htdocs');
        if (has_rails()) {
            $conf_hash->{railsdir}  = File::Spec->catfile($conf_hash->{path}, 'rails');
            $conf_hash->{mongrel_base_port} = 5 * $camp_number + 9200;
            $conf_hash->{proxy_name} = "camp_${camp_number}_mongrel_proxy";
            $conf_hash->{proxy_balance_members} = join(
                "\n\t",
                map {
                    my $port = $conf_hash->{mongrel_base_port} + $_;
                    "BalancerMember http://127.0.0.1:$port";
                }
                (0..4)
            );
        }

        _config_hash_db( $conf_hash, $camp_number );

        $conf_hash->{httpd_path}    = File::Spec->catfile($conf_hash->{path}, 'httpd');
        $conf_hash->{httpd_lib_path}    = '/usr/lib/httpd/modules';
        $conf_hash->{httpd_cmd_path}    = '/usr/sbin/httpd';
        $conf_hash->{http_port}     = 9000 + $camp_number;
        $conf_hash->{https_port}    = 9100 + $camp_number;
        for my $conf_file (
            map { File::Spec->catfile($_, 'local-config') } base_path(), type_path()
        ) {
            next unless -f $conf_file;
            open(my $CONF, '<', $conf_file) or die "Couldn't open configuration file $conf_file: $!\n";
            while (my $line = <$CONF>) {
                chomp($line);
                next unless $line =~ /\S/;
                next if $line =~ /^\s*#/;
                if (my ($key,$val) = $line =~ /^\s*(\w+):(.*?)\s*$/) {
                    $conf_hash->{$key} = substitute_hash_tokens($val, $conf_hash);
                }
                else {
                    warn "Skipping invalid line in file $conf_file: $line\n";
                    next;
                }
            }
            close $CONF or die "Error closing $conf_file: $!\n";
        }
        die "Must specify a hostname within your base camp or type local-config!\n"
            unless defined $conf_hash->{hostname} and $conf_hash->{hostname} =~ /\S/;
        die "Must specify the camp directory list within your base camp or type local-config!\n"
            unless defined $conf_hash->{camp_subdirectories}
                and $conf_hash->{camp_subdirectories} =~ /\S/;
        $conf_hash->{camp_subdirectories} = [
            split /[\s,]+/, $conf_hash->{camp_subdirectories}
        ];
        $conf_hash->{db_source_scripts} = [
            split /[\s,]+/, $conf_hash->{db_source_scripts} || ''
        ];
        $conf_hash->{db_source_scripts_parse} = {
            map { $_ => 1 } (split /[\s,]+/, $conf_hash->{db_source_scripts_parse} || '')
        };
        $conf_hash->{db_dbnames} = [
            split /[\s,]+/, $conf_hash->{db_dbnames} || ''
        ];

        $conf_hash->{db_mysql_scripts} = [
            split /[\s,]+/, $conf_hash->{db_mysql_scripts} || ''
        ] if $conf_hash->{db_type} eq 'mysql';

        if (has_ic()) {
            die "Must provide catalog linker names within base camp or type local-config!\n"
                unless defined $conf_hash->{catalog_linker_filenames}
                    and $conf_hash->{catalog_linker_filenames} =~ /\S/;
            $conf_hash->{catalog_linker_filenames} = [
                split /[\s,]+/, $conf_hash->{catalog_linker_filenames},
            ];
            $conf_hash->{catroot} ||= File::Spec->catfile($conf_hash->{path}, 'catalogs', $conf_hash->{catalog});
        }
        $conf_hash->{http_url}  = 'http://'  . $conf_hash->{hostname} . ':' . $conf_hash->{http_port}  . '/';
        $conf_hash->{https_url} = 'https://' . $conf_hash->{hostname} . ':' . $conf_hash->{https_port} . '/';

        if (!vcs_type_is_set() and defined($conf_hash->{vcs_default_type}) and $conf_hash->{vcs_default_type} =~ /\S/) {
            set_vcs_type( $conf_hash->{vcs_default_type} );
        }

        my %ssl_defaults = (
            C   => 'US',
            ST  => 'New York',
            L   => 'New York',
            O   => 'End Point Corporation',
        );

        for my $token (keys %ssl_defaults) {
            my $key = "ssl_$token";
            next if defined $conf_hash->{$key} and $conf_hash->{$key} =~ /\S/;
            $conf_hash->{$key} = $ssl_defaults{$token};
        }
    }
    return $conf_hash;
}

sub cleanup_camp_path {
    my ($camp, $replace) = @_;
    my $cfg = config_hash( $camp );
    if (-d $cfg->{path}) {
        die "Won't overwriting existing $cfg->{path} directory without replace option.\n"
            unless $replace;
        my $dir = pushd($cfg->{path}) or die "Couldn't chdir $cfg->{path}: $!\n";
        # rmtree will fail on write-protected .svn directories; remove these with a find operation
        -d $_ && do_system(sprintf('find %s %s',  $_, q(-name '.svn' -type d -prune -exec rm -rf '{}' \\;)))
            for @{$cfg->{camp_subdirectories}};
        rmtree(
            $cfg->{camp_subdirectories},
            0,
            1,
        );
    }
    return 1;
}

sub create_camp_path {
    my ($camp, $replace) = @_;
    my $cfg = config_hash( $camp );
    cleanup_camp_path($camp, $replace);
    mkpath($cfg->{path}) or die "Couldn't make camp path: $cfg->{path}: $!\n";
    return;
}

sub register_camp {
    my ($comment) = @_;
    my $conf = config_hash();
    my $sth = dbh()->prepare(<<'EOL');
INSERT INTO camps (
    camp_number,
    username,
    camp_type,
    vcs_type,
    comment,
    create_date
)
VALUES (?,?,?,?,?, CURRENT_TIMESTAMP)
EOL
    $sth->execute($conf->{number}, camp_user(), type(), vcs_type(), $comment)
        or die "Failed to register camp $conf->{number} in database!\n";
    $sth->finish;
    return;
}

sub unregister_camp {
    my ($comment) = @_;
    my $conf = config_hash();
    my $sth = dbh()->prepare(q{DELETE FROM camps WHERE camp_number = ?});
    $sth->execute($conf->{number})
        or die "Failed to unregister camp $conf->{number} in database!\n";
    $sth->finish;
    return;
}

sub resolve_camp_number {
    my $param = shift;
    my $camp;

    # look at explicit parameter
    $camp = validate_camp_number($param);
    return $camp if defined $camp;

    # look at environment
    $camp = validate_camp_number($ENV{CAMP});
    return $camp if defined $camp;

    # look at path
    getcwd() =~ m{/camp(\d+)\b} and do {
        $camp = validate_camp_number($1);
        return $camp if defined $camp;
    };

    # return nothing if we can't resolve further
    return;
}

sub validate_camp_number {
    my $number = shift;
    return $number if defined($number) and $number =~ /\A\d+\z/;
    return;
}

sub git_clone_options {
    my $options = config_hash->{git_clone_options};
    $options = '' unless defined($options) and $options =~ /\S/;
    return $options;
}

sub git_repository {
    my $hash = config_hash();
    defined($_) && /\S/ && return is_git_remote_repo($_) ? $_ : File::Spec->catfile( type_path(), $_ )
        for (
            $hash->{repo_path_git},
            $hash->{repo_path},
            'repo.git',
        );
    return;
}

sub git_branch {
    my $branch = config_hash->{git_branch};
    $branch = '' unless defined($branch) and $branch =~ /\S/;
    return $branch;
}

sub is_git_remote_repo {
    local $_ = shift;

    return m{^\w+://}       # remote protocol specification; i.e., ssh://
      ||   m{^\S+?@\S+?:.}  # user@host: default ssh-style
    ;
}

sub svn_repository {
    my $hash = config_hash();
    defined($_) && /\S/ && return File::Spec->catfile( type_path(), $_ )
        for (
            $hash->{repo_path_svn},
            $hash->{repo_path},
            'svnrepo/trunk',
        );
    return;
}

sub svn_checkout {
    my $conf = config_hash();

    return do_system(
        sprintf(
            'svn co file://%s %s',
            svn_repository(),
            $conf->{path},
        ),
    );
}

sub svn_update {
    my $conf = config_hash();

    my $path = pushd( $conf->{path} ) or die "Cannot chdir to $conf->{path}: $!\n";
    return do_system('svn up');
}

sub vcs_exclude_patterns {
    my %patterns = (
        svn => [ '**.svn**' ],
        git => [ '**.git**' ],
    );
    my $type = vcs_type();
    my $pattern = $patterns{$type} or die "No exclusion patterns found for VCS type '$type'.\n";
    return @$pattern;
}

sub vcs_checkout {
    my $replace = shift;
    my $conf = config_hash();
    my $vcs = vcs_type();

    my @cmds;

    if ($vcs eq 'svn') {
        create_camp_path($conf->{number}, $replace);
        @cmds = (
            [
                'svn co file://%s %s',
                svn_repository(),
                $conf->{path},
            ],
        );
    }
    elsif ($vcs eq 'git') {
        cleanup_camp_path($conf->{number}, $replace);
        @cmds = (
            [
                'git clone %s %s %s',
                git_clone_options(),
                git_repository(),
                $conf->{path},
            ],
        );
        if (my $branch = git_branch()) {
            my $repo = 'origin';
            if ($branch =~ s!^(\w+)/(\w.+)$!$2!) {
                $repo = $1;
            }

            push @cmds, [
                '(cd %s && git checkout --track -b %s %s/%s)',
                $conf->{path},
                $branch,
                $repo,
                $branch,
            ];
        }
        push @cmds, [
            'cd %s && git submodule init && git submodule update',
            $conf->{path},
        ];
    }
    else {
        die "Unknown version control system: $vcs\n";
    }

    do_system(sprintf($_->[0], @{$_}[1..$#$_])) for @cmds;

    return;
}

sub vcs_refresh {
    my $base = vcs_type();
    my $cmd = $base eq 'svn' ? 'up' : 'pull';
    my $dir = pushd( config_hash()->{path} );
    return do_system($base, $cmd);
}

sub vcs_remove_camp {
    # do nothing
    return;
}

sub vcs_local_refresh {
    my $vcs_type = vcs_type();
    my %map = (
        svn => 'svn up',
        git => 'git checkout',
    );
    my $cmd = $map{$vcs_type} or die "No local refresh command available for VCS type '$vcs_type'.\n";
    return do_system($cmd);
}

sub vcs_local_revert {
    # Make file paths relative, since that's what the version control systems expect
    my %files_by_path;
    for my $file (@_) {
        my ($filename, $path) = File::Basename::fileparse($file);
        push @{ $files_by_path{$path} }, $filename;
    }

    my $vcs_type = vcs_type();
    my %map = (
        svn => 'svn revert %s',
        git => 'git checkout %s',
    );
    my $cmd = $map{$vcs_type} or die "No local revert command available for VCS type '$vcs_type'.\n";

    while (my ($path, $files) = each %files_by_path) {
        my $dir = pushd($path) or die "Couldn't chdir $path: $!\n";
        my $args = join ' ', @$files;

        do_system(sprintf($cmd, $args));
    }

    return;
}

sub prepare_ic {
    return unless has_ic();
    my $conf = config_hash();
    my $file;

    # Set the main server script as executable.
    $file = "$conf->{icroot}/bin/interchange";
    if (-f $file) {
        my $current_mode = (stat $file)[2] & 07777;
        my $new_mode     = $current_mode|S_IXUSR|S_IXGRP|S_IXOTH;

        chmod $new_mode, $file or die sprintf "Can't change permissions on %s: %lo\n", $file, $new_mode;
    }

    # Prepare the CGI linker.
    $file = "$conf->{icroot}/bin/compile_link";
    if (-x $file) {
        do_system("$file -s $conf->{ic_socket} --source $conf->{icroot}/src");
        if (! -d $conf->{cgidir}) {
            mkdir $conf->{cgidir} or die "error making cgi-bin directory: $!\n";
        }
        do_system("cp -p $conf->{icroot}/src/vlink $conf->{cgidir}/$_")
            for @{$conf->{catalog_linker_filenames}};

        # use the version control system revert hardcoded changes to src/ files
        my @files = map { File::Spec->catfile($conf->{icroot}, 'src', $_) } qw( tlink.pl vlink.pl );
        vcs_local_revert(@files);
    }

    type_message('prepare_ic');
    return;
}

sub _ssl_private_key {
    for my $root_path (type_path(), base_path()) {
        my $path = File::Spec->catfile( $root_path, 'etc', 'camp.key' );
        return $path if -f $path;
    }
    die "Cannot find private key file for SSL cert creation.\n";
}

sub prepare_apache {
    my $conf = config_hash();

    unless ($conf->{skip_apache}) {
        # create empty directories
        mkpath([ map { File::Spec->catfile( $conf->{httpd_path}, $_, ) } qw( conf logs run ) ]);

        # symlink to system-wide Apache modules
        symlink $conf->{httpd_lib_path}, File::Spec->catfile($conf->{httpd_path}, 'modules')
            or die "Couldn't symlink Apache modules directory\n";
    }

    # Create SSL certificate
    unless ($conf->{skip_ssl_cert_gen}) {
        my $crt_path = File::Spec->catfile( $conf->{httpd_path}, 'conf', 'ssl.crt' );
        mkpath($crt_path);

        my $tmpfile = File::Temp->new( DIR => camp_user_tmpdir(), UNLINK => 0 );
        $tmpfile->print(<<EOF);
[ req ]
distinguished_name = req_distinguished_name
attributes         = req_attributes
prompt             = no

[ req_distinguished_name ]
C                 = $conf->{ssl_C}
ST                = $conf->{ssl_ST}
L                 = $conf->{ssl_L}
O                 = $conf->{ssl_O}
OU                = $conf->{name} for $conf->{admin_name}
CN                = $conf->{hostname}
emailAddress      = $conf->{admin_email}

[ req_attributes ]
challengePassword =
EOF
        $tmpfile->close;
        do_system(
            sprintf(
                "openssl req -new -x509 -days 3650 -key %s -out %s -config $tmpfile",
                _ssl_private_key(),
                File::Spec->catfile($crt_path, "$conf->{hostname}.crt"),
            ),
        );

        unlink($tmpfile) or die "Error unlinking $tmpfile: $!\n";
    }

    type_message('prepare_apache');
    return;
}

=pod

=head1 TEMPLATE FILE OPERATIONS

Rendering and installing arbitrary files into a camp from templates is a critical aspect of
the camp system.  Configuration files for Apache, Interchange, Rails, etc. should be reduced
to templates, with things like hostnames, file paths, port numbers, etc. replaced with
camp-system tokens of the form described in the section regarding CONFIGURATION VARIABLES.  At
camp creation time, Camp::Master will parse each template, performing token substitution,
and install each parsed template into the appropriate location within the new camp.

The files to parse are specified within the camp type subdirectory's B<camp-config-files>
file.  Specify one path per line; blanks and lines starting with the pound character are ignored.

All the files specified will undergo the described token substitution and installation into
the new camp.  The paths specified in B<camp-config-files> are expected to be relative to
the camp type directory's 'etc/' subdirectory, and also reflect the target path of the file
when copied into the new camp itself.  Thus, a file at /home/camp/some_type/etc/blah/foo.conf
would be registered in B<camp-config-files> with a path relative to etc/, or "blah/foo.conf",
and would be installed at /home/some_user/campNN/blah/foo.conf after parsing.

Also, some assumptions are made about what files will be included if your camp uses
Interchange versus Rails:

=over

=item *

If your B<camp-config-files> file specifies I<interchange/bin/interchange>, then
it is assumed to use Interchange.

=item *

If your B<camp-config-files> file specifies I<rails/.../config/mongrel_cluster.yml>, then
it is assumed to use Rails.

=back

Note that these are not mutually exclusive.  It is theoretically acceptable for a single
camp to employ both app server types.  If you are bursting with curiosity and sadly deficient
in sanity, by all means try this out.

While this can be expected to vary between deployments, a number of files are obvious candidates
for inclusion within this templating scheme:

=over

=item *

rails/.../config/database.yml

=item *

interchange/interchange_local.cfg

=item *

catalogs/.../catalog_local.cfg

=item *

httpd/conf/sites/some_site.conf

=back

Anything that relies on file paths, ports, domain names, etc. should be abstracted out into such
templates.  A common pattern (implied by interchange_local.cfg and catalog_local.cfg above) is
to encapsulate such details within "local" configuration files that are included from master configuration
files; the master configuration files can stay in version control and have no need to vary between
camps, production, etc., while the "local" configuration files are small, containing only what is absolutely
necessary, and vary in a controlled way between environments by virtue of being managed by the camp system.

=cut

sub install_templates {
    my $conf = config_hash();
    unless (defined($roles) or $conf->{skip_db}) {
        parse_roles();
    }
    my $template_path = File::Spec->catfile(type_path(), 'etc');
    local $/;
    for my $file (@edits) {
        my $source_path = File::Spec->catfile($template_path, $file);
        print "Interpolating tokenized template file '$source_path'...";
        my $mode = (stat($source_path))[2];
        open(my $INFILE, '<', $source_path) or die "Failed to open template file '$source_path': $!\n";
        my $template = <$INFILE>;
        $template = substitute_hash_tokens(
            $template,
            $conf,
        );
        close $INFILE or die "Error closing $source_path: $!\n";
        my $parent_path = my $target_path = File::Spec->catfile($conf->{path}, $file);
        $parent_path =~ s:/[^/]+$::;
        print " installing to '$target_path'.\n";
        mkpath( $parent_path );
        open(my $OUTFILE, '>', $target_path) or die "Failed writing configuration file '$target_path': $!\n";
        print $OUTFILE $template;
        close $OUTFILE or die "Error closing $target_path: $!\n";
        chmod($mode, $target_path);
    }
    type_message('install_templates');
    return;
}

sub prepare_rails {
    # not sure if anything needs to be done here, as all that really needs doing
    # should get addressed by configuration files.  So it's a no-op for now.
    return;
}

sub roles {
    parse_roles() unless defined $roles;
    return sort keys %$roles;
}

sub role_password {
    my $role = shift;
    parse_roles() unless defined $roles;
    my $role_hash = $roles->{$role};
    die "Cannot find/generate password for unknown role '$role'!\n"
        unless defined $role_hash
    ;
    if (! $role_hash->{password}) {
        my $conf = config_hash();
        $conf->{"db_role_${role}_pass"}
            = $role_hash->{password}
            = generate_nice_password();
    }
    return $role_hash->{password};
}

sub role_sql {
    my $role = shift;
    parse_roles() unless defined $roles;
    my $role_hash = $roles->{$role};
    die "Cannot find SQL for unknown role '$role'!\n"
        unless defined $role_hash;
    die "Role '$role' has no SQL statement!\n" unless $role_hash->{sql};
    return $role_hash->{parsed_sql} ||= parse_role_sql( $role_hash );
}

sub parse_roles {
    my $conf = config_hash();
    $roles = {};
    my $password_cache = role_password_cache();
    my $path = roles_path();
    opendir(my $DIR, $path) or die "Failed to open roles path '$path': $!\n";
    local $/;
    for my $role (grep /^\w+$/, readdir($DIR)) {
        open(my $ROLE, '<', File::Spec->catfile($path, $role))
            or die "Failed to open role file '$role': $!\n";
        $roles->{$role} = {
            role    => $role,
            sql     => <$ROLE>,
        };

        if (my $pw = $password_cache->{$role}) {
            $conf->{"db_role_${role}_pass"}
                = $roles->{$role}->{password}
                = $pw;
        }
        close $ROLE or die "Error closing $path: $!\n";
    }
    closedir($DIR);
    return scalar keys %$roles;
}

sub parse_role_sql {
    my $role = shift;
    my %data = (
        role => $role->{role},
        pass => role_password( $role->{role} ),
    );
    return substitute_hash_tokens($role->{sql}, \%data, '');
}

sub _prepare_database_vars {
    my ($conf, $roles, $sources, $names) = @_;
    @$roles = roles();
    @$sources = @{ $conf->{db_source_scripts} };
    @$names = @{ $conf->{db_dbnames} };

    die "There are no roles configured for this camp type!  Cannot prepare database.\n"
        unless @$roles;
    die "There are no source scripts for this camp type!  Cannot prepare database.\n"
        unless @$sources;
    die "There are no database named specified for this camp type!  Cannot prepare database.\n"
        unless @$names;
    return;
}

sub _verify_camp_path {
    my $conf = shift;
    die "Camp '$conf->{name}' does not appear to have been created; please create it first.\n"
        unless -d $conf->{path};
    return 1;
}

sub _database_exists_check {
    my ($conf, $replace) = @_;
    return 1 unless -d $conf->{db_path};
    die "Database already exists in $conf->{db_path}; must specify 'replace' to overwrite it.\n"
        unless $replace;
    _db_type_dispatcher( '_database_running_check' )->( @_ );
    # remove old database's binary data.
    rmtree($conf->{db_path}, 0, 1);
    return;
}

sub _database_running_check_pg {
    my $conf = shift;
    # check for running Postmaster on this database.
    if (system("pg_ctl status -D $conf->{db_data}") == 0) {
        # stop running postgres
        system("pg_ctl stop -D $conf->{db_data} -m fast") == 0
            or die "Error stopping running Postgres instance!\n";
    }
    return 1;
}

sub _database_running_check_mysql {
    my $conf = shift;
    # check for running MySQL on this database.
    my $opts = camp_mysql_options( user => 'root', no_database => 1, config => $conf );
    if (do_system_soft("mysqladmin $opts ping") == 0) {
        # stop running MySQL
        do_system_soft("mysqladmin $opts shutdown") == 0
            or die "Error stopping running MySQL instance!\n";
    }
    return 1;
}

sub role_password_cache {
    return _camp_db_type_dispatcher( 'role_password_cache' )->( @_ );
}

sub role_password_cache_pg {
    my %opt = @_;
    my $conf = $opt{config} || config_hash();

    my $pass_file = File::Spec->catfile( $conf->{root}, '.pgpass', );
    my $pw_cache = {};

    if (-f $pass_file) {
        open my $IN, '<', $pass_file or die "Can't read $pass_file: $!\n";
        while (<$IN>) {
            chomp;
            next if !/^$conf->{db_host}:$conf->{db_port}:/;
            my ($role,$pw) = (split /:/)[3,4];

            if ($role && $pw) {
                $pw_cache->{$role} = $pw;
            }
        }
        close $IN or die "Couldn't close $IN: $!\n";
    }

    return $pw_cache;
}

sub role_password_cache_mysql {
    my %opt = @_;
    my $conf = $opt{config} || config_hash();
    my $path = camp_mysql_settings_file($conf);

    return {} unless -f $path;

    my $settings = parse_yaml( $path );
    return $settings->{users} || {};
}

sub camp_mysql_settings_file {
    my $conf = shift;
    return File::Spec->catfile( $conf->{path}, 'mysql.yml' );
}

sub camp_mysql_options {
    my %opt = @_;
    my $conf = $opt{config} || config_hash();
    die "No configuration hash provided!\n" unless ref($conf) eq 'HASH';

    my $settings = parse_yaml( camp_mysql_settings_file($conf) );
    my @opt;
    my %merge_settings = qw(
        user default_user
        database default_database
        socket socket
        port port
        host host
    );
    for my $setting (keys %merge_settings) {
        next if defined($opt{$setting}) and length($opt{$setting});
        my $source_key = $merge_settings{$setting};
        next unless defined($settings->{$source_key}) and length($settings->{$source_key});
        $opt{$setting} = $settings->{$source_key};
    }
    delete @opt{ grep { !(defined($opt{$_}) and length($opt{$_})) } keys %opt };

    if (defined($opt{user})) {
        push @opt, "-u $opt{user}";
        my $pass = $settings->{users}->{$opt{user}};
        push @opt, "-p$pass" if defined $pass and length $pass and !$opt{no_password};
    }

    push @opt, "--socket=$opt{socket}" if defined $opt{socket};
    if (defined $opt{host} and lc($opt{host}) ne 'localhost') {
        push @opt, "-h $opt{host}";
        push @opt, "-P $opt{port}" if defined($opt{port});
    }

    push @opt, $opt{database} if defined $opt{database} and !$opt{'no_database'};
    return join ' ', @opt;
}

{
    my $yaml_run;
    sub use_yaml {
        eval 'use YAML::Syck ()' if ! $yaml_run++;
        return $yaml_run;
    }
}

sub parse_yaml {
    my $file = shift;
    use_yaml();
    return YAML::Syck::LoadFile( $file );
}

sub _prepare_camp_database_client_settings {
    return _db_type_dispatcher( '_prepare_camp_database_client_settings' )->( @_ );
}

# Clean up the user's .pgpass file, add new entries for this camp, which means
# initializing passwords for each role.
sub _prepare_camp_database_client_settings_pg {
    my ($conf, $roles, $dbnames) = @_;
    # Read any existing ~/.pgpass file
    my $pass_file = File::Spec->catfile( $conf->{root}, '.pgpass', );
    my $old_pass_data = '';
    if (-f $pass_file) {
        open my $IN, '<', $pass_file or die "Can't read $pass_file: $!\n";
        while (<$IN>) {
            next if /^$conf->{db_host}:$conf->{db_port}:/;
            $old_pass_data .= $_;
        }
        close $IN or die "Couldn't close $IN: $!\n";
    }
    my $pw_cache      = role_password_cache_pg();
    my $postgres_pass = $conf->{db_pg_postgres_pass} = $pw_cache->{postgres} || generate_nice_password();
    my $pass_file_tmp = File::Temp->new( UNLINK => 0, DIR => $conf->{root} );
    $pass_file_tmp->print( "$conf->{db_host}:$conf->{db_port}:*:postgres:$postgres_pass\n" );
    for my $role (@$roles) {
        my $pass = role_password( $role );
        $pass_file_tmp->print("$conf->{db_host}:$conf->{db_port}:*:$role:$pass\n");
    }
    $pass_file_tmp->print($old_pass_data);
    $pass_file_tmp->close or die "Couldn't close $pass_file_tmp: $!\n";
    rename "$pass_file_tmp", $pass_file
        or die "Couldn't rename $pass_file_tmp to $pass_file: $!\n";
    return 1;
}

# For MySQL, we have no native equivalent to a camp-oriented my.cnf, as my.cnf is only for the
# user's home directory and doesn't readily apply to multiple mysql instances (in the [client]
# section).
#
# So, we create a hash of relevant information (socket, port, host, default db, default user, user/pass pairs)
# and store it as YAML.  This is the outbound side of the YAML work you see in camp_mysql_options().
sub _prepare_camp_database_client_settings_mysql {
    my ($conf, $roles) = @_;

    my $settings = {
        users => {},
    };
    $settings->{socket} = $conf->{db_socket} if defined($conf->{db_socket}) and length($conf->{db_socket});
    $settings->{port} = $conf->{db_port} if defined($conf->{db_port}) and length($conf->{db_port});
    $settings->{host} = $conf->{db_host} if defined($conf->{db_host}) and length($conf->{db_host}) and lc($conf->{db_host}) ne 'localhost';
    $settings->{default_database} = $conf->{db_default_database} if defined($conf->{db_default_database}) and length($conf->{db_default_database});
    $settings->{default_user} = $conf->{db_default_user} if defined($conf->{db_default_user}) and length($conf->{db_default_user});
    for my $role (@$roles) {
        $settings->{users}{$role} = role_password( $role );
    }

    my $file_name = camp_mysql_settings_file( $conf );
    my $tmp_file = File::Temp->new( UNLINK => 0, DIR => $conf->{path} );
    use_yaml();
    $tmp_file->print( YAML::Syck::Dump( $settings ) );
    $tmp_file->close or die "Couldn't close $tmp_file: $!\n";
    rename "$tmp_file", $file_name
        or die "Couldn't rename $tmp_file to $file_name: $!\n";
    return 1;
}

sub _initialize_camp_database {
    return _db_type_dispatcher( '_initialize_camp_database' )->(@_);
}

sub _initialize_camp_database_pg {
    my $conf = shift;

    # PostgreSQL initdb before version 8.0 didn't have the -A or --pwfile options,
    # so we have to basically reimplement them manually.
    my $password_pain = (db_version_pg() < 8.0);

    my $postgres_pass = $conf->{db_pg_postgres_pass} or die "No password determined for postgres user!\n";
    # Run initdb to make new database cluster.
    my $tmp = File::Temp->new( DIR => camp_user_tmpdir(), UNLINK => 0 );
    $tmp->print( "$postgres_pass\n" );
    $tmp->close or die "Couldn't close $tmp: $!\n";

    my @args = (
        "-D $conf->{db_data}",
        '-n',
        '-U', 'postgres',
    );
    if (! $password_pain) {
        push @args, '-A', 'md5', "--pwfile=$tmp";
    }
    push @args, "-E $conf->{db_encoding}"
        if $conf->{db_encoding};
    push @args, "--locale=$conf->{db_locale}"
        if $conf->{db_locale};
    my $cmd = 'initdb ' . join(' ', @args);
    print "Preparing database cluster:\n$cmd\n";
    system($cmd) == 0 or die "Error executing initdb!\n";

    if ($password_pain) {
        # The default pg_hba.conf uses ident authentication, which won't work since
        # we're user e.g. "bob" trying to connect as "postgres", so switch temporarily
        # to trust auth.
        my $pg_hba_file = File::Spec->catfile($conf->{db_data}, 'pg_hba.conf');
        my $pg_hba_orig = "$pg_hba_file.orig";
        rename $pg_hba_file, $pg_hba_orig or die "Couldn't rename $pg_hba_file to $pg_hba_orig: $!\n";
        open my $TRUST, '>', $pg_hba_file or die "Couldn't write $pg_hba_file: $!\n";
        print {$TRUST} <<'END';
local all all trust
END
        close $TRUST or die "Couldn't close $pg_hba_file: $!\n";

        # We have to start the database to be able to set the superuser's password
        _render_database_config($conf);
        db_control('start') or die "Error starting new camp database!\n";
        my $PSQL = db_connect_as_owner();
        print {$PSQL} "ALTER USER postgres WITH ENCRYPTED PASSWORD '$postgres_pass';\n";
        close $PSQL or die "Error piping command to psql: $!\n";

        # Now that the superuser's password is set, we can switch to password authentication
        # by editing the original pg_hba.conf.
        my $pg_hba_content = '';
        open my $IN, '<', $pg_hba_orig or die "Couldn't read $pg_hba_orig: $!\n";
        while (<$IN>) {
            # Comment out all active lines
            $pg_hba_content .= '#' if /\S/ and ! /^\s*#/;
            $pg_hba_content .= $_;
        }
        close $IN or die "Couldn't close $pg_hba_file: $!\n";

        open my $OUT, '>', $pg_hba_file or die "Couldn't write $pg_hba_file: $!\n";
        print {$OUT} $pg_hba_content;
        print {$OUT} <<'END';
local   all         all                                             md5
host    all         all         127.0.0.1         255.255.255.255   md5
END
        close $OUT or die "Couldn't close $pg_hba_file: $!\n";

        # Now stop the database and on next start it should be ready to go
        db_control('stop') or die "Error stopping new camp database!\n";
    }

    unlink $tmp or die "Error unlinking $tmp: $!\n";

    # Create SSL certificate
    if (defined $conf->{db_pg_ssl_active} and $conf->{db_pg_ssl_active}) {
        my $crt_path = File::Spec->catfile( $conf->{db_data}, 'server.crt' );
        my $key_path = File::Spec->catfile( $conf->{db_data}, 'server.key' );

        my $ssl_C  = $conf->{db_pg_ssl_C}  || $conf->{ssl_C};
        my $ssl_ST = $conf->{db_pg_ssl_ST} || $conf->{ssl_ST};
        my $ssl_L  = $conf->{db_pg_ssl_L}  || $conf->{ssl_L};
        my $ssl_O  = $conf->{db_pg_ssl_O}  || $conf->{ssl_O};

        my $tmpfile = File::Temp->new( DIR => camp_user_tmpdir(), UNLINK => 0 );
        $tmpfile->print(<<EOF);
[ req ]
distinguished_name = req_distinguished_name
attributes         = req_attributes
prompt             = no

[ req_distinguished_name ]
C                 = $ssl_C
ST                = $ssl_ST
L                 = $ssl_L
O                 = $ssl_O
OU                = $conf->{name} for $conf->{admin_name}
CN                = $conf->{hostname}
emailAddress      = $conf->{admin_email}

[ req_attributes ]
challengePassword =
EOF
        $tmpfile->close;

        do_system("openssl genrsa -out $key_path");

        chmod 0600, $key_path or die "Can't change permissions on $key_path: 0600\n";

        do_system("openssl req -new -x509 -days 3650 -key $key_path -out $crt_path -config $tmpfile");

        unlink($tmpfile) or die "Error unlinking $tmpfile: $!\n";
    }

    return 1;
}

sub _initialize_camp_database_mysql {
    my $conf = shift;
    _render_database_config($conf)  unless ($conf->{_did_render_database_config});
    my $cmd = "mysql_install_db --datadir=$conf->{db_data} --defaults-file=$conf->{db_conf}";
    print "Preparing database instance:\n$cmd\n";
    system($cmd) == 0 or die "Error executing mysql_install_db!\n";
    return 1;
}

sub _render_database_config {
    my $conf = shift;
    # set up camp-specific configuration
    open my $TEMPLATE, '<', db_config_path() or die "Failed to open database configuration template: $!\n";
    my $template = do { local $/; <$TEMPLATE> };
    close $TEMPLATE or die "Failed to close database configuration template!\n";
    $template = substitute_hash_tokens(
        $template,
        {
            map { $_ => $conf->{$_} }
            grep /^db_/,
            keys %$conf
        },
    );
    # my.cnf is private per camp, so needs to be replaced at refresh time
    my $open_type = ($conf->{db_type} eq 'mysql') ? '>' : '>>';
    open my $CONF, $open_type, $conf->{db_conf} or die "Could not append to $conf->{db_conf}: $!\n";
    print $CONF $template;
    close $CONF or die "Couldn't close $conf->{db_conf}: $!\n";
    $conf->{_did_render_database_config} = 1;
    return 1;
}

sub db_connect_as_owner {
    return _db_type_dispatcher('_db_connect_as_owner')->(@_);
}

sub _db_connect_as_owner_pg {
    return db_connect( @_, user => 'postgres', database => 'template1' );
}

sub _db_connect_as_owner_mysql {
    return db_connect( @_, user => 'root', database => 'mysql' );
}

sub db_connect {
    return _db_type_dispatcher('_db_connect')->(@_);
}

sub _db_connect_pg {
    my %opt = @_;
    my $conf = config_hash();
    my $cmd = "psql -X -h $conf->{db_host} -p $conf->{db_port} -U $opt{user} -d $opt{database}";
    print "Connecting to Postgres: $cmd\n";
    open my $PSQL, "| $cmd"
        or die "Error opening pipe to psql: $!\n";
    return $PSQL;
}

sub _db_connect_mysql {
    my %opt = @_;
    my $conf = config_hash();
    # use the -n (unbuffered) option to flush the buffer per query (necessary in a pipeline)
    my $cmd = 'mysql ' . camp_mysql_options(%opt);
    print "Connecting to MySQL: $cmd\n";
    open my $MYSQL, "| $cmd"
        or die "Error opening pipe to mysql: $!\n";
    return $MYSQL;
}

sub _prepare_camp_database_roles {
    my ($roles, $conf) = @_;

    # Create regular database roles; no_password doesn't affect Pg but matters for MySQL (only this first time).
    my $SESSION = db_connect_as_owner( no_password => 1 );

    # This has no effect on Pg, but matters a lot to MySQL.
    _db_pre_roles_trigger( $SESSION, $conf );

    for my $role (@$roles) {
        my $sql = role_sql( $role );
        print "SQL: $sql\n";
        print {$SESSION} $sql, "\n;\n";
    }

    # Again, no effect on Pg, but significant to MySQL.
    _db_post_roles_trigger( $SESSION, $conf );

    close $SESSION or die "Error piping command to database: $!\n";
    return 1;
}

sub _db_pre_roles_trigger {
    return _db_type_dispatcher('_db_pre_roles_trigger')->(@_);
}

sub _db_pre_roles_trigger_pg {
    return 1;
}

sub _db_pre_roles_trigger_mysql {
    my ($PIPE, $conf) = @_;
    # Here's where we slurp the mysql.sql dump and thus get database user rights
    # properly set up in MySQL.
    for my $script_name (@{ $conf->{db_mysql_scripts} }) {
        my $script = File::Spec->catfile( type_path(), $script_name );
        print "Processing MySQL initialization source script: $script\n";
        print {$PIPE} "source $script;\n";
    }
    print "Flushing privileges on MySQL.\n";
    print {$PIPE} "FLUSH PRIVILEGES;\n";
    return 1;
}

sub _db_post_roles_trigger {
    return _db_type_dispatcher('_db_post_roles_trigger')->(@_);
}

sub _db_post_roles_trigger_pg {
    return 1;
}

sub _db_post_roles_trigger_mysql {
    my ($PIPE, $conf) = @_;
    # Need to flush privileges once more for MySQL to get in-memory grant tables updated.
    print "flushing privileges on MySQL.\n";
    print {$PIPE} "FLUSH PRIVILEGES;\n";
    return 1;
}

sub _import_camp_data {
    my ($sources, $conf) = @_;
    # Import data
    for my $script (@$sources) {
        my $script_file = $script;
        if ($conf_hash->{db_source_scripts_parse}{$script}) {
            print "Tokenizing script '$script'\n";
            # slurp source script
            local $/;
            local @ARGV = $script_file;
            my $src = <>;
            # tokenize into a temporary file
            my $tmpfile = File::Temp->new( DIR => $conf->{db_tmpdir}, UNLINK => 0 );
            $tmpfile->print(substitute_hash_tokens($src, $conf));
            $tmpfile->close;
            $script_file = $tmpfile;
        }
        $script_file = File::Spec->file_name_is_absolute($script_file)
            ? $script_file
            : File::Spec->catfile(type_path(), $script_file);
        my $cmd = _import_db_cmd($script_file, $conf);
        print "Processing script '$script':\n$cmd\n";
        system($cmd) == 0 or die "Error importing data\n";
    }
    return;
}

sub _import_db_cmd {
    return _db_type_dispatcher('_import_db_cmd')->(@_);
}

sub _import_db_cmd_pg {
    my ($script, $conf) = @_;
    # Old versions of Postgres didn't create a "postgres" database by default.
    # But for newer ones, use that instead of template1 so we don't pollute the
    # template db if something goes wrong in the import.
    my $dbname = (db_version_pg() < 8.0) ? 'template1' : 'postgres';
    return "psql -X -h $conf->{db_host} -p $conf->{db_port} -U postgres -d $dbname -f $script";
}

sub _import_db_cmd_mysql {
    my ($script, $conf) = @_;
    return 'mysql ' . camp_mysql_options( user => 'root', no_database => 1 ) . " < $script";
}

sub prepare_database {
    my $replace = shift;
    my $conf = config_hash();
    return if $conf->{skip_db};
    my (@roles, @sources, @dbnames);
    _prepare_database_vars( $conf, \@roles, \@sources, \@dbnames );

    _verify_camp_path( $conf );

    # check for extant database
    _database_exists_check( $conf, $replace );

    # initialize database paths including base, data, tmp
    mkdir $conf->{db_path} or die "Could not make database path '$conf->{db_path}': $!\n";
    mkdir $conf->{db_data} or die "Couldn't make database data path '$conf->{db_data}': $!\n"
        unless -d $conf->{db_data};
    mkdir $conf->{db_tmpdir} or die "Couldn't make database tmp/ path '$conf->{db_tmpdir}': $!\n"
        unless -d $conf->{db_tmpdir};

    _prepare_camp_database_client_settings( $conf, \@roles, \@dbnames );

    _initialize_camp_database($conf);

    _render_database_config($conf)
        unless $conf->{_did_render_database_config};

    # Start new camp database instance
    db_control( 'start' ) or die "Error starting new camp database!\n";

    # Sleep for a few seconds to give the server time to set up if necessary
    my $sleep_threshold = defined($conf->{db_sleep_time}) ? $conf->{db_sleep_time} : 5;
    sleep($sleep_threshold) if $sleep_threshold;

    _prepare_camp_database_roles( \@roles, $conf );

    _import_camp_data( \@sources, $conf );

    type_message('prepare_database');
    return;
}

sub do_system {
    my @cmd = @_;
    print "@cmd\n";
    my $exit = system(@cmd) >> 8;
    die "Error! Exit code = $exit\n" unless $exit == 0;
    return;
}

sub generate_nice_password {
    my @v = qw( a e i o u );
    my @c = qw( b d f g h j k m n p r s t v w z );  # no l, y
    my @c2 = (@c, qw( c q x ));
    my @d = (2..9);   # no 0, 1

    my $did_numbers = 0;
    my $did_letters = 0;
    my $last_numbers;
    my $pass = '';
    for (1..3) {
        my $l = rand(10) > 7;
        if ($last_numbers) {
            $l = 1;
        }
        elsif ($_ > 2) {
            undef $l if ! $did_numbers;
            $l = 1 if ! $did_letters;
        }
        if ($l) {
            $pass .= $c[rand @c] . $v[rand @v];
            $pass .= $c2[rand @c2] if rand(10) > 5;
            ++$did_letters;
            undef $last_numbers;
        }
        else {
            $pass .= $d[rand @d];
            $pass .= $d[rand @d] if rand(10) > 3;
            ++$did_numbers;
            $last_numbers = 1;
        }
        redo if $_ > 2 and length($pass) < 8;
    }
    return $pass;
}

sub server_control {
    my %opt = @_;
    my (
        $action,
        $service,
    ) = @opt{qw( action service )};
    $service = (has_rails() ? 'rails' : 'ic') if ! defined $service;
    my %actions = map { $_ => $_ } qw(
        init
        restart
        stop
        start
    );

    my %services = (
        db      => \&db_control,
        httpd   => \&httpd_control,
    );

    my %db_services = (
        pg      => \&_db_control_pg,
        mysql   => \&_db_control_mysql,
    );

    my $dbtype = camp_db_type();
    $services{ic}       = \&ic_control    if has_ic();
    $services{rails}    = \&rails_control if has_rails();
    $services{app}      = \&app_control   if has_app();
    $services{$dbtype}  = $db_services{$dbtype};
    delete $services{db} if $conf_hash->{skip_db};

    my @services = grep { defined $services{$_} } qw(
        httpd
        pg
        mysql
        db
        ic
        rails
        app
    );

    die "Invalid action '$action' specified!\n" unless $actions{$action};
    my @services_to_start;
    if ($service eq 'all') {
        @services_to_start = grep !defined($db_services{$_}), @services;
    }
    else {
        die "Invalid service '$service' specified!\n" unless $services{$service};
        @services_to_start = ($service);
    }

    my %nonfatal_actions = (
        stop => 'stop',
    );

    my $fatal = !defined($nonfatal_actions{$action});
    for my $service_name (@services_to_start) {
        print "Service $service_name ${action}...\n";
        $services{$service_name}->( $action ) or (
            $fatal && die "Failed to $action $service_name!\n"
        );
    }
    return scalar(@services_to_start);
}

sub app_control {
    my $action = shift;
    my $conf = config_hash();

    my $cmd = $conf->{"app_$action"};
    $cmd and do_system_soft($cmd) == 0 and return 1;
    return;
}

sub rails_control {
    my $action = shift;
    my $conf = config_hash();
    die "Need railsdir definition!\n"
        unless defined $conf->{railsdir}
        and $conf->{railsdir} =~ /\S/
    ;
    # Stupid mongrel doesn't return real exit statuses.
    # Nor does it have a smart restart that simply starts if it wasn't running.
    my @actions;
    if ($action eq 'restart') {
        @actions = qw(stop start);
    }
    else {
        @actions = ($action);
    }
    # Stupid mongrel fails if the var/log and var/run directories don't exist.  Lame.
    mkpath( [ map { File::Spec->catfile( $conf->{railsdir}, 'var', $_, ) } qw( log run ) ] );
    my $cmd = join('; ', map { "mongrel_rails cluster::$_" } @actions);
    do_system_soft( "cd $conf->{railsdir} && ($cmd)" ) == 0
        and return 1;
    return;
}

sub ic_control {
    my $action = shift;
    my $conf = config_hash();
    $ENV{CAMP} = $conf->{number};
    return do_system_soft("$conf->{icroot}/bin/interchange --$action") == 0;
}

sub db_control {
    return _db_type_dispatcher( '_db_control' )->(@_);
}

sub _db_control_mysql {
    my $action = shift;
    my $conf = config_hash();
    die "Need db_data definition!\n"
        unless defined $conf->{db_data}
            and $conf->{db_data} =~ /\S/;
    my $cmd;
    $action = lc($action);
    if ($action eq 'restart') {
        _db_control_mysql( 'stop' );
        return _db_control_mysql( 'start' );
    }
    elsif ($action eq 'start') {
        $cmd = "nohup mysqld_safe --defaults-file=$conf->{db_conf} > $conf->{db_tmpdir}/nohup.out 2>&1 &";
    }
    else {
        $action = 'shutdown' if $action eq 'stop';
        my $opt = camp_mysql_options( no_database => 1, user => 'root' );
        $cmd = "mysqladmin --defaults-file=$conf->{db_conf} $opt $action";
    }
    do_system_soft($cmd) == 0
        and return 1;
    return;
}

sub _db_control_pg {
    my $action = shift;
    my $conf = config_hash();
    die "Need db_data definition!\n"
        unless defined $conf->{db_data}
            and $conf->{db_data} =~ /\S/;
    my $cmd = "PGHOST=$conf->{db_host} pg_ctl -D $conf->{db_data} -l $conf->{db_tmpdir}/pgstartup.log -m fast";
    # Work around old pg_ctl's terrible -w implementation, as evidenced by
    # this comment there: "FIXME:  This is horribly misconceived."
    my $manual_wait = (db_version_pg() < 8.0);
    $cmd .= ' -w' if ! $manual_wait;
    $cmd .= ' ' . $action;
    my $result = do_system_soft($cmd);
    sleep 5 if $manual_wait;
    $result == 0 and return 1;
    return;
}

sub httpd_control {
    my $action = shift;
    my $conf = config_hash();

    my $cmd = $conf->{"httpd_$action"};
    if (!$conf->{skip_apache} and !$cmd) {
        die "Need httpd_cmd_path definition!\n"
            unless defined $conf->{httpd_cmd_path}
                and $conf->{httpd_cmd_path} =~ /\S/;
        die "Need httpd_path definition!\n"
            unless defined $conf->{httpd_path}
                and $conf->{httpd_path} =~ /\S/;

        $cmd = "$conf->{httpd_cmd_path} -d $conf->{httpd_path} -k $action";
        $cmd .= join('', map { " -D$_" } grep /\S/, split / /, $conf->{httpd_define})
            if $conf->{httpd_define};
        if (defined $conf->{httpd_specify_conf} and $conf->{httpd_specify_conf} =~ /\S/) {
            $cmd .= " -f $conf->{httpd_path}/$conf->{httpd_specify_conf}";
        }
    }

    $cmd and do_system_soft($cmd) == 0 and return 1;
    return;
}

sub db_version_pg {
    my %arg = @_;
    # Yes, this naively assumes that the PostgreSQL client libraries are the
    # same as the server version. That makes it much easier and works for now.

    # Some examples of psql --version output:
    # psql (PostgreSQL) 7.3.19-RH
    # psql (PostgreSQL) 8.2.5
    my $raw = `psql --version 2>/dev/null`;
    $raw =~ s/\n.*//s;  # keep only the first line
    return $raw if $arg{raw};
    my ($full, $numeric, $major_minor) = $raw =~ /\s(((\d+\.\d+)(?:\.\d+)?)\S*)/;
    return $full if $arg{full};
    return $numeric if $arg{numeric};
    return $major_minor;
}

sub do_system_soft {
    my @cmd = @_;
    print "@cmd\n";
    return system(@cmd) >> 8;
}

sub type_message {
    my $type = shift;
    my $message_file = File::Spec->catfile( type_path(), "${type}_message", );
    return unless -f $message_file;
    local $/;
    open my $MSG, '<', $message_file or die "Failed to open message file $message_file: $!\n";
    print "\n" . <$MSG> . "\n";
    close $MSG or die "Error closing $message_file\n";
    return 1;
}

sub default_camp_type {
    my ($deftype) = dbh()->selectrow_array(<<'EOL');
SELECT c.camp_type
FROM camp_types c
LEFT JOIN camp_types c2
    ON c2.camp_type <> c.camp_type
WHERE c2.camp_type IS NULL
EOL
    return $deftype;
}

sub camp_type_list {
    return map { { type => $_->[0], description => $_->[1] } } @{ dbh()->selectall_arrayref(
        'SELECT camp_type, description FROM camp_types ORDER BY camp_type'
    ) };
}

sub _camp_list_sql {
    return _db_type_dispatcher( '_camp_list_sql' )->( @_ );
}

sub _camp_list_sql_pg {
    my $where = shift;
    return <<SQL;
SELECT c.*, u.name, u.email, c.create_date::DATE as create_date_display
FROM camps c, camp_users u
WHERE c.username = u.username$where
ORDER BY c.camp_number ASC
SQL
}

sub _camp_list_sql_mysql {
    my $where = shift;
    return <<SQL;
SELECT c.*, u.name, u.email, c.create_date as create_date_display
FROM camps c, camp_users u
WHERE c.username = u.username$where
ORDER BY c.camp_number ASC
SQL
}

sub camp_list {
    my %opt = @_;
    die "You must specify a camp type!\n"
        unless $opt{type}
            or $opt{all}
            or $opt{user};

    my (@args, $where);
    $where = '';

    if ($opt{type}) {
        my @types = ref $opt{type} eq 'ARRAY' ? @{$opt{type}} : $opt{type};
        $where .= "\n\tAND c.camp_type IN (" . join(',', ('?') x @types) . ")";
        push @args, @types;
    }
    if ($opt{user}) {
        $where .= "\n\tAND c.username = ?";
        push @args, $opt{user};
    }

    my $sth = dbh()->prepare( _camp_list_sql($where) );

    my @result;
    $sth->execute(@args);
    my @config_keys = qw(
        http_port
        https_port
        hostname
        http_url
        https_url
    );
    while (my $rec = $sth->fetchrow_hashref) {
        initialize( force => 1, camp => $rec->{camp_number}, );
        my $hash = config_hash();
        my $result = { %$rec };
        @$result{@config_keys} = @$hash{@config_keys};
        push @result, $result;
    }
    $sth->finish;
    return @result;
}

sub run_post_mkcamp_command {
    my $conf = config_hash();
    my $cmd = $conf->{post_mkcamp_command};
    $cmd and return do_system_soft($cmd) == 0;
    return;
}

1;

=pod

=head1 VERSION CONTROL SYSTEM OPTIONS

The camp system provides three different version control choices:

=over

=item *

Subversion ('svn')

=item *

Git ('git')

=back

Typically speaking, use of Git for a particular camp type implies non-use of Subversion, and the opposite also holds.
However, there is no reason that all types cannot be made available for use within the same camp type; the Git
software suite comes with '''git-svn''', which can be used to track a Subversion repository via a Git repository.
Therefore, all options can be available for a camp type provided the administrator takes the trouble to arrange
it.  That arrangement takes place largely outside of the camp system itself, and would instead involve post-commit
hooks within one or both repositories to ensure that a change in one repository is pushed to the other.

B<Camp::Master> ultimately makes no assumptions about your camp type's VCS offerings; if a camp user attempts to make
a new camp using some version control system, B<Camp::Master> will attempt to do it, and if the requested version control
system hasn't been configured for the camp type, an error will result.  Configuration options to tell B<Camp::Master>
about your VCS setup are fairly straightforward; see the configuration variable information for:

=over

=item *

I<default_vcs_type>

=item *

I<repo_path>

=item *

I<repo_path_git>

=item *

I<repo_path_svn>

=back

While no assumptions are made, the strong recommendation is to use Git. Subversion is slow, inefficient in its use of disk space, relatively inflexible, bad at branching, etc.

=head1 GIT USE

When creating a new camp using Git as the VCS type, B<Camp::Master> assumes an SVN-like flow of operations; the
camp type specifies where the Git repository lives, and the new camp will result in a new repository that tracks
that central repository.  Consequently, the operations used by B<Camp::Master> tend to be clone, pull, and push
operations, for remote repository use.  When you're working within your Git-based camp, you of course need to
keep this in mind, knowing that a checkout or a commit are only relative to the repository of that camp, and that
you ultimately need a push to commit your stuff to the central camp repository.

At this time, B<Camp::Master> doesn't provide any tools for creating a Git camp using an alternate repository
as the repository to track; this is something that can be done using git directly, after creating a new camp.
Create the camp with Git as the VCS choice, then use git directly within that camp to point the camp at an
alternate remote repository.

=head1 BUGS AND LIMITATIONS

This module has tests. It also probably has bugs. It is, after all, software.

=head1 AUTHOR

Ethan Rowe and other contributors

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2006-2016 End Point Corporation, https://www.endpoint.com/

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see: http://www.gnu.org/licenses/

=cut
