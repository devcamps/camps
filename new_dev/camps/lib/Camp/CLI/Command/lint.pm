package Camp::CLI::Command::lint;

our $VERSION = '0.01';

use Moose;
extends 'Camp::CLI::CommandWithNumber';

sub abstract {
    'lint...';
}

sub usage_desc {
    return '%c lint %o';
}

augment run => sub {
    my ($self, $opt, $args) = @_;

    print "linting a camp\n";

    return;
};

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command::lint - 

=head1 SYNOPSIS

App::Cmd Command that does something with lint...

=cut
