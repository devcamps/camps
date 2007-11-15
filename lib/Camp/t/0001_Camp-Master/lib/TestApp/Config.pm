package TestApp::Config;

use strict;
use warnings;
use base qw(Camp::Config);
use File::Spec;
use User::pwent;

my $path_root;
BEGIN {
    my $pkg = __PACKAGE__;
    $pkg =~ s!::!/!g;

    ($path_root) = (File::Spec->rel2abs(__FILE__) =~ m{(.+?)/lib/$pkg\.pm$});
}

sub adhoc_ic_path {
    return File::Spec->catfile($path_root, 'interchange');
}

sub adhoc_base_path {
    return File::Spec->catfile($path_root, 'catalogs');
}

sub _validate_adhoc_user {
    my $invocant = shift;
    return $invocant->_setting_set('user', getpwuid($>));   
}

1;
