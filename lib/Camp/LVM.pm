package Camp::LVM;

# Routines that interact with LVM, or routines needed to support them.

use strict;
use warnings;
use Camp::Master;


sub does_snapshot_exist {
    my $conf = shift;
    my $shapshot_size = $conf->{lvm_snapshot_size} || '3G';
    my $username = $conf->{system_user};
    my $number = $conf->{number};
    my $snapshot_name = "snap-$username-camp$number";
    my @lvs_output = `/usr/sbin/lvs`;
    if (grep { /\b$snapshot_name\b/ } @lvs_output) {
        return 1;
    }
    return 0;
}

sub update_fstab {
    my ($conf, $action, $username, $number) = @_;
    $action ||= 'add';

    # trim out all camp snapshots
    my $fstab_orig = `cat /etc/fstab`;
    my $fstab      = $fstab_orig;
    $fstab         =~ s/^.*?snap\-.*?camp\d\d.*$//mg;  # Remove all previous snapshot entries

    # Trim off any white space at the end of the file
    $fstab  =~ s/[\s\r\n]+$//s;
    $fstab .= $/;

    # Rebuild the list of all snapshots
    my $sth = Camp::Master::dbh()->prepare('SELECT username, camp_number FROM camps ORDER by camp_number');
    $sth->execute();

    my $need_to_add = 0;
    if ($action eq 'add' && $username && defined $number) {
        $need_to_add = 1;
    }
    my $lvm_origin_volume = $conf->{lvm_origin_volume} or die "Missing lvm_origin_volume from config, cannot clone LVM volume.";
    my ($vol_group) = split('/', $lvm_origin_volume);
    my $fstab_fmt   = '/dev/%s/%s       /home/%s/camp%s/pgsql/data        ext4    defaults        0 0' . "\n";

    while (my ($u,$n) = $sth->fetchrow_array) {
	if ($action eq 'remove' && $username eq $u && $number == $n) {
	    print "Removing camp$n for $u from fstab.\n";
	    next;
	}
	my $snapshot_name = "snap-$u-camp$n";
	if (-e "/dev/$vol_group/$snapshot_name") {
	    #print "Adding to fstab: /dev/$vol_group/$snapshot_name\n";  ## DEBUG
	    $fstab .= sprintf($fstab_fmt, $vol_group, $snapshot_name, $u, $n);

            if ($need_to_add && $u eq $username && $n == $number) {
                $need_to_add = 0;
                print "Re-added mount for $username camp$number\n";
            }
	}
	else {
	    warn "Camp $n for $u in camps database, but LVM snapshot /dev/$vol_group/snap-$u-camp$n does not exist.\n";
	}
	#print "update_fstab(), need_to_add=$need_to_add\n";  ## DEBUG
    }
    $sth->finish;

    if ($need_to_add) {
	print "Adding mount for $username camp$number\n";
	my $snapshot_name = "snap-$username-camp$number";
        if (-e "/dev/$vol_group/$snapshot_name") {
            $fstab .= sprintf($fstab_fmt, $vol_group, $snapshot_name, $username, $number);
        }
        else {
            warn "Camp $number for $username in camps database, but LVM snapshot /dev/$vol_group/snap-$username-camp$number does not exist.\n"; 
        }
    }

    open my $out, '>', '/etc/fstab.new'  or die "Cannot write new fstab file: $!";
    print {$out} $fstab;
    close $out;

    print "Backing up /etc/fstab and putting in place a new one.\n";  ## DEBUG
    system('cp -a /etc/fstab /etc/fstab.bak');
    system('mv /etc/fstab.new /etc/fstab');

    return;
}

sub clone_database {
    my $conf = shift;
    my $lvm_origin_volume = $conf->{lvm_origin_volume} or die "Missing lvm_origin_volume from config, cannot clone LVM volume.";
    my ($vol_group) = split('/', $lvm_origin_volume);

    my $shapshot_size = $conf->{lvm_snapshot_size} || '3G';
    my $username      = $conf->{system_user};
    my $number        = $conf->{number};
    my $snapshot_name = "snap-$username-camp$number";
    if ( does_snapshot_exist($conf) ) {
        die "LVM snapshot already exists for camp $number and user $username";
    }

    my @args = (
        "-L $shapshot_size",
        "-n $snapshot_name",
        "-s $lvm_origin_volume"
    );
    my $cmd = '/usr/sbin/lvcreate '. join(' ', @args);
    print "Creating LVM snapshot:\n$cmd\n";
    system($cmd) == 0 or die "Error executing lvcreate!\n";

    my $db_mount_point = $conf->{db_data};
#    print "db_mount_point=$db_mount_point\n";  ## DEBUG
#    system("/bin/mkdir -p $db_mount_point");
#    system("chown -R $username:$username $db_mount_point");
#    system("echo '$db_mount_point'; ls -la $db_mount_point");
#    system("mount | grep camp");
#    print "db_mount_point $db_mount_point exists.\n"  if ( -d $db_mount_point );  ## DEBUG
#    print "/bin/mount -t ext4 /dev/$vol_group/$snapshot_name $db_mount_point\n";  ## DEBUG
    my $rc = system("/bin/mount -t ext4 /dev/$vol_group/$snapshot_name $db_mount_point");
    if ($? >> 8) {
        die "Error running mount! exit code: ". ($? >> 8);
    }
    sleep 2;
#    print "mount\n";  ## DEBUG
#    system("mount | grep '$conf->{db_path}'");

    # Check for double mount
    # For whatever reason, the mount command above mounts the snapshot
    # twice: once on campXX/pgsql/data, and then again on campXX/pgsql (on top of the other).
    # Still baffled, I just added this work-around.
    my $db_path = $conf->{db_path};
    my @mounts = `/bin/mount | grep '$db_path'`;
    if (scalar(@mounts) > 1) {
	print "Umnounting duplicate mount $db_path\n";
        system("/bin/umount $db_path");
        sleep 2;
#        print "mount\n";  ## DEBUG
#        system("mount | grep '$db_path'");
    }
    my $max_wait = 10;
    while ( ! -d "$db_mount_point/base" && $max_wait-- ) {
        sleep 2;
        print "Waiting for mount dir to exist: $db_mount_point/base\n";
    }
    if (! -d "$db_mount_point/base") {
	die "Uh... we tried to cmount $db_mount_point and it didn't work.\n";
    }
    system("chown -R $username:$username $db_mount_point");

    # Update /etc/fstab with the new mounted camp db so it stays there
    # when the machine reboots
    update_fstab($conf, 'add', $username, $number);
    return;
}

sub remove_database_clone {
    my $conf = shift;
    my $lvm_origin_volume = $conf->{lvm_origin_volume} or die "Missing lvm_origin_volume from config, cannot clone LVM volume.";
    my ($vol_group) = split('/', $lvm_origin_volume);
    #print "vol_group=$vol_group\n";  ## DEBUG

    my $username      = $conf->{system_user};
    my $number        = $conf->{number};
    my $snapshot_name = "snap-$username-camp$number";
    if ( ! does_snapshot_exist($conf) ) {
        die "No LMV snapshot exists for camp $number and username $username to remove.";
    }

    my $db_mount_point = $conf->{db_data};
    print "db_mount_point=$db_mount_point\n";  ## DEBUG

    # unmount the camp volume
    system("/bin/umount -l $db_mount_point");
    if ( $? > 0 ) { warn "Failed to umount $db_mount_point"; }
    my $max_wait = 10;
    while ( -d "$db_mount_point/base" && $max_wait-- ) {
        sleep 2;
        print "Waiting for mount dir to unmount: $db_mount_point/base\n";
    }

    # update fstab
    update_fstab($conf, 'remove', $username, $number);

    # remove the LVM snapshot
    my @args = (
        "-f $vol_group/$snapshot_name",
    );
    my $cmd = '/usr/sbin/lvremove '. join(' ', @args);
    print "Removing LVM snapshot:\n$cmd\n";
    system($cmd) == 0 or die "Error executing lvcreate!\n";

    return;
}

sub resize_snapshots {
    my $conf = shift;
    my $camp_number = $conf->{number};
    my $threshold = 50;  # percentage
    my $increase_by = $conf->{lvm_snapshot_size} || '3G';
    my $verbose = 1;

    my @lvs = `/usr/sbin/lvs | grep snap | grep camp`;
    chomp(@lvs);
    die "No lvs output"  unless (@lvs);

    # if given a camp number, then look at that camp only
    if ($camp_number && $camp_number =~ /^\d+$/) {
	my @tmp  = grep { /^.*?\bsnap\-\w+\-camp$camp_number\b.*$/ } @lvs;
	@lvs     = @tmp;
    }

    # Loop over each camp snapshot
    foreach my $c (@lvs) {
	my ($vol, $group, $size, $consumed) = $c =~ /^\s+(snap\-\w+\-camp\d\d)\s+(\S+)\s+\S+\s+([\d\.]+\w+)\s+\S+\s+([\d\.]+)\s*$/;
	print $c ."\n"  if ($verbose);
	if (! ($vol && $group && $consumed)) {
	    print "Could not regex match lvs line:  $c\n";
	    next;
	}

	if ($consumed > $threshold) {
	    print "Increasing size of snapshot $vol (currently $consumed\% of $size, adding $increase_by)\n";
	    my $cmd = "/usr/sbin/lvresize -L +$increase_by $group/$vol";
	    system($cmd);
	}
    }
    return;
}



1;
