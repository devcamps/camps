package Camp::User;

use strict;
use warnings;

use User::pwent (); 
use Camp::Moose;

has username => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
    trigger     => sub {
        my $self = shift;
        $self->_user( User::pwent::getpwnam( $self->username ) );
        warn sprintf("username '%s' does not exist.\n", $self->username)
            unless $self->_user;
    },
);

has _user => (
    is          => 'rw',
    trigger     => sub {
        shift->_reset_display_name;
    },
    metaclass   => 'DoNotSerialize',
);

has email_address => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

has _display_name => (
    isa         => 'Str|Undef',
    reader      => 'display_name',
    clearer     => '_reset_display_name',
    lazy        => 1,
    default     => sub {
        my $self = shift;
        return undef unless my $user = $self->_user;
        return $user->comment;
    },
    metaclass   => 'DoNotSerialize',
);

has camp_administrator => (
    is          => 'rw',
    isa         => 'Bool',
    default     => 0,
);

no Camp::Moose;

1;

=pod

=head1 NAME

B<Camp::User>: class representing camp user accounts

=head1 DESCRIPTION

The B<Camp::User> object represents a user of the camp system, meaning
an account on the local system with permission to use the camps
deployment in question.

Each object should correspond to a real user account on the underlying
operating system.

=head1 ATTRIBUTES

=over

=item B<username> (required)

The username uniquely identifies the B<Camp::User> instance within the camps deployment.

It should match up to the username of the corresponding OS user account
to which the B<Camp::User> pertains.  If the username provided does not
match a real account, B<Camp::User> accepts it but will issue a warning.

=item B<email_address> (required)

Take a wild guess what this is.

=item B<display_name> (read-only)

The pretty name to show for the user; this is taken from the OS information
for the username in question.

=item B<camp_administrator>

Boolean attribute representing whether or not the user account is
granted the right to administer the camps deployment itself,
which includes adjusting configuration details, managing camp types, etc.

A true value gives the right, false denies.  False is default.

=back

=head1 AUTHORS

Ethan Rowe (End Point Corporation)

=cut
