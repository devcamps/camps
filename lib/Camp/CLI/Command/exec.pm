package Camp::CLI::Command::exec;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'execute a camp script';
}

sub usage_desc {
    return '%c exec %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "Executing a camp script\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::exec - 

=head1 SYNOPSIS

App::Cmd Command that wraps the running of an executable within the camp environment.

=cut
