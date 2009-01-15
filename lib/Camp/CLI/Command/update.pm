package Camp::CLI::Command::update;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'update a camp';
}

sub usage_desc {
    return '%c update %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "updating a camp\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::update - 

=head1 SYNOPSIS

App::Cmd Command that updates the database, files, source, config, etc. of the camp.

=cut
