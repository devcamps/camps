package Camp::Type;

1;

=pod

=head1 HEAD

B<Camp::Type>: an object class for representing "camp types" within a camp deployment.

=head1 DESCRIPTION

A "camp type" is the campified representation of a particular software system.  It consists of an arbitrary number of resources,
(see B<Camp::Resource>), with configuration information and relationships between those resources, with each resource representing
a different component within the targeted software system.

When a camps user makes a new camp, the user specifies a camp type, which determines which resources/configuration are used in
creating the camp.

The "camp type" construct increases the flexibility of camps considerably, by allowing for various scenarios:

=over

=item *

Different, unrelated applications managed within the same camp deployment (a good approach for a shared development server)

=item *

Representing different deployment configurations/scenarios for the same application

=item *

...and so on.

=back

=head1 ATTRIBUTES

=over

=item B<camps> (read-only)

Returns a list of all the B<Camp::Resource::Camp> objects of this particular type.

=item B<deployment> (required)

The B<Camp::Deployment> to which the B<Camp::Type> instance belongs.

=item B<name> (required; unique)

A unique name identifying the type within the deployment.

=item B<path>

The type's path on the file system; defaults to the B<name> value under the B<types_path> of the B<deployment> instance; there
should be no reason to set this, though it is writable.

=item B<config_path>

The path of the YAML configuration file for this camp type, defaulting to "camp_type.yaml" within the B<path>.

=item B<resource_path>

The path under which all resource libraries for the camp type reside, defaulting to the "resources" directory underneath B<path>.

=back

=head1 METHODS

=over

=item B<initialize()>

Creates the (presumably new) B<Camp::Type> object within the relevant B<deployment>.  This means:

=over

=item *

Storing information about the camp type within the deployment metadata store (see B<Camp::Deployment::Meta>)

=item *

Preparing the skeleton filesystem layout for the camp type according to the various path-related attributes.

=back

If the B<Camp::Type> in question already exists in the deployment (either in the metadata store or the file system),
B<initialize()> will throw an exception.

=back

=head1 AUTHORS

Ethan Rowe (End Point Corporation)

soon to be others.

=cut

