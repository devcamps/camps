package Camp::CLI::Command::start;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'start a camp';
}

sub usage_desc {
    return '%c start %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "starting a camp\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::start - 

=head1 SYNOPSIS

App::Cmd Command that starts the services managed by a camp.

=cut
