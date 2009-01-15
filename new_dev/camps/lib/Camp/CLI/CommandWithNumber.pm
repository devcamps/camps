package Camp::CLI::CommandWithNumber;

our $VERSION = '0.01';

use Moose;
extends qw(Camp::CLI::Command);

has number => (
    documentation => 'Camp to work on',
    metaclass     => 'Getopt',
    cmd_aliases   => ['n'],
    # TODO: if "Maybe[Int]" gets added to the MooseX::Getopt option map 
    #       then the following can be uncommented and used
    #isa           => 'Maybe[Int]',
    isa           => 'Int',
    is            => 'rw',
    required      => 0,
    default       => sub {
        my $self = shift;

        my $cwd = Cwd::getcwd();
        if ($cwd =~ m{/camp(\d+)(?:/|$)}) {
            return $1;
        }
        else {
            # TODO: if the "Maybe[Int]" fix above is applied then this can be removed
            return -1;
        }
        return;
    },
);

# a command that works on a number necessarily expects a path to a camp to exist
# but something like make camp builds the path, so this can't actually verify
# the path's existence
has path => (
    documentation => 'Location of Camp Directories',
    metaclass     => 'Getopt',
    isa           => 'Str',
    is            => 'rw',
    required      => 0,
    default       => sub {
        my $self = shift;
        return $self->user_config->{path};
    },
);

augment run => sub {
    my ($self, $opts, $args) = @_;

    # TODO: if the "Maybe[Int]" fix above is applied then the check against -1 can be removed
    die $self->usage_error("Unable to determine camp number\n") if (not defined $self->number or $self->number == -1);

    print "Camp number: '" . $self->number . "'\n" if $self->verbose;

    print "Determining final camp path " if $self->verbose;
    $self->path( File::Spec->catfile($self->path, 'camp' . $self->number) );
    print $self->path . "...Done.\n" if $self->verbose;

    inner();

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::CommandWithNumber - 

=head1 SYNOPSIS

Inheritable Base class to be inherited by Camp::CLI commands that insist on knowing a camp number to function.
Builds on Camp::CLI::Command.

=cut
