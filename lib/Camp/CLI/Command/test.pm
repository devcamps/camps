package Camp::CLI::Command::test;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'test something about a camp';
}

sub usage_desc {
    return '%c test %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "testing a camp\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::test - 

=head1 SYNOPSIS

App::Cmd Command that tests something about a camp.

=cut
