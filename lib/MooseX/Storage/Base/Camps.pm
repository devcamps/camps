
package MooseX::Storage::Base::Camps;
use Moose::Role;

use MooseX::Storage::Engine::Camps;

our $VERSION   = '0.01';

sub pack {
    my ( $self, @args ) = @_;
    my $e = MooseX::Storage::Engine::Camps->new( object => $self );
    $e->collapse_object(@args);
}

sub unpack {
    my ( $class, $data, @args ) = @_;
    my $e = MooseX::Storage::Engine::Camps->new( class => $class );
    $class->new( $e->expand_object($data, @args) );
}

1;

__END__

=pod

=head1 NAME

MooseX::Storage::Base::Camps - Camps serialization

=head1 SYNOPSIS

  package Point;
  use Moose;
  use MooseX::Storage;

  our $VERSION = '0.01';

  with Storage(base => 'Camps');

  has 'x' => (is => 'rw', isa => 'Int', persist => 0);
  has 'y' => (is => 'rw', isa => 'Int', persist => 1);

  1;

  my $p = Point->new(x => 10, y => 10);

  ## methods to pack/unpack an 
  ## object in perl data structures

  # pack the class into a hash
  # x doesn't serialize
  $p->pack(); # { __CLASS__ => 'Point-0.01', y => 10 }

  # unpack the hash into a class
  # no x, so x won't be set
  my $p2 = Point->unpack({ __CLASS__ => 'Point-0.01', y => 10 });

=head1 DESCRIPTION

This class is a simple override of MooseX::Storage::Basic to work with
MooseX::Storage::Engine::Camps. It works together to serialize only persistent
attributes.

=head1 METHODS

=over 4

=item B<pack>

=item B<unpack ($data)>

=back

=head2 Introspection

=over 4

=item B<meta>

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no 
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Chris Prather E<lt>chris.prather@iinteractive.comE<gt>

Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

Chris Nehren E<lt>cnehren@endpoint.comE<gt> modified this simple class for use
with Camps.

=head1 COPYRIGHT AND LICENSE

Copyright 2007-2008 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

Copyright 2009 by End Point Corporation.

L<http://www.endpoint.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
