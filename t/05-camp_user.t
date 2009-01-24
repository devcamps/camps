#!perl -T

use strict;
use warnings;

use English '-no-match-vars';
use User::pwent;
use Test::More tests => 11;
use Test::Exception;

my ($class, $user, $name, $pwent);
BEGIN {
    $class = 'Camp::User';
    use_ok($class);
}

$name = 'spamalot';
while (getpwnam($name)) { $name .= 'x' }

{
    my $warning;
    local $SIG{__WARN__} = sub {
        $warning = shift;
    };

    $user = $class->new(
        username        => $name,
        email_address   => 'sir@spamalot.com',
    );

    cmp_ok(
        $warning,
        '=~',
        qr{username '$name' does not exist},
        'warning issued if username() does not match a real user account',
    );
}

is(
    $user->username,
    'spamalot',
    'username() get',
);

ok(
    !defined($user->display_name),
    'display_name() undefined when username() does not match real account',
);

$pwent = getpw($EUID);
$user->username($pwent->name);
is(
    $user->username,
    $pwent->name,
    'username() set/get',
);

is(
    $user->email_address,
    'sir@spamalot.com',
    'email_address() get',
);

$user->email_address('aard@vark.net');
is(
    $user->email_address,
    'aard@vark.net',
    'email_address() set/get',
);

is(
    $user->display_name,
    $pwent->comment,
    'display_name() get',
);

dies_ok(
    sub { $user->display_name('Madam Aard V. Ark') },
    'display_name() is read-only',
);

ok(
    !$user->camp_administrator,
    'camp_administrator() defaults to false',
);

$user->camp_administrator(1);
ok(
    $user->camp_administrator,
    'camp_administrator() true post-set',
);

