package Camp::CLI::Command::make;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

has skip_record => (
    documentation => 'Do not record camp in database',
    metaclass     => 'Getopt',
    isa           => 'Bool',
    is            => 'rw',
    default       => 0,
);

has skip_service => (
    documentation => 'Skip building a service',
    metaclass     => 'Getopt',
    isa           => 'Bool',
    is            => 'rw',
    default       => 0,
);

has '+number' => (
    default => sub {
        # TODO: need to pull the next camp id in the sequence
        return 999;
    },
);

sub abstract {
    'create a new camp';
}

sub usage_desc {
    return '%c make %o type comment';
}

sub _validate_args {
    my ($self, $opt, $args) = @_;

    $self->SUPER::_validate_args($opt, $args);

    die $self->usage_error("Must supply type and comment\n") unless @$args >= 2;
}

augment run => sub {
    my ( $self, $opts, $args ) = @_;

    die "Unrecognized type: " . $args->[0] . "\n" unless (defined $self->config->{project}->{ $args->[0] });
    my $project = $self->config->{project}->{ $args->[0] };

    print "Making camp\n" if $self->verbose;
    print "....type: $args->[0]\n" if $self->verbose;
    print "....path: " . $self->path . "\n" if $self->verbose;

    my $init_dir = File::Spec->catfile( $self->path, '.camp' );
    if (-e $init_dir) {
        die "Camp init directory already exists: $init_dir\n";
    }
    File::Path::mkpath($init_dir);

    my $init_file = File::Spec->catfile( $init_dir, 'init' );
    open my $INIT_HANDLE, ">$init_file" or die "Can't open init file for writing: $!\n";
    print $INIT_HANDLE "creation = " . time . "\n";
    print $INIT_HANDLE "type = $args->[0]\n";
    close $INIT_HANDLE;

    print "Setting up services....\n";
    for my $service (@{ $project->{service} }) {
        print "\t...$service\n";
    }

    return;
};

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::make - 

=head1 SYNOPSIS

App::Cmd Command that creates a new camp instance.

=cut
