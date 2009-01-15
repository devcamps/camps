package Camp::CLI::Command::destroy;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'tear down a camp';
}

sub usage_desc {
    return '%c destroy %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "Attempting to destroy camp: " . $self->number . "\n" if $self->verbose;
    print "TODO: stop services\n";

    unless (-d $self->path) {
        die "Camp directory does not exist: " . $self->path . "\n";
    }
    unless (-d File::Spec->catfile( $self->path, '.camp' )) {
        die "Path does not appear to be a camp: " . $self->path . "\n";
    }
    File::Path::rmtree( $self->path );
    print "TODO: remove camp config\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::destroy - 

=head1 SYNOPSIS

App::Cmd Command that tears down a camp instance.

=cut
