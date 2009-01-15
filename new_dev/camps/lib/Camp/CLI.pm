package Camp::CLI;

use Moose;

extends 'MooseX::App::Cmd';

__PACKAGE__->meta->make_immutable;

no Moose;

our $VERSION = '0.01';

1;

__END__

=head1 NAME

Camp::CLI -

=head1 SYNOPSIS

Sets up standard App::Cmd related items.

=cut
