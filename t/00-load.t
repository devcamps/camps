#!perl -T

use Test::More tests => 14;

BEGIN {
	use_ok( 'Camp' );
	use_ok( 'Camp::CLI' );
	use_ok( 'Camp::CLI::Command' );
	use_ok( 'Camp::CLI::Command::connect' );
	use_ok( 'Camp::CLI::Command::destroy' );
	use_ok( 'Camp::CLI::Command::exec' );
	use_ok( 'Camp::CLI::Command::info' );
	use_ok( 'Camp::CLI::Command::lint' );
	use_ok( 'Camp::CLI::Command::list' );
	use_ok( 'Camp::CLI::Command::make' );
	use_ok( 'Camp::CLI::Command::restart' );
	use_ok( 'Camp::CLI::Command::start' );
	use_ok( 'Camp::CLI::Command::test' );
	use_ok( 'Camp::CLI::Command::update' );
}

diag( "Testing Camp $Camp::VERSION, Perl $], $^X" );
