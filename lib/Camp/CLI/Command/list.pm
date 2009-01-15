package Camp::CLI::Command::list;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::Command';

sub abstract {
    'list existing camps';
}

sub usage_desc {
    return '%c list %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "listing camps\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::list - 

=head1 SYNOPSIS

App::Cmd Command that lists existing camps.

=cut
