/*
 * Copyright (c) 2003 by the gtk2-perl team (see the file AUTHORS)
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the 
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330, 
 * Boston, MA  02111-1307  USA.
 *
 * $Header: /cvsroot/gtk2-perl/gtk2-perl-xs/Glib/Glib.xs,v 1.7 2003/08/29 02:15:42 muppetman Exp $
 */

=head2 Miscellaneous

Various useful utilities defined in Glib.xs.

=over

=cut


#include "gperl.h"

#include "ppport.h"


=item GPERL_CALL_BOOT(name)

call the boot code of a module by symbol rather than by name.

in a perl extension which uses several xs files but only one pm, you
need to bootstrap the other xs files in order to get their functions
exported to perl.  if the file has MODULE = Foo::Bar, the boot symbol
would be boot_Foo__Bar.

=item void _gperl_call_XS (pTHX_ void (*subaddr) (pTHX_ CV *), CV * cv, SV ** mark);

never use this function directly.  see C<GPERL_CALL_BOOT>.

for the curious, this calls a perl sub by function pointer rather than
by name; call_sv requires that the xsub already be registered, but we
need this to call a function which will register xsubs.  this is an
evil hack and should not be used outside of the GPERL_CALL_BOOT macro.
it's implemented as a function to avoid code size bloat, and exported
so that extension modules can pull the same trick.

=cut
void
_gperl_call_XS (pTHX_ void (*subaddr) (pTHX_ CV *), CV * cv, SV ** mark)
{
	dSP;
	PUSHMARK (mark);
	(*subaddr) (aTHX_ cv);
	PUTBACK;	/* forget return values */
}



=item void gperl_croak_gerror (const char * prefix, GError * err)

within I<err>.  I<prefix> may be NULL, but I<err> may not.

Use this when wrapping a function that uses #GError for reporting runtime
errors.  The bindings map the concept of #GError to runtime exceptions;
thus, where a C programmer would wrap a function call with code that
checks for a #GError and bails out when one is found, the perl developer
simply wraps a block of code in an eval(), and the bindings croak() when
a #GError is found.

Since croak() does not return, this function handles the magic behind 
not leaking the memory associated with the #GError.  To use this you'd
do something like

 PREINIT:
   GError * error = NULL;
 CODE:
   if (!funtion_that_can_fail (something, &error))
      gperl_croak_gerror (NULL, error);

it's just that simple!

=cut
void
gperl_croak_gerror (const char * prefix, GError * err)
{
	/* croak does not return, which doesn't give us the opportunity
	 * to free the GError.  thus, we create a copy of the croak message
	 * in an SV, which will be garbage-collected, and free the GError
	 * before croaking. */
	SV * svmsg;
	if (prefix && strlen (prefix)) {
		svmsg = newSV(0);
		sv_catpvf (svmsg, "%s: %s", prefix, err->message);
	} else {
		svmsg = newSVpv (err->message, 0);
	}
	/* don't need this */
	g_error_free (err);
	/* mark it as ready to be collected */
	sv_2mortal (svmsg);
	croak (SvPV_nolen (svmsg));
}



=item gpointer gperl_alloc_temp (int nbytes)

Allocate and return a pointer to an I<nbytes>-long temporary buffer that will
be reaped at the next garbage collection sweep.  This is handy for allocating
things that need to be alloc'ed before a croak (since croak doesn't return and
give you the chance to free them).  The trick is that the memory is allocated
in a mortal perl scalar.  See the perl online manual for notes on using this
technique.

Do B<not> under any circumstances attempt to call g_free(), free(), or any other deallocator on this pointer, or you will crash the interpreter.

=cut
/*
 * taken from pgtk_alloc_temp in Gtk-Perl-0.7008/Gtk/MiscTypes.c
 */
gpointer
gperl_alloc_temp (int nbytes)
{
	dTHR;

	SV * s = sv_2mortal (newSVpv ("", 0));
	SvGROW (s, nbytes);
	memset (SvPV (s, PL_na), 0, nbytes);
	return SvPV (s, PL_na);
}


=back

=cut

MODULE = Glib		PACKAGE = Glib

BOOT:
	g_type_init ();
#if defined(G_THREADS_ENABLED) && !defined(GPERL_DISABLE_THREADSAFE)
	/*warn ("calling g_thread_init (NULL)");*/
	if (!g_thread_supported ())
		g_thread_init (NULL);
#endif
	/* boot all in one go.  other modules may not want to do it this
	 * way, if they prefer instead to perform demand loading. */
	GPERL_CALL_BOOT (boot_Glib__Type);
	GPERL_CALL_BOOT (boot_Glib__Boxed);
	GPERL_CALL_BOOT (boot_Glib__Object);
	GPERL_CALL_BOOT (boot_Glib__Signal);
	GPERL_CALL_BOOT (boot_Glib__Closure);
	GPERL_CALL_BOOT (boot_Glib__MainLoop);
	GPERL_CALL_BOOT (boot_Glib__ParamSpec);
	GPERL_CALL_BOOT (boot_Glib__IO__Channel);
