package Camp::CLI::Command;

our $VERSION = '0.01';

use Carp qw( croak );
use Cwd qw();
use File::HomeDir qw();
use File::Spec qw();

use Moose;
extends qw(MooseX::App::Cmd::Command);

with 'MooseX::SimpleConfig';

has verbose => (
    documentation => 'Turns on output',
    metaclass     => 'Getopt',
    cmd_aliases   => ['v'],
    isa           => 'Bool',
    is            => 'rw',
    default       => 0,
);

has help => (
    documentation => 'Usage Screen',
    metaclass     => 'Getopt',
    cmd_aliases   => ['h'],
    isa           => 'Bool',
    is            => 'rw',
    default       => 0,
);

has config => (
    documentation => 'Camps Config',
    is            => 'rw',
    isa           => 'HashRef',
    metaclass     => 'Getopt',
);

has '+configfile' => (
    documentation => 'System config file path',
    # TODO: using a sub here relies on a patch to MooseX::App::Cmd::Command that allows a code
    #       reference to be dereferenced and executed
    default       => sub {
        my $self = shift;

        my $dir = defined $ENV{CAMPS_CONFIG_DIR} ? $ENV{CAMPS_CONFIG_DIR} : '/etc/camps';
        my $file = File::Spec->catfile( $dir, 'base.xml' );

        return $file;
    },
);

has _user_config => (
    accessor      => 'user_config',
    documentation => 'Camp User Config',
    is            => 'rw',
    isa           => 'HashRef',
    default       => sub {
        my $self = shift;
        my $config = {};

        my $dir = defined $ENV{CAMP_CFG} ? $ENV{CAMP_CFG} : File::HomeDir->my_home;
        my $file = File::Spec->catfile( $dir, '.camprc' );

        print "Loading user config file: $file..." if $self->verbose;
        if (-e $file) {
            my $all_configs = Config::Any->load_files(
                {
                    files           => [ $file ],
                    use_ext         => 0,
                    flatten_to_hash => 1,
                    force_plugins   => [
                        'Config::Any::General',
                        'Config::Any::XML',
                        'Config::Any::YAML',
                    ],
                },
            );
            $config = $all_configs->{$file};

            print "Done.\n" if $self->verbose;
        }
        else {
            print "Not Found.\n" if $self->verbose;
        }
        if (not defined $config->{path}) {
            print "Setting default path: " if $self->verbose;
            $config->{path} = File::HomeDir->my_home;
            print "$config->{path}....Done.\n" if $self->verbose;
        }
        else {
            # this handles '~' expansion
            if ($config->{path} =~ /\A~/) {
                $config->{path} = glob $config->{path};
            }
        }

        return $config;
    },
);

sub validate_args {
    my $self = shift;

    my ($opt, $args) = @_;

    die $self->_usage_text if $opt->{help};

    $self->_validate_args($opt, $args);

    return;
}

sub _validate_args {
}

sub run {
    my ($self, $opts, $args) = @_;

    inner();

    exit;
}

__PACKAGE__->meta->make_immutable;

no Moose;

__PACKAGE__;

__END__

=head1 NAME

Camp::CLI::Command - 

=head1 SYNOPSIS

Base class to be inherited by Camp::CLI commands, allows generic processing of arguments and options
that are accessible to all commands.

=cut
