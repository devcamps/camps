package MooseX::Storage::Engine::Camps;
use Moose;
use Scalar::Util qw(refaddr);

extends 'MooseX::Storage::Engine';
# util methods ...

sub map_attributes {
    my ($self, $method_name, @args) = @_;
    my @attributes = ($self->object || $self->class)->meta->compute_all_persistent_attributes;
    map { 
        $self->$method_name($_, @args) 
    } grep {
        # Skip our special skip attribute :)
        !$_->does('MooseX::Storage::Meta::Attribute::Trait::DoNotSerialize') 
    } ($self->object || $self->class)->meta->compute_all_persistent_attributes;
}

1;

=pod

=head1 NAME

MooseX::Storage::Engine::Camps -- Camps serialization Engine

=head1 DESCRIPTION

This class overrides map_attributes in L<MooseX::Storage::Engine> to use
compute_all_persistent_attributes in L<Camp::Moose::Meta> to determine which
attributes to serialize.

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
