#!perl -T

use strict;
use warnings;
use Test::More qw( no_plan );
use Test::Exception;

my $class;

BEGIN {
    $class = 'Camp::Interface';
    use_ok($class);
}

my $interface = $class->new();
my @args = (1,2,3);

is_deeply (
	[$interface->format_command(@args)],
	\@args,
	'default behavior of format_command() method'
);

cmp_ok(
	$interface->validate_result(5),
	'==',
	5,
	'default behavior of validate_result() method'
);

throws_ok(
    sub { $interface->do_command() }, 
	'Camp::Interface::Exception',
	'command execution Exception'
);


package InterfaceSubclass;
use base qw(Camp::Interface);

sub format_command {
	my $self = shift; 
	my (@args) = shift;

	$args[0] =  ord $args[0];
	return @args;
}

sub validate_result {
	my $self = shift;
	my $raw_result = shift;

	return chr $raw_result;
}

sub execute_command {
	my $self = shift;
	my (@args) = shift;

	$args[0] -= 32;
	return $args[0];
}

package main;

my $subclass = InterfaceSubclass->new();

SKIP: { 
    skip 'Test for InterfaceSubclass test class', 3;

    is_deeply([$subclass->format_command('a')],[97],'subclass format_command');
    cmp_ok($subclass->execute_command(97),'==',65,'subclass execute_command');
    cmp_ok($subclass->validate_result(65),'eq','A','subclass validate_result');
};

cmp_ok(
	$subclass->do_command('a'),
	'eq',
	'A',
	'do_command'
);


