
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
