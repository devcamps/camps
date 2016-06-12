package Camp::LVM;

# Routines that interact with LVM for camp database snapshots

use strict;
use warnings;
use lib '/home/camp/lib';
use Camp::Master;

sub does_lv_exist {
    my $conf = shift;
    my $vg = $conf->{lvm_vg};
    my $lv = $conf->{use_origin} ? $conf->{lvm_origin_name} : $conf->{lvm_snapshot_name};
    my $name;

    if ($conf->{use_origin}) {
        $name = "$vg-$lv";
    }
    else {
        my $username = $conf->{system_user};
        my $number = $conf->{number};
        $name = "$vg-snap-$username-camp$number";
    }

    my @output = `/usr/sbin/lvs --noheading --separator=- -ovg_name,lv_name`;
    if (grep { /\b$name\b/ } @output) {
        return 1;
    }
    return 0;
}

sub is_lv_active {
    my $conf = shift;
    my $vg = $conf->{lvm_vg};
    my $lv = $conf->{use_origin} ? $conf->{lvm_origin_name} : $conf->{lvm_snapshot_name};

    my @output = `/usr/sbin/lvscan | grep /dev/$vg/$lv`;
    if (grep { /INACTIVE/ } @output) {
        return 0;
    }
    return 1;
}

sub does_mount_exist {
    my $conf = shift;
    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};

    my $cmd = "/usr/bin/mountpoint -q $mount_point";
    if (system($cmd) == 0) {
        return 1;
    }
    return;
}

sub local_hash {
    my $local_hash = shift;
    for my $conf_file (
        map { File::Spec->catfile($_, 'local-config') } Camp::Master::base_path(), Camp::Master::type_path()
    ) {
        next unless -f $conf_file;
        open(my $CONF, '<', $conf_file) or die "Couldn't open configuration file $conf_file: $!\n";
        while (my $line = <$CONF>) {
            chomp($line);
            next unless $line =~ /\S/;
            next if $line =~ /^\s*#/;
            if (my ($key,$val) = $line =~ /^\s*(\w+):(.*?)\s*$/) {
                $local_hash->{$key} = Camp::Master::substitute_hash_tokens($val, $local_hash);
            }
            else {
                warn "Skipping invalid line in file $conf_file: $line\n";
                next;
            }
        }
        close $CONF or die "Error closing $conf_file: $!\n";
    }
    $local_hash->{base_path} = Camp::Master::base_path();
    $local_hash->{type_path} = Camp::Master::type_path();
    return $local_hash;
}

sub status_lv {
    my $conf = shift;
    my $vg = $conf->{lvm_vg};
    my $lv = $conf->{lvm_origin_name};
    my $mount_point = $conf->{lvm_origin_data} or die "Missing lvm_origin_data from config";

    use_origin($conf);

    if (!does_lv_exist($conf)) {
        die "$lv does not exist.";
    }
    elsif (!does_mount_exist($conf)) {
        system("/bin/mount /dev/$vg/$lv $mount_point");
        if ($? >> 8) {
            die "Error running mount! exit code: " . ($? >> 8);
        }
        print "Mounting $mount_point\n";
    }
    return;
}

sub create_lv {
    my $conf = shift;
    my $vg          = $conf->{lvm_vg};
    my $lv          = $conf->{use_origin} ? $conf->{lvm_origin_name} : $conf->{lvm_snapshot_name};
    my $lv_size     = $conf->{use_origin} ? $conf->{lvm_origin_size} : $conf->{lvm_snapshot_size};
    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};

    if (does_lv_exist($conf)) {
        die "/dev/$vg/$lv already exists.";
    }

    my @args = (
        '/usr/sbin/lvcreate',
        "-L $lv_size",
        "-n $vg/$lv",
    );
    if ($conf->{use_origin}) {
        push @args, "-y -Wy -Zy";
    }
    else {
        push @args, "-s $vg/$conf->{lvm_origin_name}";
    }
    my $cmd = join(' ', @args);
    print "Creating:\n$cmd\n";
    system($cmd) == 0 or die "Error executing lvcreate!\n";
    if ($conf->{use_origin}) {
        $cmd = "mkfs.ext4 -m 0 /dev/$vg/$lv";
        system($cmd) == 0 or die "Error executing $cmd\n";
    }
    mount_fs($conf);

    return;
}

sub use_origin {
    my ($conf, $function) = @_;
    $conf->{use_origin} ||= 1;
    return;
}

sub origin_initdb {
    my $conf = shift;

    _pre_origin_initdb($conf);

    my @args = (
        '/usr/bin/initdb',
        "-D $conf->{lvm_origin_data}",
        '-n',
        '-U', 'postgres',
    );

    my $cmd = join(' ', @args);
    $cmd = "su camp -c '$cmd'";
    system($cmd) == 0 or die "Error executing $cmd\n";

    _post_origin_initdb($conf);

    return;
}

sub _pre_origin_initdb {
    my $conf = shift;
    # lost+found gets created by mkfs and needs to get removed since initdb requires an empty directory
    rmdir "$conf->{lvm_origin_data}/lost+found" or die "Error removing lost+found!\n";
    return;
}

sub _post_origin_initdb {
    my $conf = shift;

    # append psql/postgres config to origin
    my $db_conf = File::Spec->catfile($conf->{lvm_origin_data}, 'postgresql.conf');
    my $append = File::Spec->catfile('/home/camp/pgsql/', 'postgresql.conf');

    # camp_db_port is not set because we are using usring origin
    # we inject lvm_origin_port to populate postgresql.conf's token
    $conf->{db_port} = $conf->{lvm_origin_port};
    $conf->{db_tmpdir} = '/tmp';

    open(my $out, '>>', $db_conf) or die "Failed writing configuration file '$db_conf': $!\n";

    open(my $in, '<', $append) or die "Failed opening configuration file '$append': $!\n";
    while (my $line = <$in>) {
        my $template = $line;
        $template = Camp::Master::substitute_hash_tokens(
            $line,
            $conf,
        );
        print $out $template;
    }
    close $in;
    close $out or die "Error closing $db_conf: $!\n";

    return;
}

sub analyze_db {
    my $conf = shift;
    my $port = $conf->{use_origin} ? $conf->{lvm_origin_port} : $conf->{camp_db_port};

    my @args = (
        '/usr/bin/vacuumdb',
        '-h localhost',
        "-p $port",
        '-U', 'postgres',
        '-a',
        '-Z',
     );

    my $cmd = join(' ', @args);
    system($cmd) == 0 or die "Error executing $cmd\n";
    return;
}

sub _database_shutdown {
    my $conf = shift;
    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};
    my $username    = $conf->{use_origin} ? 'camp' : $conf->{system_user};

    # check for running Postmaster on this database.
    if (system("pgrep -u $username -f $mount_point") == 0) {
        # stop running postgres
        my $cmd = "pkill -u $username -f $mount_point";
        #system("su $username -c '$cmd'") == 0
        system($cmd) == 0
            or die "Error stopping running Postgres instance!\n";
        sleep 4;
    }
    return;
}

sub _db_control_pg {
    my ($conf, $action) = @_;
    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};
    my $logdir = $conf->{type_path};
    # FIXME: add option for camp

    if ($action eq 'stop') {
        # we use a little more agressive function to stop
        _database_shutdown($conf);
        return;
    }

    my $cmd = "PGHOST=$conf->{db_host} pg_ctl -D $mount_point -l $logdir/pgstartup.log -m fast -w $action";
    my $result = system("su camp -c '$cmd'");
    $result == 0 and return 1;
    return;
}

sub mount_active {
    my $conf = shift;

    # in certain circumstances the snapshot can become unmounted before postgres is shutdown
    # this will leave the snapshot in a stuck state unable to be removed because the PG
    # process is still using the mount.  As it is unmounted we have no pid file so we
    # use pkill instead.  To test this we check if the config file exists in the data dir.

    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};
    my $pg_hba_file = File::Spec->catfile($mount_point, 'pg_hba.conf');
    -e $pg_hba_file and return 1;
    return;
}

sub remove_lv {
    my $conf = shift;
    my $vg = $conf->{lvm_vg};
    my $lv = $conf->{use_origin} ? $conf->{lvm_origin_name} : $conf->{lvm_snapshot_name};
    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};

    if ( ! does_lv_exist($conf) ) {
        print "/dev/$vg/$lv does not exist.\n";
        return;
    }

    unless (mount_active($conf)) {
        print "$mount_point is mounted but contains no data.\n";
        _database_shutdown($conf);
    }

    umount_fs($conf);

    my @args = (
        '/usr/sbin/lvremove',
        "-f /dev/$vg/$lv",
    );
    my $cmd = join(' ', @args);
    print "Removing /dev/$vg/$lv:\n$cmd\n";
    system($cmd) == 0 or die "Error executing lvremove!\n";

    return;
}

sub umount_fs {
    my $conf = shift;
    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};

    if (! does_mount_exist($conf)) {
        return;
    }

    # unmount the camp volume
    system("/bin/umount -l $mount_point");
    if ($? > 0) { warn "Failed to umount $mount_point"; }
    my $max_wait = 10;
    while ( -d "$mount_point/base" && $max_wait-- ) {
        sleep 2;
        print "Waiting for mount dir to unmount: $mount_point/base\n";
    }
    return;
}

sub mount_fs {
    my $conf = shift;
    my $vg          = $conf->{lvm_vg};
    my $lv          = $conf->{use_origin} ? $conf->{lvm_origin_name} : $conf->{lvm_snapshot_name};
    my $mount_point = $conf->{use_origin} ? $conf->{lvm_origin_data} : $conf->{db_data};
    my $username    = $conf->{use_origin} ? 'camp' : $conf->{system_user};

    if (does_mount_exist($conf)) {
        return;
    }
    elsif (!mount_active($conf)) {
        print "$mount_point is mounted but contains no data.\n";
        _database_shutdown($conf);
    }

    # although the mount may not exist it could be stuck by postgres

    if (! does_lv_exist($conf)) {
        die "/dev/$vg/$lv does not exists";
    }
    elsif ((! is_lv_active($conf)) && (! $conf->{use_origin})) {
        die "Snapshot INACTIVE replace with refresh-camp --db.\n";
        return;
    }

    my $rc = system("/bin/mount /dev/$vg/$lv $mount_point");
    if ($? >> 8) {
        die "Error running mount! exit code: ". ($? >> 8);
    }
    print "Mounting $mount_point.\n";

    # Check for double mount
    my @mounts = `/bin/mount | grep '$mount_point'`;
    if (scalar(@mounts) > 1) {
        print "Umnounting duplicate mount $mount_point.\n";
        system("/bin/umount $mount_point");
        sleep 2;
    }
    unless ($conf->{use_origin}) {
        my $max_wait = 10;
        while (! -d "$mount_point/base" && $max_wait--) {
            sleep 2;
            print "Waiting for mount dir to exist: $mount_point/base\n";
        }
        if (! -d "$mount_point/base") {
            die "Failed to mount $mount_point\n";
        }
    }
    system("chown -R $username: $mount_point") == 0
        or die "Error running chown";

    return;
}

sub resize_snapshots {
    my $conf = shift;
    my $camp_number = $conf->{number};
    my $threshold = 50;  # percentage
    my $increase_by = $conf->{lvm_snapshot_size} || '3G';
    my $verbose = 1;

    my @args = (
        '/usr/sbin/lvs',
        "--separator ,",
        "--noheadings",
        "-o",
        "vg_name,lv_name,seg_size,data_percent",
    );
    my $cmd = join(' ', @args);
    my @data = `$cmd`;
    chomp @data;
    die "No lvs output" unless @data;

    # if given a camp number, then look at that camp only
    if ($camp_number && $camp_number =~ /^\d+$/) {
        @data = grep { /^.*?\bsnap\-\w+\-camp$camp_number\b.*$/ } @data;
    }

    my @lvs;

    for my $line (@data) {
        $line =~ s/^\s+//;
        my @fields = split(/,/, $line);
        push @lvs, \@fields;
    }

    # Loop over each snapshot
    for my $c (@lvs) {
        my ($group, $vol, $size, $consumed) = @$c;
        print "Checking @{$c}\n" if $verbose;

        # validate lvs data
        if  (!($group && $vol && $size)) {
            print "lvs line not a valid snapshot skipping...\n";
            next;
        }
        elsif ($vol !~/snap\-\w+-camp\d/) {
            print "lvs line not a camp snapshot skipping...\n";
            next;
        }
        elsif ($consumed > $threshold) {
            print "Increasing size of snapshot $vol (currently $consumed\% of $size, adding $increase_by)\n";
            my $cmd = "/usr/sbin/lvresize -L +$increase_by $group/$vol";
            system($cmd);
        }
        else {
            print "Snapshot $vol within threshold (currently $consumed\% of $size.)\n";
        }
    }
    return;
}

1;
