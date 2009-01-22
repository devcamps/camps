package Camp::Moose::Attribute;

use base qw(Moose::Meta::Attribute);

__PACKAGE__->meta->add_attribute( persist => ( reader => persists ) );

1;
