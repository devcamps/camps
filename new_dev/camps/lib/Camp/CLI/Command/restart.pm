package Camp::CLI::Command::restart;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'restart a camp';
}

sub usage_desc {
    return '%c restart %o';
}

sub command_names {
    return qw( restart re );
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "restarting a camp\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::restart - 

=head1 SYNOPSIS

App::Cmd Command that restarts the services managed by a camp.

=cut
