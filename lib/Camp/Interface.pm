package Camp::Interface;

use strict;
use warnings;
use Camp::Moose;

no Camp::Moose;
1;

=pod

=head1 NAME

B<Camp::Interface>: class for representing "interfaces" to which resource-oriented commands may be issued.

=head1 DESCRIPTION

All the "resources" in the camp system represent services, programs, etc. that can do stuff.  But to get them to do stuff,
we need a mechanism for telling them what stuff to do.  B<Camp::Interface> represents the "transport layer" for that mechanism;
the caller can provide commands to the B<Camp::Interface> object, and B<Camp::Interface> knows how to carry out those commands
appropriately for the type of resource.

For a given type of resource (a resource representing a shell environment, or a telnet session, or a database
session, etc.), it may be necessary implement custom B<Camp::Interface> subclasses for providing that transport layer.  Some
examples of how B<Camp::Interface> might be used for various kinds of resources:

=over

=item *

For a "localhost" resource, a B<Camp::Interface> subclass would simply pass commands through to the underlying shell environment.

=item *

For a remote host resource, a B<Camp::Interface> subclass might front an SSH session, through which all commands would be piped.

=item *

For a Postgres (database) resource, the relevant B<Camp::Interface> subclass might maintain a pipeline to a I<psql> session.

=back

While the interfaces are represented by objects, that does not mean that the interfaces need to be stateful; the "localhost" example
above, for instance, would really not need to track state between commands.  However, for interfaces that involve a session with some
other daemon, like SSH, a database client, etc., the session can be maintained as state within the subclass instance as appropriate
for the daemon in question.

=head1 ATTRIBUTES

=over

=item B<last_error>

The B<Camp::Interface::Exception> instance for the most recent error.  Read-only.

=item B<last_result>

The result value of the most recent command.  Read-only.

=item B<resource>

The B<Camp::Resource> to which the object pertains.  This attribute is required when B<Camp::Interface> is
instantiated, as B<Camp::Interface> may need to go to that resource for details about how to communicate
with the underlying resource in question.

No type-checking occurs on the B<resource> attribute by default.  However, if your B<Camp::Interface> subclass
implementation depends on certain configuration attributes/methods being present in the related B<Camp::Resource>
instance, then your subclass should possibly define a specialized type constraint.  However, use duck typing whenever
possible; rather than designing a type constraint that looks for a specific class, use a type constraint that checks
to see if the desired interface is implemented.  Or, don't bother, and it'll either work or it won't.  You won't know
until runtime in either case.

=back

=head1 METHODS

=over

=item B<do_command( @command_args )>

Formats the command arguments as needed for the service with which B<Camp::Interface> expects to interact, and
passes the resulting command through to that service.

This method is the primary point of use for B<Camp::Interface>; resource objects making use of a B<Camp::Interface>
subclass instance would issue commands to their underlying service via B<do_command()>.

The semantics of I<@command_args> are up to the implementer, and should be idiomatic to the type of resource
with which the B<Camp::Interface> subclass interacts.  For many kinds of resources, I<@command_args> would probably
simply contain a single command string; this would be potentially suitable for shell commands, database "scripts",
etc.

The response value should reflect the response code from the underlying service/resource, as appropriate to
that service/response.

The B<do_command()> method is a higher-level method that is largely composed of calls to underlying
methods discussed below.  If your subclass properly implements the lower-level methods, then B<do_command()>
should Just Work.

If the command execution dies, a B<Camp::Interface::Exception> error is thrown, and the same error is
set in the B<last_error> attribute.  Otherwise, the result value is stored in the B<last_result> attribute.

=item B<execute_command( @formatted_command )>

Must be implemented per-subclass to actually handle the real
mechanics of executing a command.  The I<@formatted_command> list is expected to take whatever form the service
needs for actual execution, having been prepared by B<format_command()>.

The response value should be the raw response value provided by the service/resource upon executing the command in
question.

=item B<format_command( @command_args )>

To be implemented per-subclass.

Given I<@command_args> as appropriate for B<do_command()>, parses those arguments
and returns a transformed set (as appropriate for the service/resource fronted by this interface) appropriate
for use by B<execute_command()>.

The default behavior (i.e. if you don't override it in your subclass) as defined in B<Camp::Interface> is to
simply pass through I<@command_args> unchanged.

=item B<validate_result( $raw_result )>

To be implemented per-subclass.

Given a raw result value in I<$raw_result> from B<execute_command()>, should verify that the result does not
represent a hard error, and should convert the raw value to an appropriate
value that is usable within camps.  For instance, for shell commands, the raw result value should be shifted 8 bits
in order to arrive at the actual meaningful value.

The result value should be the converted value, if conversion was necessary; otherwise, passing the original value
through is appropriate.

If the result represents a hard error, then B<validate_result()> should die with an appropriate error message.  It
is not necessary to throw an exception object; as B<validate_result()> is typically used within the B<do_command()>
method, the error thrown will be caught and rethrown appropriately as a B<Camp::Interface::Exception> error.

The default behavior defined in B<Camp::Interface> is to simply pass the I<$raw_result> through unchanged with
no error-checking.

=back

=cut

