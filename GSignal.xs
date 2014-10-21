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
 * $Header: /cvsroot/gtk2-perl/gtk2-perl-xs/Glib/GSignal.xs,v 1.8 2003/08/28 21:59:32 muppetman Exp $
 */

=head2 GSignal

=over

=cut

//#define NOISY

#include "gperl.h"

static GSList * closures = NULL;

static void
forget_closure (SV * callback,
                GPerlClosure * closure)
{
#ifdef NOISY
	warn ("forget_closure %p / %p", callback, closure);
#endif
	closures = g_slist_remove (closures, closure);
}

static void
remember_closure (GPerlClosure * closure)
{
#ifdef NOISY
	warn ("remember_closure %p / %p", closure->callback, closure);
	warn ("   callback %s\n", SvPV_nolen (closure->callback));
#endif
	closures = g_slist_prepend (closures, closure);
	g_closure_add_invalidate_notifier ((GClosure *) closure,
	                                   closure->callback,
	                                   (GClosureNotify) forget_closure);
}

=item gulong gperl_signal_connect (SV * instance, char * detailed_signal, SV * callback, SV * data, GConnectFlags flags)

The actual workhorse behind GObject::signal_connect, the binding for
g_signal_connect, for use from within XS.  This creates a C<GPerlClosure>
wrapper for the given I<callback> and I<data>, and connects that closure to the
signal named I<detailed_signal> on the given GObject I<instance>.  This is only
good for named signals.  I<flags> is the same as for g_signal_connect().
I<data> may be NULL, but I<callback> must not be.

Returns the id of the installed callback.

=cut
gulong
gperl_signal_connect (SV * instance,
                      char * detailed_signal,
                      SV * callback, SV * data,
                      GConnectFlags flags)
{
	GPerlClosure * closure;

	closure = (GPerlClosure *)
			gperl_closure_new (callback, data,
			                   flags & G_CONNECT_SWAPPED);

	/* after is true only if we're called as signal_connect_after */
	closure->id =
		g_signal_connect_closure (gperl_get_object (instance),
		                          detailed_signal,
		                          (GClosure*) closure, 
		                          flags & G_CONNECT_AFTER);

	if (closure->id > 0)
		remember_closure (closure);
	
	return ((GPerlClosure*)closure)->id;
}

/*
G_SIGNAL_MATCH_ID        The signal id must be equal.
G_SIGNAL_MATCH_DETAIL    The signal detail be equal.
G_SIGNAL_MATCH_CLOSURE   The closure must be the same.
G_SIGNAL_MATCH_FUNC      The C closure callback must be the same.
G_SIGNAL_MATCH_DATA      The closure data must be the same.
G_SIGNAL_MATCH_UNBLOCKED Only unblocked signals may matched.

at the perl level, the CV replaces both the FUNC and CLOSURE.  it's rare
people will specify any of the others than FUNC and DATA, but i can see
how they would be useful so let's support them.
*/
typedef guint (*sig_match_callback) (gpointer           instance,
                                     GSignalMatchType   mask,
                                     guint              signal_id,
                                     GQuark             detail,
                                     GClosure         * closure,
                                     gpointer           func,
                                     gpointer           data);

static int
foreach_closure_matched (gpointer instance,
                         GSignalMatchType mask,
                         guint signal_id,
                         GQuark detail,
                         SV * func,
                         SV * data,
                         sig_match_callback callback)
{
	int n = 0;
	GSList * i;

	if (mask & G_SIGNAL_MATCH_CLOSURE || /* this isn't too likely */
	    mask & G_SIGNAL_MATCH_FUNC ||
	    mask & G_SIGNAL_MATCH_DATA) {
		/*
		 * to match against a function or data, we need to find the
		 * scalars for those in the GPerlClosures; we'll have to
		 * proxy this stuff.  we'll replace the func and data bits
		 * with closure in the mask.
		 *    however, we can't do the match for any of the other
		 * flags at this level, so even though our design means one
		 * closure per handler id, we still have to pass that closure
		 * on to the real C functions to do any other filtering for
		 * us.
		 */
		/* we'll compare SVs by their stringified values.  cache the
		 * stringified needles, but there's no way to cache the
		 * haystack. */
		const char * str_func = func ? SvPV_nolen (func) : NULL;
		const char * str_data = data ? SvPV_nolen (data) : NULL;

		mask &= ~(G_SIGNAL_MATCH_FUNC | G_SIGNAL_MATCH_DATA);
		mask |= G_SIGNAL_MATCH_CLOSURE;

		/* this is a little hairy because the callback may disconnect
		 * a closure, which would modify the list while we're iterating
		 * over it. */
		i = closures;
		while (i != NULL) {
			GPerlClosure * c = (GPerlClosure*) i->data;
			i = i->next;
			if ((!func || strEQ (str_func, SvPV_nolen (c->callback))) &&
			    (!data || strEQ (str_data, SvPV_nolen (c->data)))) {
				n += callback (instance, mask, signal_id,
				               detail, (GClosure*)c,
				               NULL, NULL);
			}
		}
	} else {
		/* we're not matching against a closure, so we can just
		 * pass this on through. */
		n = callback (instance, mask, signal_id, detail,
		              NULL, NULL, NULL);
	}
	return n;
}


=back

=cut


MODULE = Glib::Signal	PACKAGE = Glib::Object	PREFIX = g_

##
##/* --- typedefs --- */
##typedef struct _GSignalQuery		 GSignalQuery;
##typedef struct _GSignalInvocationHint	 GSignalInvocationHint;
##typedef GClosureMarshal			 GSignalCMarshaller;
##typedef gboolean (*GSignalEmissionHook) (GSignalInvocationHint *ihint,
##					 guint			n_param_values,
##					 const GValue	       *param_values,
##					 gpointer		data);
##typedef gboolean (*GSignalAccumulator)	(GSignalInvocationHint *ihint,
##					 GValue		       *return_accu,
##					 const GValue	       *handler_return,
##					 gpointer               data);


###
### ## creating signals ##
### new signals are currently created as a byproduct of Glib::Type:;register
###
##        g_signal_newv
##        g_signal_new_valist
##        g_signal_new

###
### ## emitting signals ##
### all versions of g_signal_emit go through Glib::Object::signal_emit,
### which is mostly equivalent to g_signal_emit_by_name.
###
##        g_signal_emitv
##        g_signal_emit_valist
##        g_signal_emit
##        g_signal_emit_by_name

## heavily borrowed from gtk-perl and goran's code in gtk2-perl, which
## was inspired by pygtk's pyobject.c::pygobject_emit

void
g_signal_emit (instance, name, ...)
	GObject * instance
	char * name
    PREINIT:
	guint signal_id, i;
	GQuark detail;
	GSignalQuery query;
	GValue * params;
    CODE:
#define ARGOFFSET 2
	if (!g_signal_parse_name (name, G_OBJECT_TYPE (instance), &signal_id,
				  &detail, TRUE))
		croak ("Unknown signal %s for object of type %s", 
			name, G_OBJECT_TYPE_NAME (instance));

	g_signal_query (signal_id, &query);

	if ((items-ARGOFFSET) != query.n_params) 
		croak ("Incorrect number of arguments for emission of signal %s in class %s; need %d but got %d",
		       name, G_OBJECT_TYPE_NAME (instance),
		       query.n_params, items-ARGOFFSET);

	/* set up the parameters to g_signal_emitv.   this is an array
	 * of GValues, where [0] is the emission instance, and the rest 
	 * are the query.n_params arguments. */
	params = g_new0 (GValue, query.n_params + 1);

	g_value_init (&params[0], G_OBJECT_TYPE (instance));
	g_value_set_object (&params[0], instance);

	for (i = 0 ; i < query.n_params ; i++) {
		g_value_init (&params[i+1], 
			      query.param_types[i] & ~G_SIGNAL_TYPE_STATIC_SCOPE);
		if (!gperl_value_from_sv (&params[i+1], ST (ARGOFFSET+i)))
			croak ("Couldn't convert value %s to type %s for parameter %d of signal %s on a %s",
			       SvPV_nolen (ST (ARGOFFSET+i)),
			       g_type_name (G_VALUE_TYPE (&params[i+1])),
			       i, name, G_OBJECT_TYPE_NAME (instance));
	}

	/* now actually call it.  what we do depends on the return type of
	 * the signal; if the signal returns anything we need to capture it
	 * and push it onto the return stack. */
	if (query.return_type != G_TYPE_NONE) {
		/* signal returns a value, woohoo! */
		GValue ret;
		memset (&ret, 0, sizeof (GValue));
		EXTEND (SP, 1);
		PUSHs (sv_2mortal (gperl_sv_from_value (&ret)));
		g_value_unset (&ret);
	} else {
		g_signal_emitv (params, signal_id, detail, NULL);
	}

	/* clean up */
	for (i = 0 ; i < query.n_params + 1 ; i++)
		g_value_unset (&params[i]);
	g_free (params);
#undef ARGOFFSET


##guint                 g_signal_lookup       (const gchar        *name,
##					     GType               itype);
##G_CONST_RETURN gchar* g_signal_name         (guint               signal_id);
##void                  g_signal_query        (guint               signal_id,
##					     GSignalQuery       *query);
##guint*                g_signal_list_ids     (GType               itype,
##					     guint              *n_ids);
##gboolean	      g_signal_parse_name   (const gchar	*detailed_signal,
##					     GType		 itype,
##					     guint		*signal_id_p,
##					     GQuark		*detail_p,
##					     gboolean		 force_detail_quark);
##GSignalInvocationHint* g_signal_get_invocation_hint (gpointer    instance);
##
##
##/* --- signal emissions --- */
##void	g_signal_stop_emission		    (gpointer		  instance,
##					     guint		  signal_id,
##					     GQuark		  detail);
##void	g_signal_stop_emission_by_name	    (gpointer		  instance,
##					     const gchar	 *detailed_signal);
void g_signal_stop_emission_by_name (GObject * instance, const gchar * detailed_signal);

##gulong	g_signal_add_emission_hook	    (guint		  signal_id,
##					     GQuark		  quark,
##					     GSignalEmissionHook  hook_func,
##					     gpointer	       	  hook_data,
##					     GDestroyNotify	  data_destroy);
##void	g_signal_remove_emission_hook	    (guint		  signal_id,
##					     gulong		  hook_id);
##
##
##/* --- signal handlers --- */
##gboolean g_signal_has_handler_pending	      (gpointer		  instance,
##					       guint		  signal_id,
##					       GQuark		  detail,
##					       gboolean		  may_be_blocked);

###
### ## connecting signals ##
### currently all versions of signal_connect go through
### Glib::Object::signal_connect, which acts like the g_signal_connect
### convenience function.
###
##gulong g_signal_connect_closure_by_id	      (gpointer		  instance,
##					       guint		  signal_id,
##					       GQuark		  detail,
##					       GClosure		 *closure,
##					       gboolean		  after);
##gulong g_signal_connect_closure	      (gpointer		  instance,
##					       const gchar       *detailed_signal,
##					       GClosure		 *closure,
##					       gboolean		  after);
##gulong g_signal_connect_data		      (gpointer		  instance,
##					       const gchar	 *detailed_signal,
##					       GCallback	  c_handler,
##					       gpointer		  data,
##					       GClosureNotify	  destroy_data,
##					       GConnectFlags	  connect_flags);

gulong
g_signal_connect (instance, detailed_signal, callback, data=NULL)
	SV * instance
	char * detailed_signal
	SV * callback
	SV * data
    ALIAS:
	Glib::Object::signal_connect = 0
	Glib::Object::signal_connect_after = 1
	Glib::Object::signal_connect_swapped = 2
    PREINIT:
	GConnectFlags flags = 0;
    CODE:
	if (ix == 1) flags |= G_CONNECT_AFTER;
	if (ix == 2) flags |= G_CONNECT_SWAPPED;
	RETVAL = gperl_signal_connect (instance, detailed_signal,
	                               callback, data, flags);
    OUTPUT:
	RETVAL


void
g_signal_handler_block (object, handler_id)
	GObject * object
	gulong handler_id

void
g_signal_handler_unblock (object, handler_id)
	GObject * object
	gulong handler_id

void
g_signal_handler_disconnect (object, handler_id)
	GObject * object
	gulong handler_id

gboolean
g_signal_handler_is_connected (object, handler_id)
	GObject * object
	gulong handler_id

 ##
 ## this would require a fair bit of the magic used in the *_by_func
 ## wrapper below...
 ##
##gulong   g_signal_handler_find              (gpointer          instance,
##                                             GSignalMatchType  mask,
##                                             guint             signal_id,
##                                             GQuark            detail,
##                                             GClosure         *closure,
##                                             gpointer          func,
##                                             gpointer          data);

 ###
 ### the *_matched functions all have the same signature and thus all 
 ### are handled by matched().
 ###

 ##  g_signal_handlers_block_matched
 ##  g_signal_handlers_unblock_matched
 ##  g_signal_handlers_disconnect_matched

 ##### FIXME oops, no typemap for GSignalMatchType...
##guint
##matched (instance, mask, signal_id, detail, func, data)
##	SV * instance
##	GSignalMatchType mask
##	guint signal_id
##	SV * detail
##	SV * func
##	SV * data
##    ALIAS:
##	Glib::Object::signal_handlers_block_matched = 0
##	Glib::Object::signal_handlers_unblock_matched = 1
##	Glib::Object::signal_handlers_disconnect_matched = 2
##    PREINIT:
##	sig_match_callback callback = NULL;
##	GQuark real_detail = 0;
##    CODE:
##	switch (ix) {
##	    case 0: callback = g_signal_handlers_block_matched; break;
##	    case 1: callback = g_signal_handlers_unblock_matched; break;
##	    case 2: callback = g_signal_handlers_disconnect_matched; break;
##	}
##	if (!callback)
##		croak ("internal problem -- xsub aliased to invalid ix");
##	if (detail && SvPOK (detail)) {
##		real_detail = g_quark_try_string (SvPV_nolen (detail));
##		if (!real_detail)
##			croak ("no such detail %s", SvPV_nolen (detail));
##	}
##	RETVAL = foreach_closure_matched (gperl_get_object (instance),
##	                                  mask, signal_id, real_detail,
##	                                  func, data);
##    OUTPUT:
##	RETVAL


##/* --- chaining for language bindings --- */
##void	g_signal_override_class_closure	      (guint		  signal_id,
##					       GType		  instance_type,
##					       GClosure		 *class_closure);
##void	g_signal_chain_from_overridden	      (const GValue      *instance_and_params,
##					       GValue            *return_value);
##


 ### the *_by_func functions all have the same signature, and thus are
 ### handled by do_stuff_by_func.

 ## g_signal_handlers_disconnect_by_func(instance, func, data)
 ## g_signal_handlers_block_by_func(instance, func, data)
 ## g_signal_handlers_unblock_by_func(instance, func, data)

int
do_stuff_by_func (instance, func, data=NULL)
	GObject * instance
	SV * func
	SV * data
    ALIAS:
	Glib::Object::signal_handlers_block_by_func = 0
	Glib::Object::signal_handlers_unblock_by_func = 1
	Glib::Object::signal_handlers_disconnect_by_func = 2
    PREINIT:
	sig_match_callback callback = NULL;
    CODE:
	switch (ix) {
	    case 0: callback = g_signal_handlers_block_matched; break;
	    case 1: callback = g_signal_handlers_unblock_matched; break;
	    case 2: callback = g_signal_handlers_disconnect_matched; break;
	}
	if (!callback)
		croak ("internal problem -- xsub aliased to invalid ix");
	RETVAL = foreach_closure_matched (instance, G_SIGNAL_MATCH_CLOSURE,
	                                  0, 0, func, data, callback);
    OUTPUT:
	RETVAL

