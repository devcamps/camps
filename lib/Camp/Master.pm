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
    server_control
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

sub pgsql_path {
    return File::Spec->catfile( type_path(), 'pgsql', );
}

sub roles_path {
    return File::Spec->catfile( pgsql_path(), 'roles', );
}

sub pgconfig_path {
    -f $_ && return($_)
        for map { File::Spec->catfile( $_, 'postgresql.conf', ) } (
                pgsql_path(),
                File::Spec->catfile( base_path(), 'pgsql', ),
            )
    ;
    die "Cannot locate pgsql/postgresql.conf in type definition or base camp user!\n";
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

sub get_next_camp_number {
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
        $conf_hash->{pg_host}       = 'localhost';
        $conf_hash->{pg_port}       = 8900 + $camp_number;
        $conf_hash->{pg_path}       = File::Spec->catfile( $conf_hash->{path}, 'pgsql', );
        $conf_hash->{pg_encoding}   = 'UTF-8',
#        $conf_hash->{pg_locale}     = undef; 
        $conf_hash->{pg_data}       = File::Spec->catfile( $conf_hash->{pg_path}, 'data', );
        $conf_hash->{pg_tmpdir}     = File::Spec->catfile( $conf_hash->{pg_path}, 'tmp', );
        $conf_hash->{pg_log}        = File::Spec->catfile( $conf_hash->{pg_tmpdir}, 'postgresql.log', );
        $conf_hash->{pg_conf}       = File::Spec->catfile( $conf_hash->{pg_data}, 'postgresql.conf', );
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
        $conf_hash->{pg_source_scripts} = [
            split /[\s,]+/, $conf_hash->{pg_source_scripts} || ''
        ];
        $conf_hash->{pg_dbnames} = [
            split /[\s,]+/, $conf_hash->{pg_dbnames} || ''
        ];
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
    comment
)
VALUES (?,?,?,?)
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
        $config->{"pg_role_${role}_pass"}
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

sub prepare_database {
    my $replace = shift;
    my $conf = config_hash();
    my @roles = roles();
    my @sources = @{ $conf->{pg_source_scripts} };
    my @dbnames = @{ $conf->{pg_dbnames} };

    die "There are no roles configured for this camp type!  Cannot prepare database.\n"
        unless @roles
    ;
    die "There are no source scripts for this camp type!  Cannot prepare database.\n"
        unless @sources
    ;
    die "There are no database named specified for this camp type!  Cannot prepare database.\n"
        unless @dbnames
    ;

    # verify camp's existence
    die "Camp '$conf->{name}' does not appear to have been created; please create it first.\n"
        unless -d $conf->{path}
    ;

    # check for extant database
    if (-d $conf->{pg_path}) {
        die "Database already exists in $conf->{pg_path}; must specify 'replace' to overwrite it.\n"
            unless $replace
        ;
        # check for running Postmaster on this database.
        if (system("pg_ctl status -D $conf->{pg_data}") == 0) {
            # stop running postgres
            system("pg_ctl stop -D $conf->{pg_data} -m fast") == 0
                or die "Error stopping running Postgres instance!\n"
            ;
        }
        # remove old database's binary data.
        rmtree($conf->{pg_path}, 0, 1,);
    }

    mkdir $conf->{pg_path} or die "Could not make Postgres path '$conf->{pg_path}': $!\n";
    mkdir $conf->{pg_data} or die "Couldn't make Postgres data path '$conf->{pg_data}': $!\n"
        unless -d $conf->{pg_data}
    ;

    # create the tmp/ directory for logs and other stuff that eludes the backup
    mkdir $conf->{pg_tmpdir} or die "Couldn't make Postgres tmp/ path '$conf->{pg_tmpdir}': $!\n"
        unless -d $conf->{pg_tmpdir}
    ;

    # Read any existing ~/.pgpass file
    my $pass_file = File::Spec->catfile( $conf->{root}, '.pgpass', );
    my $old_pass_data = '';
    if (-f $pass_file) {
        open my $IN, '<', $pass_file or die "Can't read $pass_file: $!\n";
        while (<$IN>) {
            next if /^$conf->{pg_host}:$conf->{pg_port}:/;
            $old_pass_data .= $_;
        }
        close $IN or die "Couldn't close $IN: $!\n";
    }
    my $postgres_pass = generate_nice_password();
    my $pass_file_tmp = File::Temp->new( UNLINK => 0, );
    $pass_file_tmp->print( "$conf->{pg_host}:$conf->{pg_port}:*:postgres:$postgres_pass\n" );
    for my $role (@roles) {
        my $pass = role_password( $role );
        $pass_file_tmp->print("$conf->{pg_host}:$conf->{pg_port}:$_:$role:$pass\n")
            for @dbnames
        ;
    }
    $pass_file_tmp->print($old_pass_data);
    $pass_file_tmp->close or die "Couldn't close $pass_file_tmp: $!\n";
    rename "$pass_file_tmp", $pass_file
        or die "Couldn't rename $pass_file_tmp to $pass_file: $!\n"
    ;

    # Run initdb to make new database cluster.
    my $tmp = File::Temp->new( UNLINK => 0, );
    $tmp->print( "$postgres_pass\n" );
    $tmp->close or die "Couldn't close $tmp: $!\n";
    my @args = (
        "-D $conf->{pg_data}",
        '-n',
        "-U postgres --pwfile=$tmp -A md5",
    );
    push @args, "-E $conf->{pg_encoding}"
        if $conf->{pg_encoding}
    ;
    push @args, "--locale=$conf->{pg_locale}"
        if $conf->{pg_locale}
    ;
    my $cmd = 'initdb ' . join(' ', @args);
    print "Preparing database cluster:\n$cmd\n";
    system($cmd) == 0 or die "Error executing initdb!\n";
    unlink $tmp or die "Error unlinking $tmp: $!\n";

    # set up camp-specific configuration
    open my $TEMPLATE, '<', pgconfig_path() or die "Failed to open postgresql.conf template: $!\n";
    my $template = do { local $/; <$TEMPLATE> };
    close $TEMPLATE or die "Failed to close postgresql.conf template!\n";
    $template = substitute_hash_tokens(
        $template,
        {
            map { $_ => $conf->{$_} }
            grep /^pg_/,
            keys %$conf
        },
    );
    open my $CONF, '>>', $conf->{pg_conf} or die "Could not append to $conf->{pg_conf}: $!\n";
    print $CONF $template;
    close $CONF or die "Couldn't close $conf->{pg_conf}: $!\n";

    # Start Postgres on new cluster
    my $startlog = File::Spec->catfile( $conf->{pg_tmpdir}, 'pgstartup.log', );
    system("pg_ctl start -D $conf->{pg_data} -l $startlog -w") == 0
        or die "Error starting Postgres on new cluster!\n"
    ;

    # Create regular database roles
    $cmd = "psql -p $conf->{pg_port} -U postgres -d postgres";
    print "Command: $cmd\n";
    open my $PSQL, "| $cmd"
        or die "Error opening pipe to psql: $!\n"
    ;
    for my $role (@roles) {
        my $sql = role_sql( $role );
        print "SQL: $sql\n";
        print {$PSQL} $sql, "\n;\n";
    }
    close $PSQL or die "Error piping command to psql: $!\n";

    # Import data
    for my $script (@sources) {
        my $script_file = File::Spec->catfile( type_path(), $script, );
        $cmd = "psql -p $conf->{pg_port} -U postgres -d postgres -f $script_file";
        print "Processing script '$script':\n$cmd\n";
        system($cmd) == 0 or die "Error importing data\n";
    }

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
        rails   => \&rails_control,
        ic      => \&ic_control,
        pg      => \&pg_control,
        httpd   => \&httpd_control,
    );

    delete $services{ic} unless has_ic();
    delete $services{rails} unless has_rails();
    my @services = grep { defined $services{$_} } qw(
        httpd
        pg
        ic
        rails
    );

    die "Invalid action '$action' specified!\n" unless $actions{$action};
    my @services_to_start;
    if ($service eq 'all') {
        @services_to_start = @services;
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

sub pg_control {
    my $action = shift;
    my $conf = config_hash();
    die "Need pg_data definition!\n"
        unless defined $conf->{pg_data}
        and $conf->{pg_data} =~ /\S/
    ;
    do_cmd_soft("pg_ctl -D $conf->{pg_data} -l $conf->{pg_tmpdir}/pgstartup.log -m fast -w $action") == 0
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
