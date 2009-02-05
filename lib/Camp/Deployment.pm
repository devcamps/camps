package Camp::Deployment;

use File::Spec;
use File::Path ();
use Camp::Moose;

has path => (
    required    => 1,
    is          => 'rw',
    isa         => 'Str',
);

has config_path => (
    is          => 'rw',
    isa         => 'Str',
    lazy        => 1,
    default     => sub {
        File::Spec->catfile( shift->path, 'camps_deployment.yaml' );
    },
    metaclass   => 'DoNotSerialize',
);

has types_path => (
    is          => 'rw',
    isa         => 'Str',
    lazy        => 1,
    default     => sub {
        File::Spec->catfile( shift->path, 'types' );
    },
);

has resource_path => (
    is          => 'rw',
    isa         => 'Str',
    lazy        => 1,
    default     => sub {
        File::Spec->catfile( shift->path, 'resources' );
    },
);

no Camp::Moose;

sub initialize {
    my $self = shift;
    $self->_initialize_paths;
    return $self;
}

sub _initialize_paths {
    my $self = shift;

    my @paths = (
        $self->path,
        $self->resource_path,
        $self->types_path,
    );

    for my $path (@paths) {
        die "$path already exists; cannot initialize.\n"
            if -d $path;
    }

    for my $path (@paths) {
        eval { File::Path::mkpath( $path ) };
        die "Error creating ${path}: $@\n"
            if $@;
    }

    return $self;
}

1;

=pod

=head1 NAME

B<Camp::Deployment>: object module representing top-level camp applications or "deployments"

=head1 DESCRIPTION

A camps "deployment" is an actual application, with the configuration, metadata, etc. all present
to define camp types, camp users, camps, etc.  The B<Camp::Deployment> object model allows for basic
navigation and management of such deployments, with functionality for:

=over

=item *

Deployment initialization (creation of new camp system applications)

=item *

Camp type creation and management (adding, editing camp types within a given deployment)

=item *

Individual camp creation

=item *

Camp user management

=item *

But wait!  There's more (maybe, later)!

=back

A B<Camp::Deployment> instance is created with a given path, which is treated as the base path of the
entire camps deployment.  Within that path, certain resources are expected:

=over

=item *

I<types/> directory for camp type definitions

=item *

I<resources/> directory for resource configuration/extensions

=item *

I<camps_deployment.yaml> file for basic configuration information

=back

If your camps deployment lives in I</var/lib/camps>, you can expect the following directory structure, based
on the B<Camp::Deployment> defaults:

 /var/lib/camps/
    camps_deployment.yaml
    resources/
    types/

If you wanted to create a new camps deployment at I<camps> under your home directory, you could do something
like:

 # prepare the deployment object and point it at "camps" under your home
 my $deployment = Camp::Deployment->new(
     path => File::Spec->catfile( $ENV{HOME}, 'camps' ),
 );
 # create the deployment within the filesystem
 $deployment->initialize;

Later, if you wanted to work with that deployment to add a camp type:

 # Load up the deployment object
 my $deployment = Camp->Deployment->new(
     path => File::Spec->catfile( $ENV{HOME}, 'camps' ),
 );
 # Load it up; it'll throw an exception if it fails.
 $deployment->load;
 # add your new camp type
 my $type = $deployment->add_type(
     Camp::Type->new( name => 'my_new_type' )
 );
 ...

Or get a list of all the camp types known to your deployment:

 for my $type ($deployment->get_types) {
     printf "%s: %d camps\n", $type->name, scalar($type->camps);
 }

It should not really be necessary to use B<Camp::Deployment> directly if you're a user of camps; this module
is intended for use within the camps codebase itself.

=back

=head1 ATTRIBUTES

=over

=item B<path> (required)

This required attribute specifies where in the filesystem the camps deployment in question resides.  Without
it, B<Camp::Deployment> isn't related to anything real.

The directory referenced will by default contain all the pieces of the camp deployment, though this can be
overridden as needed if for some reason resources or types should live outside of the main deployment path.

=item B<config_path>

Specifies the full path of the configuration file for the deployment.  This defaults to B<camps_deployment.yaml>
undder the B<path> value.

=item B<types_path>

Specifies where on the filesystem the camp type definitions reside for the given deployment.  While this can
be specified, recommended use is to accept the default, which is "types" under the B<path> value.

=item B<resources_path>

Specifies where on the filesystem the deployment-wide resource extensions/configuration libraries reside.
Like B<types_path>, this can be specified manually, but the default value of "resources" under the B<path> value
is recommended.

=item B<db> (read-only)

Returns the B<Camp::Deployment::Meta> instance that manages the camps deployment database.

=back

=head1 METHODS

=over

=item B<initialize()>

Prepares a new deployment for use, based on the state of the object.  This involves setting up
the relevant paths, the configuration YAML file (see B<save()>, setting up the deployment database,
etc.

=item B<get_types( @names )>

Returns a list of the B<Camp::Type> instances known to the deployment.  If the optional I<@names>
list is provided, then the instances will be filtered to include only those with matching names; without
I<@names>, all known B<Camp::Type> instances are returned.

=item B<save()>

Writes the deployment configuration data (basically, the attribute values of the object) to
the B<config_path>.

Configuration data is written out as YAML.

=back

=cut

