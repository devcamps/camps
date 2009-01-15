#!perl -T

use Test::More tests => 27;

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
	use_ok( 'Camp::Service' );
	use_ok( 'Camp::Service::AppServer' );
	use_ok( 'Camp::Service::AppServer::Interchange' );
	use_ok( 'Camp::Service::AppServer::Rails' );
	use_ok( 'Camp::Service::DB' );
	use_ok( 'Camp::Service::DB::MySQL' );
	use_ok( 'Camp::Service::DB::Postgres' );
	use_ok( 'Camp::Service::HTTP' );
	use_ok( 'Camp::Service::HTTP::Apache' );
	use_ok( 'Camp::Service::VCS' );
	use_ok( 'Camp::Service::VCS::CVS' );
	use_ok( 'Camp::Service::VCS::Git' );
	use_ok( 'Camp::Service::VCS::Subversion' );
}

diag( "Testing Camp $Camp::VERSION, Perl $], $^X" );
