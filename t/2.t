#
# $Header: /cvsroot/gtk2-perl/gtk2-perl-xs/Glib/t/2.t,v 1.4 2003/09/11 14:35:03 rwmcfa1 Exp $
#

use strict;
use warnings;

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('Glib') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $obj = new Glib::Object "Glib::Object";
ok(2);

undef $obj;
ok(3);
