#!/usr/bin/perl -w

=doc

Tests for new property features.  These should probably go into 4.t and 5.t,
but the test suite is a mess of order-of-operations spaghetti tests and i
don't really want to mess with that.  Someday we'll have to overhaul this
suite, but it's late on Sunday night and i don't have the energy to fix what
ain't really broke.

This stuff makes Glib::Object::Subclass's GET_PROPERTY()/SET_PROPERTY()
replacements unnecessary.  Any ideas how to obsolete its new() replacement?

=cut

use Test::More tests => 42;
use Glib ':constants';
use Data::Dumper;
use strict;

# we'll test, for paranoia's sake, that things work the same both with and
# without Glib::Object::Subclass; to simplify things, let's use the exact
# same list of properties for both.  however, since the GObjects take
# ownership of the pspecs, we can't share them.  just use the same code
# to create them:
sub make_properties {
    # a basic one
    Glib::ParamSpec->string ('name', '', '', 'Joe', G_PARAM_READWRITE),
    # now with the new explicit handler syntax:
    {
        # with no handlers, this is the same as not using the hash
        pspec => Glib::ParamSpec->string ('middle', '', '', 'Momma',
                                          G_PARAM_READWRITE),
    },
    {
        pspec => Glib::ParamSpec->string ('nickname', '', '', 'Jimmy-John',
                                          G_PARAM_READWRITE),
        get => sub { ok(1, 'explicit getter for nickname');
                     $_[0]->{nickname} },
        set => sub { ok(1, 'explicit setter for nickname');
                     $_[0]->{nickname} = $_[1] },
    },
    {
        # if you leave out a getter, you get the default behavior
        pspec => Glib::ParamSpec->string ('surname', '', '', 'Jones',
                                          G_PARAM_READWRITE),
        set => sub { ok(1, 'explicit setter for surname');
                     $_[0]->{surname} = $_[1] },
    },
    {
        # same for leaving out a setter
        pspec => Glib::ParamSpec->string ('title', '', '', 'Mr',
                                          G_PARAM_READWRITE),
        get => sub { ok(1, 'explicit getter for title');
                     $_[0]->{title} },
    },
};


# create a new object type by hand (no Glib::Object::Subclass)

Glib::Type->register_object ('Glib::Object', 'Foo',
                             properties => [ &make_properties ]);


# now create one with Subclass, with the same properties.
package Bar;
use Glib::Object::Subclass 'Glib::Object',
    properties => [ &main::make_properties ];

package main;

sub prop_names {
	map { UNIVERSAL::isa ($_, 'Glib::ParamSpec')
	      ? $_->get_name
	      : $_->{pspec}->get_name
	} @_
}
sub Glib::Object::_list_property_names {
	prop_names $_[0]->list_properties
}
sub default_values {
	map { $_->get_default_value } $_[0]->list_properties
}


my @names = prop_names &make_properties;


# start tests

is_deeply ([prop_names (Foo->list_properties)], \@names,
	   'props created correctly for Foo');
my $foo = Foo->new;
isa_ok ($foo, 'Foo', 'it\'s a Foo');
is (scalar keys %$foo, 0, 'new Foo has no keys');

# initially all props should have all default values, except for the ones
# with explicit getters, as the explicit getters don't handle default values.
my @initial_values = default_values ('Foo');
$initial_values[2] = undef;
$initial_values[4] = undef;
my @values = $foo->get (@names);
is_deeply ([$foo->get (@names)], \@initial_values,
           'all defaults except for explicit ones');
is (scalar keys %$foo, 0, 'Foo still has no keys after get');

my @default_values = default_values ('Foo');
$foo->set (map { $names[$_], $default_values[$_] } 0..$#names);
is (scalar keys %$foo, 5, 'new Foo has keys after setting');
is_deeply ([ map {$foo->{$_}} @names ], [ @default_values ],
           'and they have values');

# now add a GET_PROPERTY and SET_PROPERTY that will be called when no
# explicit ones are supplied.
sub get_property {
	ok (1, 'fallback GET_PROPERTY called');
	return 'fallback';
}
sub set_property {
	ok (1, 'fallback SET_PROPERTY called');
	$_[0]->{$_[1]->get_name} = 'fallback';
}
{
no warnings;
*Foo::GET_PROPERTY = \&get_property;
*Foo::SET_PROPERTY = \&set_property;
}

# start over.
$foo = Foo->new;
isa_ok ($foo, 'Foo', 'it\'s a Foo');
is (scalar keys %$foo, 0, 'new Foo has no keys');

# with the overrides in place, none of the implicit keys will have values
# in get, because Subclass's GET doesn't handle defaults.
my @expected = map { defined $_ ? 'fallback' : undef } @initial_values;
@values = $foo->get (@names);
is_deeply ([$foo->get (@names)], \@expected,
           'fallback called for implicit getters');
is (scalar keys %$foo, 0, 'Foo still has no keys after get');

@expected = @default_values;
$expected[0] = 'fallback';
$expected[1] = 'fallback';
$expected[4] = 'fallback';
$foo->set (map { $names[$_], $default_values[$_] } 0..$#names);
is (scalar keys %$foo, 5, 'new Foo has keys after setting');
is_deeply ([ map {$foo->{$_}} @names ], [ @expected ],
           'and they have values');




#
# now verify that Subclass still works as expected.
#

my $bar = Bar->new;
is (scalar keys %$bar, 0, 'bar has no keys on creation');
@expected = @default_values;
$expected[2] = undef;
$expected[4] = undef;
is_deeply ([$bar->get (@names)], \@expected,
           'Subclass works just like registering by hand');
$bar->set (map { $names[$_], $default_values[$_] } 0..$#names);
is (scalar keys %$bar, 5, 'new Foo has keys after setting');
is_deeply ([ map {$bar->{$_}} @names ], [ @default_values ],
           'and they have values');
