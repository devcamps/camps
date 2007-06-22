package Camp::Master;

use strict;
use warnings;
use IO::Handle;
use File::Path;
use File::pushd;
use File::Temp ();
use File::Spec;
use Data::Dumper;
use User::pwent;
use DBI;
use Exporter;
use base qw(Exporter);

@Camp::Master::EXPORT = qw(
    initialize
    dbh
    base_path
    base_user
    type_path
    install_templates
    camp_list
    has_rails
    has_ic
    camp_db_type
    camp_db_config
    create_camp_path
    prepare_camp
    prepare_ic
    prepare_apache
    prepare_database
    prepare_rails
    register_camp
    set_camp_user
    svn_checkout
	svn_update
    get_next_camp_number
    camp_user
    camp_user_info
    camp_user_obj
    config_hash
    do_system
    role_password
    role_sql
    roles
    roles_path
    pgsql_path
    mysql_path
    db_path
    server_control
    process_copy_paths
);

my (
    @base_edits,
    @edits,
    %edits,
    $has_rails,
    $has_ic,
    $initialized,
    $type,
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
    httpd/conf/httpd.conf
);
$base_camp_user = 'camp';

sub initialize {
    my %options = @_;
    if (!$initialized or $options{force}) {
        $initialized
            = $conf_hash = $has_rails = $has_ic = $type
            = $camp_user = $camp_user_info = $roles
            = $camp_db_config
            = undef;
        @edits = %edits = ();
        $conf_hash = undef;
        if (defined $options{camp} and $options{camp} =~ /^\d+$/) {
            my $hash = get_camp_info( $options{camp} );
            set_type( $hash->{camp_type} );
            set_camp_user( $hash->{username} );
            read_camp_config();
            $initialized++;
            # initialize the config hash to the requested camp number.
            $hash = config_hash( $options{camp} );
        }
        else {
            set_type( $options{type} ) if defined $options{type};
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
    close $CONFIG;
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
    close $FILE;
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

sub type_path {
    my $local_type = @_ ? shift : type();
    return File::Spec->catfile( base_path(), $local_type, );
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

=back

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

=over

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
        if grep { !( ref($_) eq 'HASH' and defined($_->{source}) and defined($_->{target}) ) } @data
    ;

    for my $copy (@data) {
        my $link = defined($copy->{default_link}) && $copy->{default_link};
        my $src = $copy->{source};
        my $target = $copy->{target};
        $src = File::Spec->catfile( type_path(), $src ) if ! File::Spec->file_name_is_absolute($src);
        $target = File::Spec->catfile( $conf->{path}, $target );
        if (!$defaults_only and !( defined($copy->{always}) && $copy->{always} )) {
            my $decision;
            while (!defined($decision) or $decision !~ /^\s*([yn]?)\s*$/i) {
                printf "Do you want to copy $src to $target (if no, symlinks are used)? y/n (%s) ", $link ? 'n' : 'y';
                $decision = <STDIN>;
            }
            $link = $1 eq 'n' if $1;
        }
        if ($link) {
            print "Symlinking $target to $src.\n";
            symlink($src, $target) or die "Failed to symlink: $!\n";
        }
        else {
            print "Copying $src to $target.\n";
            system("cp -a $src $target") == 0 or die "Failed to copy: $!\n";
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

sub has_rails {
    die "Cannot call has_rails() until package has been initialized!\n" unless $initialized;
    return $has_rails if defined $has_rails;
    return $has_rails = (grep m!^rails/[-\w]+/config/mongrel_cluster.yml$!, @edits,) ? 1 : 0;
}

sub has_ic {
    die "Cannot call has_ic() until package has been initialized!\n" unless $initialized;
    return $has_ic if defined $has_ic;
    return $has_ic = $edits{'interchange/bin/interchange'} ? 1 : 0;
}

sub base_user_path {
    return base_user()->dir();
}

sub base_user {
    die "No base user specified!\n" unless defined $base_camp_user and $base_camp_user =~ /\S/;
    return $base_user_obj ||= getpwnam( $base_camp_user );
}

sub dbh {
    return $dbh if defined $dbh;
    my %settings = camp_db_config();
    my ($dsn, $user, $pass) = @settings{qw( dsn user password )};
    die "Must specify a DSN and user to access camp database!\n"
        unless defined $dsn and defined $user
    ;
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
}

sub set_camp_user_info {
    my $user = shift;
    my $row = dbh()->selectrow_hashref('SELECT name AS admin_name, email AS admin_email FROM camp_users WHERE username = ?', undef, $user,);
    die "admin '$user' is unknown; aborting!\n"
        unless ref($row) and $row->{admin_name}
    ;
    return $row;
}

sub get_camp_info {
    my $camp = shift;
    my $row = dbh()->selectrow_hashref('SELECT username, camp_type FROM camps WHERE camp_number = ?', undef, $camp,);
    die "Camp '$camp' is unknown!\n"
        unless ref($row) and $row->{camp_type}
    ;
    return $row; 
}

sub camp_user {
    die "No camp user set!\n"
        unless defined $camp_user_obj
    ;
    return $camp_user;
}

sub camp_user_obj {
    die "No camp user set!\n"
        unless defined $camp_user_obj
    ;
    return $camp_user_obj;
}

sub camp_user_info {
    die "No camp user set!\n"
        unless defined $camp_user_obj
    ;
    return $camp_user_info;
}

sub _db_type_dispatcher {
    my $name = shift;
    my $type = camp_db_type();
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
    my ($count) = $db->selectrow_array(q{SELECT COUNT(*) FROM camps WHERE camp_number > 0});
    return 1 unless $count;
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
    for my $key (sort { length($a) <=> length($b) } keys %$hash) {
        my $val = $hash->{$key};
        my $token = uc( length($prefix) ? "${prefix}_$key" : $key );
        $string =~ s/__${token}__/$val/g;
    }
    return $string;
}

sub _config_hash_db {
    my ($hash, $camp_number) = @_;
    _determine_db_type_and_path( $hash ) or die "Failed to determine database type!\n";
    $hash->{db_host}       = 'localhost';
    $hash->{db_port}       = 8900 + $camp_number;
    $hash->{db_encoding}   = 'UTF-8',
#    $hash->{db_locale}     = undef; 
    $hash->{db_data}       = File::Spec->catfile( $hash->{db_path}, 'data', );
    $hash->{db_tmpdir}     = File::Spec->catfile( $hash->{db_path}, 'tmp', );

    if ($hash->{db_type} eq 'pg') {
        $hash->{db_log}        = File::Spec->catfile( $hash->{db_tmpdir}, 'postgresql.log', );
        $hash->{db_conf}       = File::Spec->catfile( $hash->{db_data}, 'postgresql.conf', );
    }
    elsif ($hash->{db_type} eq 'mysql') {
        # mysql
        $hash->{db_log}        = File::Spec->catfile( $hash->{db_tmpdir}, 'mysql.log', );
        $hash->{db_conf}       = File::Spec->catfile( $hash->{path}, 'my.cnf', );
        $hash->{db_socket}     = File::Spec->catfile( $hash->{db_tmpdir}, "mysql.$camp_number.sock" );
    }
    else {
        die "Unknown database type!\n";
    }
}

sub _determine_db_type_and_path {
    my $conf = shift;
    my %paths = qw(
        pgsql   pg
        mysql   mysql
    );

    my @found = grep { -d File::Spec->catfile( type_path(), $_ ) } keys %paths;
    die "Found more than one database type; only one may be used!\n"
        if @found > 1;
    die "No database found for camp type!\n"
        if !@found;
    $conf->{db_path} = File::Spec->catfile( $conf->{path}, $found[0] );
    $conf->{db_type} = $paths{$found[0]};
    return $conf->{db_type};
}

sub config_hash {
    if (! defined $conf_hash) {
        my $camp_number = shift;
        die "Must provide a camp number for initialization of config_hash()!"
            unless defined $camp_number and $camp_number =~ /^\d+$/
        ;
        $conf_hash = {
            %{ camp_user_info() },
            number  => $camp_number,
            name    => "camp$camp_number",
            root    => camp_user_obj()->dir(),
        };
        $conf_hash->{path} = File::Spec->catfile( $conf_hash->{root}, $conf_hash->{name}, );
        if (has_ic()) {
            $conf_hash->{icroot}    = File::Spec->catfile( $conf_hash->{path}, 'interchange',);
            $conf_hash->{cgidir}    = File::Spec->catfile( $conf_hash->{path}, 'cgi-bin', );
        }
        $conf_hash->{docroot}   = File::Spec->catfile( $conf_hash->{path}, 'htdocs', );
        if (has_rails()) {
            $conf_hash->{railsdir}  = File::Spec->catfile( $conf_hash->{path}, 'rails', );
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

        $conf_hash->{httpd_path}    = File::Spec->catfile( $conf_hash->{path}, 'httpd', );
        $conf_hash->{httpd_lib_path}    = '/usr/lib/httpd/modules';
        $conf_hash->{httpd_cmd_path}    = '/usr/sbin/httpd';
        $conf_hash->{http_port}     = 9000 + $camp_number;
        $conf_hash->{https_port}    = 9100 + $camp_number;
        for my $conf_file (
            map { File::Spec->catfile( $_, 'local-config', ) } base_path(), type_path(),
        ) {
            next unless -f $conf_file;
            open(my $CONF, '<', $conf_file,);
            while (my $line = <$CONF>) {
                chomp($line);
                next unless $line =~ /\S/;
                next if $line =~ /^\s*#/;
                if (my ($key,$val) = $line =~ /^\s*(\w+):(.*?)\s*$/) {
                    $conf_hash->{$key} = substitute_hash_tokens( $val, $conf_hash, );
                }
                else {
                    warn "Skipping invalid line in file $conf_file ($line)\n";
                    next;
                }
            }
            close $CONF;
        }
        die "Must specify a hostname within your base camp or type local-config!\n"
            unless defined $conf_hash->{hostname} and $conf_hash->{hostname} =~ /\S/
        ;
        die "Must specify the camp directory list within your base camp or type local-config!\n"
            unless defined $conf_hash->{camp_subdirectories}
                and $conf_hash->{camp_subdirectories} =~ /\S/
        ;
        $conf_hash->{camp_subdirectories} = [
            split /[\s,]+/, $conf_hash->{camp_subdirectories}
        ];
        $conf_hash->{db_source_scripts} = [
            split /[\s,]+/, $conf_hash->{db_source_scripts} || ''
        ];
        $conf_hash->{db_dbnames} = [
            split /[\s,]+/, $conf_hash->{db_dbnames} || ''
        ];

        $conf_hash->{db_mysql_scripts} = [
            split /[\s,]+/, $conf_hash->{db_mysql_scripts}
        ] if $conf_hash->{db_type} eq 'mysql';

        if (has_ic()) {
            die "Must provide catalog linker names within base camp or type local-config!\n"
                unless defined $conf_hash->{catalog_linker_filenames}
                    and $conf_hash->{catalog_linker_filenames} =~ /\S/
            ;
            $conf_hash->{catalog_linker_filenames} = [
                split /[\s,]+/, $conf_hash->{catalog_linker_filenames},
            ];
        }
    }
    return $conf_hash;
}

sub create_camp_path {
    my ($camp, $replace) = @_;
    my $cfg = config_hash( $camp );
    if (-d $cfg->{path}) {
        die "Won't overwriting existing $cfg->{path} directory without replace option.\n"
            unless $replace
        ;
        my $dir = pushd($cfg->{path}) or die "Couldn't chdir $cfg->{path}: $!\n";

        rmtree(
            $conf_hash->{camp_subdirectories},
            0,
            1,
        );
    }
    else {
        mkpath( $conf_hash->{path}, ) or die "Couldn't make camp path: $conf_hash->{path}: $!\n";
    }
}

sub register_camp {
    my ($comment) = @_;
    my $conf = config_hash();
    my $sth = dbh()->prepare(<<'EOL');
INSERT INTO camps (
    camp_number,
    username,
    camp_type,
    comment,
    create_date
)
VALUES (?,?,?,?, CURRENT_TIMESTAMP)
EOL
    $sth->execute( $conf->{number}, camp_user(), type(), $comment, )
        or die "Failed to register camp $conf->{number} in database!\n"
    ;
    $sth->finish;
    return;
}

sub svn_repository() {
    return File::Spec->catfile( type_path(), 'svnrepo', 'trunk', );
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

sub prepare_ic {
    return unless has_ic();
    my $conf = config_hash();

    # Set the main server script as executable.
    do_system("chmod +x $conf->{icroot}/bin/interchange");

    # Prepare the CGI linker.
    do_system("$conf->{icroot}/bin/compile_link -s $conf->{icroot}/var/run/socket --source $conf->{icroot}/src");
    mkdir $conf->{cgidir} or die "error making cgi-bin directory: $!\n";
    do_system("cp -p $conf->{icroot}/src/vlink $conf->{cgidir}/$_")
        for @{$conf->{catalog_linker_filenames}}
    ;
    # revert hardcoded changes to src/ by removing it, then re-fetching from Subversion
    my $dir = pushd( "$conf->{icroot}/src" ) or die "Couldn't chdir $conf->{icroot}: $!\n";
    my @files = ('tlink.pl', 'vlink.pl',);
    unlink(@files) == @files or die "Couldn't unlink one or more files: $!\n";
    do_system('svn up');
    type_message('prepare_ic');
    return;
}

sub prepare_apache {
    my $conf = config_hash();
    # create empty directories
    mkpath([ map { File::Spec->catfile( $conf->{httpd_path}, $_, ) } qw( conf logs run ) ]);

    # symlink to system-wide Apache modules
    symlink $conf->{httpd_lib_path}, File::Spec->catfile( $conf->{httpd_path}, 'modules', )
        or die "Couldn't symlink Apache modules directory\n"
    ;

    # Create SSL certificate
    my $crt_path = File::Spec->catfile( $conf->{httpd_path}, 'conf', 'ssl.crt', );
    mkpath( $crt_path );

    my $tmpfile = File::Temp->new(UNLINK => 0,);
    $tmpfile->print(<<EOF);
[ req ]
distinguished_name = req_distinguished_name
attributes         = req_attributes
prompt             = no

[ req_distinguished_name ]
C                 = US
ST                = New York
L                 = New York
O                 = End Point Corporation
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
            File::Spec->catfile( type_path(), 'etc', 'camp.key', ),
            File::Spec->catfile( $crt_path, "$conf->{hostname}.crt", ),
        ),
    );

    unlink($tmpfile) or die "Error unlinking $tmpfile: $!\n";
    type_message('prepare_apache');
    return;
}

sub install_templates {
    my $conf = config_hash();
    my $template_path = File::Spec->catfile( type_path(), 'etc', );
    local $/;
    for my $file (@edits) {
        my $source_path = File::Spec->catfile( $template_path, $file, );
        print "Interpolating tokenized template file '$source_path'...";
        open(my $INFILE, '<', $source_path) or die "Failed to open template file '$source_path': $!\n";
        my $template = <$INFILE>;
        $template = substitute_hash_tokens(
            $template,
            $conf,
        );
        close $INFILE;
        my $parent_path = my $target_path = File::Spec->catfile( $conf->{path}, $file, );
        $parent_path =~ s:/[^/]+$::;
        print " installing to '$target_path'.\n";
        mkpath( $parent_path );
        open(my $OUTFILE, '>', $target_path) or die "Failed writing configuration file '$target_path': $!\n";
        print $OUTFILE $template;
        close $OUTFILE;
    }
    type_message('install_templates');
}

sub prepare_rails {
    # not sure if anything needs to be done here, as all that really needs doing
    # should get addressed by configuration files.  So it's a no-op for now.
    return;
}

sub roles {
    parse_roles() unless defined $roles;
    return sort { $a cmp $b } keys %$roles;
}

sub role_password {
    my $role = shift;
    parse_roles() unless defined $roles;
    my $role_hash = $roles->{$role};
    die "Cannot find/generate password for unknown role '$role'!\n"
        unless defined $role_hash
    ;
    if (! $role_hash->{password}) {
        my $config = config_hash();
        $config->{"db_role_${role}_pass"}
            = $role_hash->{password}
            = generate_nice_password()
        ;
    }
    return $role_hash->{password} ||= generate_nice_password();
}

sub role_sql {
    my $role = shift;
    parse_roles() unless defined $roles;
    my $role_hash = $roles->{$role};
    die "Cannot find SQL for unknown role '$role'!\n"
        unless defined $role_hash
    ;
    die "Role '$role' has no SQL statement!\n" unless $role_hash->{sql};
    return $role_hash->{parsed_sql} ||= parse_role_sql( $role_hash );
}

sub parse_roles {
    $roles = {};
    my $path = roles_path();
    opendir(my $DIR, roles_path()) or die "Failed to open roles path '$path': $!\n";
    local $/;
    for my $role (grep /^\w+$/, readdir($DIR)) {
        open(my $ROLE, '<', File::Spec->catfile( $path, $role ))
            or die "Failed to open role file '$role': $!\n"
        ;
        $roles->{$role} = {
            role    => $role,
            sql     => <$ROLE>,
        };
        close $ROLE;
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
    return substitute_hash_tokens( $role->{sql}, \%data, '', );    
}

sub _prepare_database_vars {
    my ($conf, $roles, $sources, $names) = @_;
    @$roles = roles();
    @$sources = @{ $conf->{db_source_scripts} };
    @$names = @{ $conf->{db_dbnames} };

    die "There are no roles configured for this camp type!  Cannot prepare database.\n"
        unless @$roles
    ;
    die "There are no source scripts for this camp type!  Cannot prepare database.\n"
        unless @$sources
    ;
    die "There are no database named specified for this camp type!  Cannot prepare database.\n"
        unless @$names
    ;
    return;
}

sub _verify_camp_path {
    my $conf = shift;
    die "Camp '$conf->{name}' does not appear to have been created; please create it first.\n"
        unless -d $conf->{path}
    ;
    return 1;
}

sub _database_exists_check {
    my ($conf, $replace) = @_;

    return 1 unless -d $conf->{db_path};    
    die "Database already exists in $conf->{db_path}; must specify 'replace' to overwrite it.\n"
        unless $replace
    ;
    _db_type_dispatcher( '_database_running_check' )->( @_ );
    # remove old database's binary data.
    rmtree($conf->{db_path}, 0, 1,);
}

sub _database_running_check_pg {
    my $conf = shift;
    # check for running Postmaster on this database.
    if (system("pg_ctl status -D $conf->{db_data}") == 0) {
        # stop running postgres
        system("pg_ctl stop -D $conf->{db_data} -m fast") == 0
            or die "Error stopping running Postgres instance!\n"
        ;
    }
    return 1;
}

sub _database_running_check_mysql {
    my $conf = shift;
    # check for running MySQL on this database.
    if (system("mysqladmin --defaults-file=$conf->{db_my_conf} ping") == 0) {
        # stop running MySQL
        my $opts = camp_mysql_options( user => 'root', no_database => 1, config => $conf );
        system("mysqladmin $opts shutdown")
            or die "Error stopping running MySQL instance!\n"
        ;
    }
    return 1;
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
        eval "use YAML::Syck ()" if ! $yaml_run++;
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
    my $postgres_pass = $conf->{db_pg_postgres_pass} = generate_nice_password();
    my $pass_file_tmp = File::Temp->new( UNLINK => 0, DIR => $conf->{path} );
    $pass_file_tmp->print( "$conf->{db_host}:$conf->{db_port}:*:postgres:$postgres_pass\n" );
    for my $role (@$roles) {
        my $pass = role_password( $role );
        $pass_file_tmp->print("$conf->{db_host}:$conf->{db_port}:$_:$role:$pass\n")
            for @$dbnames
        ;
    }
    $pass_file_tmp->print($old_pass_data);
    $pass_file_tmp->close or die "Couldn't close $pass_file_tmp: $!\n";
    rename "$pass_file_tmp", $pass_file
        or die "Couldn't rename $pass_file_tmp to $pass_file: $!\n"
    ;
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
        or die "Couldn't rename $tmp_file to $file_name: $!\n"
    ;
    return 1;
}

sub _initialize_camp_database {
    return _db_type_dispatcher( '_initialize_camp_database' )->(@_);
}

sub _initialize_camp_database_pg {
    my $conf = shift;
    
    my $postgres_pass = $conf->{db_pg_postgres_pass} or die "No password determined for postgres user!\n";
    # Run initdb to make new database cluster.
    my $tmp = File::Temp->new( UNLINK => 0, );
    $tmp->print( "$postgres_pass\n" );
    $tmp->close or die "Couldn't close $tmp: $!\n";
    my @args = (
        "-D $conf->{db_data}",
        '-n',
        "-U postgres --pwfile=$tmp -A md5",
    );
    push @args, "-E $conf->{db_encoding}"
        if $conf->{db_encoding}
    ;
    push @args, "--locale=$conf->{db_locale}"
        if $conf->{db_locale}
    ;
    my $cmd = 'initdb ' . join(' ', @args);
    print "Preparing database cluster:\n$cmd\n";
    system($cmd) == 0 or die "Error executing initdb!\n";
    unlink $tmp or die "Error unlinking $tmp: $!\n";
    return 1;
}

sub _initialize_camp_database_mysql {
    my $conf = shift;
    my $cmd = "mysql_install_db --datadir=$conf->{db_data}";
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
    open my $CONF, '>>', $conf->{db_conf} or die "Could not append to $conf->{db_conf}: $!\n";
    print $CONF $template;
    close $CONF or die "Couldn't close $conf->{db_conf}: $!\n";
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
    my $cmd = "psql -p $conf->{db_port} -U $opt{user} -d $opt{database}";
    print "Connecting to Postgres: $cmd\n";
    open my $PSQL, "| $cmd"
        or die "Error opening pipe to psql: $!\n"
    ;
    return $PSQL;
}

sub _db_connect_mysql {
    my %opt = @_;
    my $conf = config_hash();
    # use the -n (unbuffered) option to flush the buffer per query (necessary in a pipeline)
    my $cmd = 'mysql ' . camp_mysql_options(%opt);
    print "Connecting to MySQL: $cmd\n";
    open my $MYSQL, "| $cmd"
        or die "Error opening pipe to mysql: $!\n"
    ;
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

    close $SESSION or die "Error piping command to psql: $!\n";
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
        my $script_file = File::Spec->catfile( type_path(), $script, );
        my $cmd = _import_db_cmd( $script_file, $conf );
        print "Processing script '$script':\n$cmd\n";
        system($cmd) == 0 or die "Error importing data\n";
    }

}

sub _import_db_cmd {
    return _db_type_dispatcher('_import_db_cmd')->(@_);
}

sub _import_db_cmd_pg {
    my ($script, $conf) = @_;
    return "psql -p $conf->{db_port} -U postgres -d postgres -f $script";
}

sub _import_db_cmd_mysql {
    my ($script, $conf) = @_;
    return 'mysql ' . camp_mysql_options() . " < $script";
}

sub prepare_database {
    my $replace = shift;
    my $conf = config_hash();
    my (@roles, @sources, @dbnames);
    _prepare_database_vars( $conf, \@roles, \@sources, \@dbnames );

    _verify_camp_path( $conf );

    # check for extant database
    _database_exists_check( $conf, $replace );

    # initialize database paths including base, data, tmp
    mkdir $conf->{db_path} or die "Could not make database path '$conf->{db_path}': $!\n";
    mkdir $conf->{db_data} or die "Couldn't make database data path '$conf->{db_data}': $!\n"
        unless -d $conf->{db_data}
    ;
    mkdir $conf->{db_tmpdir} or die "Couldn't make database tmp/ path '$conf->{db_tmpdir}': $!\n"
        unless -d $conf->{db_tmpdir}
    ;

    _prepare_camp_database_client_settings( $conf, \@roles, \@dbnames );

    _initialize_camp_database( $conf );

    _render_database_config( $conf );

    # Start new camp database instance
    db_control( 'start' ) or die "Error starting new camp database!\n";

    # Sleep for a few seconds to give the server time to set up if necessary
    sleep(5);

    _prepare_camp_database_roles( \@roles, $conf );

    _import_camp_data( \@sources, $conf );

    type_message('prepare_database'); 
    return;
}

sub do_system {
	my ($cmd) = @_;
	print $cmd, $/;
	my $exit = system($cmd) >> 8;
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
    $services{ic}       = \&ic_control if has_ic();
    $services{rails}    = \&rails_control if has_rails();
    $services{$dbtype}  = $db_services{$dbtype};

    my @services = grep { defined $services{$_} } qw(
        httpd
        pg
        mysql
        db
        ic
        rails
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
    do_cmd_soft( "cd $conf->{railsdir} && ($cmd)" ) == 0
        and return 1
    ;
    return undef;
}

sub ic_control {
    my $action = shift;

}

sub db_control {
    return _db_type_dispatcher( '_db_control' )->(@_);
}

sub _db_control_mysql {
    my $action = shift;
    my $conf = config_hash();
    die "Need db_data definition!\n"
        unless defined $conf->{db_data}
        and $conf->{db_data} =~ /\S/
    ;
    my $cmd;
    $action = lc($action);
    if ($action eq 'restart') {
        _db_control_mysql( 'stop' );
        return _db_control_mysql( 'start' );
    }
    elsif ($action eq 'start') {
        $cmd = "nohup mysqld_safe --defaults-file=$conf->{db_conf} &";
    }
    else {
        $action = 'shutdown' if $action eq 'stop';
        my $opt = camp_mysql_options( no_database => 1, user => 'root' );
        $cmd = "mysqladmin --defaults-file=$conf->{db_conf} $opt $action";
    }
    do_cmd_soft($cmd) == 0
        and return 1
    ;
    return undef; 
}

sub _db_control_pg {
    my $action = shift;
    my $conf = config_hash();
    die "Need db_data definition!\n"
        unless defined $conf->{db_data}
        and $conf->{db_data} =~ /\S/
    ;
    do_cmd_soft("pg_ctl -D $conf->{db_data} -l $conf->{db_tmpdir}/pgstartup.log -m fast -w $action") == 0
        and return 1
    ;
    return undef;
}

sub httpd_control {
    my $action = shift;
    my $conf = config_hash();
    die "Need httpd_cmd_path definition!\n"
        unless defined $conf->{httpd_cmd_path}
        and $conf->{httpd_cmd_path} =~ /\S/
    ;
    die "Need httpd_path definition!\n"
        unless defined $conf->{httpd_path}
        and $conf->{httpd_path} =~ /\S/
    ;
    do_cmd_soft("$conf->{httpd_cmd_path} -d $conf->{httpd_path} -k $action") == 0
        and return 1
    ;
    return undef;
}

sub do_cmd_soft {
    my $cmd = shift;
    print "$cmd\n";
    return system($cmd);
}

sub type_message {
    my $type = shift;
    my $message_file = File::Spec->catfile( type_path(), "${type}_message", );
    return unless -f $message_file;
    local $/;
    open my $MSG, '<', $message_file or die "Failed to open message file $message_file: $!\n";
    print "\n" . <$MSG> . "\n";
    close $MSG;
    return 1;
}

sub camp_list {
    my %opt = @_;
    die "You must specify a camp type!\n"
        unless $opt{type}
        or $opt{all}
    ;
    my (@args, $where);
    if ($opt{type}) {
        $where = "\n\tAND c.camp_type = ?";
        @args = ($opt{type});
    }

    my $sth = dbh()->prepare(<<SQL);
SELECT c.*, u.name, u.email, c.create_date::DATE as create_date_display
FROM camps c, camp_users u
WHERE c.username = u.username$where
ORDER BY c.camp_number ASC
SQL

    my @result;
    $sth->execute(@args);
    my @config_keys = qw(
        http_port
        https_port
        hostname
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

1;
