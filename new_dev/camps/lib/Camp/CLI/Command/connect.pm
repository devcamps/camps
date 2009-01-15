package Camp::CLI::Command::connect;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'connect to a service';
}

sub command_names {
    return qw( connect db );
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    # TODO: test subcommand to see if it is 'db' in which case we can guess what to do
    print "connecting to service\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::connect - 

=head1 SYNOPSIS

App::Cmd Command that connects to a camps' service at its command line, i.e. Postgres or MySQL.

=cut
