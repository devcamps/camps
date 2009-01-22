package Camp::Resource;

use strict;
use warnings;

use Camp::Moose;

no Camp::Moose;

1;

=pod

=head1 NAME

B<Camp::Resource>: base class for objects representing "resources".

=head1 DESCRIPTION

=head1 SUBCLASS ORGANIZATION

B<Camp::Resource> by itself provides a general interface for resources within the camp system, and some basic behaviors.  Not surprisingly,
subclasses will be responsible for implementing resource-type-specific logic.  Furthermore, the camp system assumes a particular organization
of subclasses to maximize extensibility within deployments.

The types of resources available within the camp system are typically expected to live in your global Perl library path (appropriate to wherever
you installed camps).  However, your deployment can have deployment-specific subclasses of these.  Finally, a given camp type provides another
layer of extensibility via subclassing.  The organization looks something like this:

=over

=item global modules defining types:

I<perl_lib_path>

B<Camp::Resource::*> namespace

=item deployment-specific extensions:

I<camps_base_path>/resources/

B<Camp::Deployment::Resource::*> namespace

=item camp type specific extensions:

I<camps_base_path>/types/I<type_name>/resources/

B<Camp::Deployment::Type::Resource::*> namespace

=back

While the resource types living in the global space are loaded through standard "use" (or "use base", etc.) calls, the modules in the other two locations are loaded
through nonconventional means, treated more like "plugins" than standard modules.

While the deployment and camp-type resource subclasses can naturally introduce new logic, extend the interface/behaviors, etc., their primary purpose is configuration.
A given resource in the global space defines the fundamentals for a type of resource; for instance, B<Camp::Resource::Apache> would front the Apache webserver.  However,
for any given deployment, some minimal degree of configuration can be expected, and the deployment and camp-type resource subclass definitions are the places for this.  The
deployment space configures and extends a particular resource for the entire deployment, while the camp-type space defines, configures, and extends resources for the camp type.

Ultimately, the camp type determines what resources can make up a camp, and how those resources are arranged.  The subclasses defined in the camp-type space will be arranged
according to resource organization needs within the system represented by the camp type, while those defined in the deployment space are likely to be organized similarly
to those in the global space: as basic resource types, without implying relationships between resources.  But it's ultimately up to you.

=head1 ATTRIBUTES

=over

=item B<relative_path>

A path representing where, relative to the B<container_path> (see the corresponding method), the resource lives on the filesystem.

=item B<container>

An object that derives from B<Camp::Resource> (or implements its interface) that is the containing resource of the invocant.

For example, a B<Camp::Resource> object representing "localhost" might be the B<container> for a resource object representing "postgres."

Every resource except the top-most resource (which represents a specific camp) should have a value in B<container>.  This lets us walk up
the container hierarchy.

=item B<resources>

A list of B<Camp::Resource>-based objects representing resources that are contained by the invocant.

For example, a B<Camp::Resource> object representing "localhost" would contain resource objects for all resources in the camp that run locally,
which for a webapp might look something like:

=over

=item *

A B<Camp::Resource> object representing "Git"

=item *

Another representing "Rails"

=item *

Another representing "Postgres"

=item *

Another representing "Apache"

=back

The resource objects listed do not include the total possible set of resources, but rather the set of resources actually involved with the camp
in question (which may be a subset of the total possible resources, depending on the complexity of the deployment).

=back

=head2 RESOURCE CONTROL/INTERACTION INTERFACE ATTRIBUTES

=over

=item B<service_interface>

An instance of a B<Camp::Interface> subclass (or an object that implements the B<Camp::Interface> interface) that passes commands through
to the service represented by the B<Camp::Resource> instance.  See the B<Camp::Interface> documentation for details.

This is ultimately about interacting with a running resource.

=item B<control_interface>

An instance of a B<Camp::Interface> subclass (or an object that implements the B<Camp::Interface> interface) that passes adminstrative commands
through for configuration and/or control of the B<Camp::Resource> instance.

If not overridden in the B<Camp::Resource> subclass, or configured on an instance specifically, the B<control_interface> defaults to using the B<service_interface>
of the B<container> resource.  To understand this, consider some examples:

=over

=item *

A "Postgres" resource representing a Postgres database cluster would, in simple cases, be contained by a "localhost" resource representing the local host on which
the camp system runs.  The "localhost" service interface would simply be an interface for executing shell commands.  Postgres clusters are created and controlled
with such commands; consequently, having Postgres' control interface default to localhost's service interface works nicely.

=item *

A "database" resource representing the actual Postgres database could be contained within the "Postgres" resource (this sort of abstraction isn't strictly necessary
but is certainly possible); configuration and control of this "database" resource would need to be done with SQL commands issued to the running Postgres cluster,
which is the sort of commands we would expect the "Postgres" resource's service interface to handle.  So again, having the contained resource's control interface default
to the container's service interface works well.  In this case, it's probably sensible for the "Postgres" resource's service interface to front a psql session (psql is
the Postgres client) that is connected as the "postgres" user (the default Postgres superuser).  While the "database" resource's service interface would front a similar
psql session, but perhaps connected as a less-privileged database role.

=back

Hopefully this serves to illustrate the purpose of these command/control interface attributes.  They could be used to represent all sorts of stateful control sessions:
a psql or mysql database client session; a telnet session for control of services like memcached or Varnish; an SSH session for working with a remote host; etc.

=back

=head1 METHODS

=over

=item B<container_path()>

Passes through the path of the camp within the nearest container that implements paths.

=item B<path()>

Returns the full path (relative to the nearest container for which paths are relevant) of the resource within the camp, effectively
amounting to the combination of B<container_path()> with B<relative_path>.

Generally speaking, all files for the resource within the camp should be placed under this path.

=back

=head1 RESOURCE SERIALIZATION

The camp system uses YAML to serialize resource configuration state; all attributes that are marked as "persistent" will be included
in the YAML representation of the resource state.

See B<Camp::Object::Meta> for an explanation of how to configure your subclass attributes for inclusion in the serialized representation of B<Camp::Resource> objects.
Attributes are only included in the serialized representation if they are marked as persistent.

=head1 SEE ALSO

=over

=item B<Camp::Interface>

=item B<Camp::Object>

=item B<Camp::Object::Meta>

=item B<Camp::Deployment>

=back

=head1 ACKNOWLEDGEMENTS

=cut

