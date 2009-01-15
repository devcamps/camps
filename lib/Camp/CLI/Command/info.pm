package Camp::CLI::Command::info;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'display information about a camp';
}

sub usage_desc {
    return '%c info %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "displaying information for a camp\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::info - 

=head1 SYNOPSIS

App::Cmd Command that displays information about a camp.

=cut
