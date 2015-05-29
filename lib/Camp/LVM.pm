package Camp::LVM;

# Routines that interact with LVM, or routines needed to support them.

use strict;
use warnings;
use Camp::Master;

=head1 NAME

Camp::LVM - LVM routines for camp management

=head1 VERSION

1.00

=head1 CAMP LVM DATABASE SNAPSHOT MANAGEMENT

Camps can utilize LVM snapshots for quickly cloning a database for each camp
instead of importing a SQL dump each time.  This requires some setup by the
system administrator to create the needed LVM volume to be used as the "origin"
volume that will be snapshotted.  There are also some needed changes to
/etc/sudoers to allow for running the needed commands to create, update,
remove, mount, and unmount the snapshots.

=head2 Configuration

To use LVM snapshots the following settings can be used in the file local-config.

=over

=item use_lvm_database_snapshots

If using LVM snapshots for cloning databases for each camp, then set this to 'yes'.

=item lvm_snapshot_size

When using LVM snapshots for databases, you can specifiy the initial snapshot size.  Defaults to 3G.  When
running the command `camp_lvm resize` or `camp_lvm resize_all`, camp snapshots may also be increased 
by this same size if their usage exceeds 50%.

=item lvm_origin_volume

The LVM volume name to clone for snapshots.  For example, lvm_origin_volume:vg0/CampOriginDB.

=back

=head2 Sudoers

The following changes should be made to /etc/sudoers to allow the camp user
and all other users to run the needed LVM related commands.  Please alter
any paths as needed.

 Defaults:camp !requiretty
 camp  ALL = (ALL) NOPASSWD: /home/camp/bin/re, /home/camp/bin/camp_lvm, /home/camp/bin/refresh-camp
 
 Defaults:%camp !requiretty
 %camp ALL = (ALL) NOPASSWD: /home/camp/bin/camp_lvm

=head2 Usage

When using LVM snapshots with camps, creating a camp will also create a 
snapshot clone of the database, configure it for your camp, and start it.
Deleting a camp via `rmcamp` will shutdown the database and remove the snapshot.
A refresh of the database via `refresh-camp --db` will shut down the db, remove the
snapshot, and then create it again afresh.

A developer using camps should not notice any practical difference with LVM or
without (other than the time to create a new camp).

Since all camp databases are snapshots of a common origin database on its own volume,
writes to this volume should really be avoided while there are any open
snapshots to reduce IO overhead.  But each camp is fine to do their own
reads/writes to their snapshot.

=head2 Refreshing Databases

Since all camps clone this origin database, you will need to update it
periodically in order for camps to get updated databases.  Updating the
origin database requires that all camp databases be stopped, their
snapshots removed, the origin database started, dumps imported into
the origin database, the origin database stopped again, and then all
camp databases snapshotted and and started back up.  This entire process
is best run by a script.  There is an exampl script for reference in
mics/refresh-database-origin.example.  You may want to set it up as a cronjob to
update all camps at some expected period (like every Saturday night, or
something).

=head2 Other Notes

If a developer does a lot of writes to their database
snapshot, there is a risk that the COW table will fill up.  This isn't
the end of the world, but will cause Postgres to think the file system
is 100% full and can't write to the file system any more.  To help avoid
this problem there are functions in the camp_lvm script to look at how
full a snapshot is and increase its size if needed.  You can run `sudo
/home/camp/bin/camp_lvm resize -n XX -u USER` for a specific camp, or
`sudo /home/camp/bin/camp_lvm resize_all` for every camp on the server. 
This is also something that should probably be run as a cronjob
periodically.  Currently it is hard-coded to increase snapshots if they
are more than 50% full.

=cut

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
    $fstab         =~ s/^.*?snap\-.*?camp\d\d.*$//mg;

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
    my $fstab_fmt   = '/dev/%s/%s       /home/%s/camp%s/pgsql        ext4    defaults        0 0' . "\n";

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
                print "Re-adding mount for $username camp$number\n";
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

    my $db_mount_point = $conf->{db_path} .'/data';
    #print "db_mount_point=$db_mount_point\n";  ## DEBUG
    system("/bin/mkdir -p $db_mount_point");
    print "/bin/mount /dev/$vol_group/$snapshot_name $db_mount_point", $/;  ## DEBUG
    system("/bin/mount /dev/$vol_group/$snapshot_name $db_mount_point");
    my $max_wait = 10;
    while ( ! -d "$db_mount_point/base" && $max_wait-- ) {
        sleep 2;
        print "Waiting for mount dir to exist: $db_mount_point/base\n";
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

    my $db_mount_point = $conf->{db_path} .'/data';
    #print "db_mount_point=$db_mount_point\n";  ## DEBUG

    # unmount the camp volume
    system("/bin/umount $db_mount_point");
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
