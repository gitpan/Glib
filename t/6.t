#
# $Header: /cvsroot/gtk2-perl/gtk2-perl-xs/Glib/t/6.t,v 1.1 2003/08/14 21:22:30 rwmcfa1 Exp $
#


#########################

use Test::More tests => 7;
BEGIN { use_ok('Glib::PkgConfig') };

#########################


my %pkg;

# test 1 for success
eval { %pkg = Glib::PkgConfig->find(qw/glib-2.0/); };
ok( not $@ );
ok( $pkg{modversion} and $pkg{cflags} and $pkg{libs} );

# test 1 for failure
eval { %pkg = Glib::PkgConfig->find(qw/bad1/); };
ok( $@ );

# test 2 for success
eval { %pkg = Glib::PkgConfig->find(qw/bad1 glib-2.0/); };
ok( not $@ );
ok( $pkg{modversion} and $pkg{cflags} and $pkg{libs} );

# test 2 for failure
eval { %pkg = Glib::PkgConfig->find(qw/bad1 bad2/); };
ok( $@ );

