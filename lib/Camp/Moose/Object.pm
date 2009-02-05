package Camp::Moose::Object;

use base qw(Moose::Object);
use Moose;
use MooseX::Storage;
use Camp::Moose::Attribute;

with Storage(format => 'YAML');

sub serialize {
    my ($self) = @_;
    $self->freeze;
}

1;

__END__

=head1 NAME

Camp::Moose::Object

=head1 SYNOPSIS

    use Camp::Resource; # derives from Camp::Moose::Object

    # this does not serialize
    has 'path' => (is => 'rw', isa => 'Str', metaclass => 'DoNotSerialize');

    # does serialize
    has 'port' => (is => 'rw', isa => Int);
    

=head1 DESCRIPTION

this is a description

=head1 SERIALIZATION

Camp::Moose::Object is the base class for the camp object hierarchy. All
resources handled by camps are of this type. At this time the class provides a
serialization functionality provided by L<MooseX::Storage>. Of note is that
Camp::Moose::Object uses the C<DoNotSerialize> meta-attribute to specify which
attributes serialize. All attributes serialize by default unless the
L<MooseX::Storage::Meta::Attribute::DoNotSerialize> attribute is specified.


Camp::Moose::Object serialization methods serialize using YAML.
Camp::Moose::Object will use any available YAML module for serialization, with
the following preference:

For further information about how Camp::Moose::Object serializes and
deserializes, see L<MooseX::Storage>.

=over 4

=item YAML::Syck 

=item YAML

=back

If Camp::Moose::Object cannot find one of these modules, a compile-time error
will occur. For this reason, camps will try to load both of these modules. If
this fails, the installer will install one, preferring YAML::Syck if a C
compiler is available.

=head2 PUBLIC INTERFACE 

Camp::Moose::Object provides the following methods to handle serialization:

=over 4

=item freeze

freeze will serialize the object, returning a string of YAML containing this
object and all of the relevant attributes.

=item thaw

thaw will take a YAML string and will instantiate the relevant objects and all
objects contained within this object.
