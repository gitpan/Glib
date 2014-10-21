/*
 * Copyright (C) 2003 by the gtk2-perl team (see the file AUTHORS for the full
 * list)
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Library General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at your
 * option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Library General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307  USA.
 *
 * $Header: /cvsroot/gtk2-perl/gtk2-perl-xs/Glib/GType.xs,v 1.17 2003/10/10 02:43:41 muppetman Exp $
 */

=head2 GType / GEnum / GFlags

=over

=cut

#include "gperl.h"

/* for fundamental types */
static GHashTable * types_by_package = NULL;
static GHashTable * packages_by_type = NULL;

/* locks for the above */
G_LOCK_DEFINE_STATIC (types_by_package);
G_LOCK_DEFINE_STATIC (packages_by_type);

/*
 * this is just like gtk_type_class --- it keeps a reference on the classes
 * it returns to they stick around.  this is most important for enums and
 * flags, which will be created and destroyed every time you look them up
 * unless you pull this trick.  duplicates a pointer when you are using
 * gtk, but you aren't always using gtk and it's better to be safe than sorry.
 */
gpointer
gperl_type_class (GType type)
{
	static GQuark quark_static_class = 0;
	gpointer class;

	if (!G_TYPE_IS_ENUM (type) && !G_TYPE_IS_FLAGS (type))
		g_return_val_if_fail (G_TYPE_IS_OBJECT (type), NULL);

	class = g_type_get_qdata (type, quark_static_class);
	if (!class) {
		if (!quark_static_class)
			quark_static_class = g_quark_from_static_string 
						("GPerlStaticTypeClass");
		class = g_type_class_ref (type);
		g_assert (class != NULL);
		g_type_set_qdata (type, quark_static_class, class);
	}

	return class;
}

=item void gperl_register_fundamental (GType gtype, const char * package)

register a mapping between I<gtype> and I<package>.  this is for "fundamental"
types which have no other requirements for metadata storage, such as GEnums,
GFlags, or real GLib fundamental types like G_TYPE_INT, G_TYPE_FLOAT, etc.

=cut
void
gperl_register_fundamental (GType gtype, const char * package)
{
	char * p;
	G_LOCK (types_by_package);
	G_LOCK (packages_by_type);
	if (!types_by_package) {
		types_by_package = 
			g_hash_table_new_full (g_str_hash,
			                       g_str_equal,
			                       NULL, NULL);
		packages_by_type =
			g_hash_table_new_full (g_direct_hash,
			                       g_direct_equal,
			                       NULL, 
			                       (GDestroyNotify)g_free);
	}
	p = g_strdup (package);
	g_hash_table_insert (packages_by_type, (gpointer)gtype, p);
	g_hash_table_insert (types_by_package, p, (gpointer)gtype);
	G_UNLOCK (types_by_package);
	G_UNLOCK (packages_by_type);
}

=item GType gperl_fundamental_type_from_package (const char * package)

look up the GType corresponding to a I<package> registered by
gperl_register_fundamental().

=cut
GType
gperl_fundamental_type_from_package (const char * package)
{
	GType res;
	G_LOCK (types_by_package);
	res = (GType) g_hash_table_lookup (types_by_package, package);
	G_UNLOCK (types_by_package);
	return res;
}

=item const char * gperl_fundamental_package_from_type (GType gtype)

look up the package corresponding to a I<gtype> registered by
gperl_register_fundamental().

=cut
const char * 
gperl_fundamental_package_from_type (GType gtype)
{
	const char * res;
	G_LOCK (packages_by_type);
	res = (const char *)
		g_hash_table_lookup (packages_by_type, (gpointer)gtype);
	G_UNLOCK (packages_by_type);
	return res;
}


/****************************************************************************
 * enum and flags handling (mostly from the original gtk2_perl code)
 */

static gboolean
streq_enum (register const char * a, 
	    register const char * b)
{
	while (*a && *b) {
		if (*a == *b || 
		    ((*a == '-' || *a == '_') && (*b == '-' || *b == '_'))) {
			a++;
			b++;
		} else
			return FALSE;
	}
	return *a == *b;
}

static GEnumValue *
gperl_type_enum_get_values (GType enum_type)
{
	GEnumClass * class;
	g_return_val_if_fail (G_TYPE_IS_ENUM (enum_type), NULL);
	class = gperl_type_class (enum_type);
	return class->values;
}

static GFlagsValue *
gperl_type_flags_get_values (GType flags_type)
{
	GFlagsClass * class;
	g_return_val_if_fail (G_TYPE_IS_FLAGS (flags_type), NULL);
	class = gperl_type_class (flags_type);
	return class->values;
}


=item gboolean gperl_try_convert_enum (GType gtype, SV * sv, gint * val)

return FALSE if I<sv> can't be mapped to a valid member of the registered
enum type I<gtype>; otherwise, return TRUE write the new value to the
int pointed to by I<val>.

you'll need this only in esoteric cases.

=cut
gboolean
gperl_try_convert_enum (GType type,
			SV * sv,
			gint * val)
{
	GEnumValue * vals;
	char *val_p = SvPV_nolen(sv);
	if (*val_p == '-') val_p++;
	vals = gperl_type_enum_get_values (type);
	while (vals && vals->value_nick && vals->value_name) {
		if (streq_enum (val_p, vals->value_nick) || 
		    streq_enum (val_p, vals->value_name)) {
			*val = vals->value;
			return TRUE;
		}
		vals++;
	}
	return FALSE;
}

=item gint gperl_convert_enum (GType type, SV * val)

croak if I<val> is not part of I<type>, otherwise return corresponding value

=cut
gint
gperl_convert_enum (GType type, SV * val)
{
	SV * r;
	int ret;
	GEnumValue * vals;
	if (gperl_try_convert_enum (type, val, &ret))
		return ret;
	
	/*
	 * This is an error, val should be included in the enum type.
	 * croak with a message.  note that we build the message in an
	 * SV so it will be properly GC'd
	 */
	vals = gperl_type_enum_get_values (type);
	r = newSVpv ("", 0);
	while (vals && vals->value_nick) {
		sv_catpv (r, vals->value_nick);
		if (vals->value_name) {
			sv_catpv (r, " / ");
			sv_catpv (r, vals->value_name);
		}
		if (++vals && vals->value_nick)
			sv_catpv (r, ", ");
	}
	croak ("FATAL: invalid enum %s value %s, expecting: %s",
	       g_type_name (type), SvPV_nolen (val), SvPV_nolen (r));

	/* not reached */
	return 0;
}

=item SV * gperl_convert_back_enum_pass_unknown (GType type, gint val)

return a scalar containing the nickname of the enum value I<val>, or the
integer value of I<val> if I<val> is not a member of the enum I<type>.

=cut
SV *
gperl_convert_back_enum_pass_unknown (GType type,
				      gint val)
{
	GEnumValue * vals = gperl_type_enum_get_values (type);
	while (vals && vals->value_nick && vals->value_name) {
		if (vals->value == val)
			return newSVpv (vals->value_nick, 0);
		vals++;
	}
	return newSViv (val);
}

=item SV * gperl_convert_back_enum (GType type, gint val)

return a scalar which is the nickname of the enum value val, or croak if
val is not a member of the enum.

=cut
SV *
gperl_convert_back_enum (GType type,
			 gint val)
{
	GEnumValue * vals = gperl_type_enum_get_values (type);
	while (vals && vals->value_nick && vals->value_name) {
		if (vals->value == val)
			return newSVpv (vals->value_nick, 0);
		vals++;
	}
	croak ("FATAL: could not convert value %d to enum type %s",
	       val, g_type_name (type));
	return NULL; /* not reached */
}

=item gboolean gperl_try_convert_flag (GType type, const char * val_p, gint * val)

like gperl_try_convert_enum(), but for GFlags.

=cut
gboolean
gperl_try_convert_flag (GType type,
                        const char * val_p,
                        gint * val)
{
	GFlagsValue * vals = gperl_type_flags_get_values (type);
	while (vals && vals->value_nick && vals->value_name) {
		if (streq_enum (val_p, vals->value_name) || 
		    streq_enum (val_p, vals->value_nick)) {
                        *val = vals->value;
                        return TRUE;
		}
		vals++;
	}
        
        return FALSE;
}

=item gint gperl_convert_flag_one (GType type, const char * val)

croak if I<val> is not part of I<type>, otherwise return corresponding value.

=cut
gint
gperl_convert_flag_one (GType type, 
			const char * val_p)
{
	SV *r;
	GFlagsValue * vals = gperl_type_flags_get_values (type);
	gint ret;
	if (gperl_try_convert_flag (type, val_p, &ret))
		return ret;

	/* This is an error, val should be included in the flags type, die */
	vals = gperl_type_flags_get_values (type);
	r = newSVpv("", 0);
	while (vals && vals->value_nick) {
		sv_catpv (r, vals->value_nick);
		if (vals->value_name) {
			sv_catpv (r, " / ");
			sv_catpv (r, vals->value_name);
		}
		if (++vals && vals->value_nick)
			sv_catpv (r, ", ");
	}
	croak ("FATAL: invalid flags %s value %s, expecting: %s",
	       g_type_name (type), val_p, SvPV_nolen (r));

	/* not reached */
	return 0;
}

=item gint gperl_convert_flags (GType type, SV * val)

collapse a list of strings to an integer with all the correct bits set,
croak if anything is invalid.

=cut
gint
gperl_convert_flags (GType type,
		     SV * val)
{
	if (SvTYPE (val) == SVt_PV)
		return gperl_convert_flag_one (type, SvPV_nolen (val));
	if (SvROK (val) && SvTYPE (SvRV(val)) == SVt_PVAV) {
		AV* vals = (AV*) SvRV(val);
		gint value = 0;
		int i;
		for (i=0; i<=av_len(vals); i++)
			value |= gperl_convert_flag_one (type,
					 SvPV_nolen (*av_fetch (vals, i, 0)));
		return value;
	}
	croak ("FATAL: invalid flags %s value %s, expecting a string scalar or an arrayref of strings", 
	       g_type_name (type), SvPV_nolen (val));
	return 0; /* not reached */
}

=item SV * gperl_convert_back_flags (GType type, gint val)

convert a bitfield to a list of strings.

=cut
SV *
gperl_convert_back_flags (GType type,
			  gint val)
{
	GFlagsValue * vals = gperl_type_flags_get_values (type);
	AV * flags = newAV ();
	while (vals && vals->value_nick && vals->value_name) {
		if (vals->value & val)
			av_push (flags, newSVpv (vals->value_nick, 0));
		vals++;
	}
	return newRV_noinc ((SV*) flags);
}

=back

=head2 Inheritance management

=over

=item void gperl_set_isa (const char * child_package, const char * parent_package)

tell perl that I<child_package> inherits I<parent_package>, after whatever else
is already there.  equivalent to C<< push @{$parent_package}::ISA, $child_package; >>

=cut
void
gperl_set_isa (const char * child_package,
               const char * parent_package)
{
	char * child_isa_full;
	AV * isa;

	child_isa_full = g_strconcat (child_package, "::ISA", NULL);
	isa = get_av (child_isa_full, TRUE); /* create on demand */
	/* warn ("--> @%s = qw(%s);\n", child_isa_full, parent_package); */
	g_free (child_isa_full);

	av_push (isa, newSVpv (parent_package, 0));
}


=item void gperl_prepend_isa (const char * child_package, const char * parent_package)

tell perl that I<child_package> inherits I<parent_package>, but before whatever
else is already there.  equivalent to C<< unshift @{$parent_package}::ISA, $child_package; >>

=cut
void
gperl_prepend_isa (const char * child_package,
                   const char * parent_package)
{
	char * child_isa_full;
	AV * isa;

	child_isa_full = g_strconcat (child_package, "::ISA", NULL);
	isa = get_av (child_isa_full, TRUE); /* create on demand */
	/* warn ("--> @%s = qw(%s);\n", child_isa_full, parent_package); */
	g_free (child_isa_full);

	av_unshift (isa, 1);
	av_store (isa, 0, newSVpv (parent_package, 0));
}


=item GType gperl_type_from_package (const char * package)

Look up the GType associated with I<package>, regardless of how it was
registered.  Returns 0 if no mapping can be found.

=cut
GType
gperl_type_from_package (const char * package)
{
	GType t;
	t = gperl_object_type_from_package (package);
	if (t)
		return t;

	t = gperl_boxed_type_from_package (package);
	if (t)	
		return t;

	t = gperl_fundamental_type_from_package (package);
	if (t)	
		return t;

	return 0;
}

=item GType gperl_package_from_type (GType gtype)

Look up the name of the package associated with I<gtype>, regardless of how it
was registered.  Returns NULL if no mapping can be found.

=cut
const char * 
gperl_package_from_type (GType type)
{
	const char * p;
	p = gperl_object_package_from_type (type);
	if (p)
		return p;

	p = gperl_boxed_package_from_type (type);
	if (p)	
		return p;

	p = gperl_fundamental_package_from_type (type);
	if (p)	
		return p;

	return NULL;
}


=back

=head2 Boxed type support for SV

In order to allow GValues to hold perl SVs we need a GBoxed wrapper.

=over

=item GPERL_TYPE_SV

Evaluates to the GType for SVs.  The bindings register a mapping between
GPERL_TYPE_SV and the package 'Glib::Scalar' with gperl_register_boxed().

=item SV * gperl_sv_copy (SV * sv)

implemented as C<< newSVsv (sv) >>.

=item void gperl_sv_free (SV * sv)

implemented as C<< SvREFCNT_dec (sv) >>.

=cut

void
gperl_sv_free (SV * sv)
{
	SvREFCNT_dec (sv);
}

SV *
gperl_sv_copy (SV * sv)
{
	return newSVsv (sv);
}

GType
gperl_sv_get_type (void)
{
	static GType sv_type = 0;
	if (sv_type == 0)
		sv_type = g_boxed_type_register_static ("GPerlSV",
		                                        (GBoxedCopyFunc) gperl_sv_copy,
		                                        (GBoxedFreeFunc) gperl_sv_free);
	return sv_type;
}


=back

=head2 UTF-8 strings with gchar

By convention, gchar* is assumed to point to UTF8 string data,
and char* points to ascii string data.  Here we define a pair of
wrappers for the boilerplate of upgrading Perl strings.  They
are implemented as functions rather than macros, because comma
expressions in macros are not supported by all compilers.

These functions should be used instead of newSVpv and SvPV_nolen
in all cases which deal with gchar* types.

=over

=item gchar * SvGChar (SV * sv)

extract a UTF8 string from I<sv>.

=cut

/*const*/ gchar *
SvGChar (SV * sv)
{
	sv_utf8_upgrade (sv);
	return (/*const*/ gchar*) SvPV_nolen (sv);
}

=item SV * newSVGChar (const gchar * str)

copy a UTF8 string into a new SV.

=cut

SV *
newSVGChar (const gchar * str)
{
	SV * sv;
	if (!str) return &PL_sv_undef;
	/* sv_setpv ((SV*)$arg, $var); */
	sv = newSVpv (str, 0);
	SvUTF8_on (sv);
	return sv;
}




/**************************************************************************/
/*
 * support for pure-perl GObject subclasses.
 *
 * this includes 
 *   * creating new object properties
 *   * creating new signals
 *   * overriding the class closures (that is, default handlers) of
 *     existing signals
 *
 * it looks like a huge quivering mass of scary-looking, visually dense
 * code, but it's really simple at the core; the verbosity comes from
 * lots of boilerplate translations and such.
 */

/* a closure used for the `class closure' of a signal.  As this gets
 * all the info from the first argument to the closure and the
 * invocation hint, we can have a single closure that handles all
 * class closure cases.  We call a method by the name of the signal
 * with "do_" prepended.
 */

static void
gperl_signal_class_closure_marshal (GClosure *closure,
				    GValue *return_value,
				    guint n_param_values,
				    const GValue *param_values,
				    gpointer invocation_hint,
				    gpointer marshal_data)
{
	GSignalInvocationHint *hint = (GSignalInvocationHint *)invocation_hint;
	GSignalQuery query;
	gchar * tmp;
	SV * method_name;
	guint i;
        HV *stash;
        SV **slot;

#ifdef NOISY
	warn ("gperl_signal_class_closure_marshal");
#endif
	g_return_if_fail(invocation_hint != NULL);

	g_signal_query (hint->signal_id, &query);

	/* construct method name for this class closure */
	method_name = newSVpvf ("do_%s", query.signal_name);

	/* convert dashes to underscores.  g_signal_name converts all the
	 * underscores in the signal name to dashes, but dashes are not
	 * valid in subroutine names. */
	for (tmp = SvPV_nolen (method_name); *tmp != '\0'; tmp++)
		if (*tmp == '-') *tmp = '_';

	stash = gperl_object_stash_from_type (query.itype);
        assert (stash);
	tmp = SvPV (method_name, i);
        slot = hv_fetch (stash, tmp, i, 0);

        /* does the function exist? then call it. */
        if (slot && GvCV (*slot)) {	
		GObject *object;
		int flags;
		dSP;
	
		ENTER;
		SAVETMPS;

		PUSHMARK (SP);

		/* get the object passed as the first argument to the closure */
		object = g_value_get_object (&param_values[0]);
		g_return_if_fail (object != NULL && G_IS_OBJECT (object));
		EXTEND (SP, (int) (1 + n_param_values));
		PUSHs (sv_2mortal (gperl_new_object (object, FALSE)));

		/* push parameter values onto the stack */
		for (i = 1; i < n_param_values; i++)
			PUSHs (sv_2mortal (gperl_sv_from_value
							((GValue*)
							&param_values[i])));

		PUTBACK;

#ifdef NOISY
		warn ("    calling method %s", SvPV_nolen (method_name));
#endif
		/* now call it */

		flags = G_EVAL | (return_value ? G_SCALAR : G_VOID|G_DISCARD);
		call_method (SvPV_nolen (method_name), flags);

		if (SvTRUE (ERRSV)) 
			gperl_run_exception_handlers ();

		if (return_value) {
			SPAGAIN;
			gperl_value_from_sv (return_value, POPs);
		}

		FREETMPS;
		LEAVE;
/*
	} else {
		croak ("cannot find object method %s of %s in emission of "
		       "signal %s\n   if you want to disable the class "
		       "closure or use a different method,\n   then specify "
		       "the class_closure key when creating the signal.\n"
		       "   croaking", SvPV_nolen (method_name),
		       g_type_name (query.itype), query.signal_name);
*/	}
}

/**
 * gperl_signal_class_closure_get:
 *
 * Returns the GClosure used for the class closure of signals.  When
 * called, it will invoke the method do_signalname (for the signal
 * "signalname").
 *
 * Returns: the closure.
 */
GClosure *
gperl_signal_class_closure_get(void)
{
	/* FIXME does this need a lock? */
	static GClosure *closure;

	if (closure == NULL) {
		closure = g_closure_new_simple(sizeof(GClosure), NULL);
		g_closure_set_marshal (closure,
		                       gperl_signal_class_closure_marshal);

		g_closure_ref (closure);
		g_closure_sink (closure);
	}
	return closure;
}

typedef struct {
	GClosure           * class_closure;
	GSignalFlags         flags;
	GSignalAccumulator   accumulator;
	GPerlCallback      * accu_data;
	GType                return_type;
	GType              * param_types;
	guint                n_params;
} SignalParams;

static SignalParams *
signal_params_new (void)
{
	SignalParams * s = g_new0 (SignalParams, 1);
	s->flags = G_SIGNAL_RUN_FIRST;
	s->return_type = G_TYPE_NONE;
	return s;
}

static void
signal_params_free (SignalParams * s)
{
	if (s) g_free (s->param_types);
	/* the closure will have been sunken and reffed by the signal. */
	/* we are leaking the accumulator.  i don't know any other way. */
	g_free (s);
}

static gboolean
gperl_real_signal_accumulator (GSignalInvocationHint *ihint,
                               GValue *return_accu,
                               const GValue *handler_return,
                               gpointer data)
{
	GPerlCallback * callback = (GPerlCallback *)data;
	dSP;
	SV * sv;
	int n;
	gboolean retval;

/*	warn ("gperl_real_signal_accumulator"); */

	/* invoke the callback, with custom marshalling */
	ENTER;
	SAVETMPS;

	PUSHMARK (SP);

	PUSHs (sv_2mortal (newSVGSignalInvocationHint (ihint)));
	PUSHs (sv_2mortal (gperl_sv_from_value (return_accu)));
	PUSHs (sv_2mortal (gperl_sv_from_value (handler_return)));

	if (callback->data)
		XPUSHs (callback->data);

	PUTBACK;

/* warn ("return_accum is '%s'\n", SvPV_nolen (sv_2mortal (gperl_sv_from_value (return_accu))));
 * warn ("handler_return was '%s'\n", SvPV_nolen (sv_2mortal (gperl_sv_from_value (handler_return)))); */

	n = call_sv (callback->func, G_EVAL|G_ARRAY);

	if (SvTRUE (ERRSV)) {
		warn ("### WOAH!  unhandled exception in a signal accumulator!\n"
		      "### this is really uncool, and for now i'm not even going to\n"
		      "### try to recover.\n"
		      "###    aborting");
		abort ();
	}

	if (n != 2) {
		warn ("###\n"
		      "### signal accumulator functions must return two values on the perl stack:\n"
		      "### the (possibly) modified return_acc\n"
		      "### and a boolean value, true if emission should continue\n"
		      "###\n"
		      "### your sub returned %d value%s\n"
		      "###\n"
		      "### there's no resonable way to recover from this.\n"
		      "### you must fix this code.\n"
		      "###    aborting",
		      n, n==1?"":"s");
		abort ();
	}

	SPAGAIN;

	/*
	 * pop the results off the stack... don't forget that they come back
	 * in reverse order.  (seems so obvious, but, well... i feel dumb.)
	 */
	sv = POPs;
	gperl_value_from_sv (return_accu, sv);

	sv = POPs;
	retval = SvTRUE (sv);

/* warn ("return_accum is '%s'\n", SvPV_nolen (sv_2mortal (gperl_sv_from_value (return_accu))));
 * warn ("handler_return was '%s'\n", SvPV_nolen (sv_2mortal (gperl_sv_from_value (handler_return)))); */

	FREETMPS;
	LEAVE;

	return retval;
}

/*
parse a hash describing a new signal into a SignalParams struct.

all keys are allowed to default.

we look for:

  flags => GSignalFlags, if not present, assumed to be run-first
  param_types => reference to a list of package names,
                 if not present, assumed to be empty (no parameters)
  class_closure => reference to a subroutine to call as the class closure.
                   may also be a string interpreted as the name of a 
                   subroutine to call, but you should be very very very
                   careful about that.
                   if not present, the library will attempt to call the
                   method named "do_signal_name" for the signal "signal_name"
                   (uses underscores).
  return_type => package name for return value.  if undefined or not present,
                 the signal expects no return value.  if defined, the signal
                 is expected to return a value; flags must be set such that
                 the signal does not run only first (at least use 'run-last').
  accumulator => quoting the Glib manual: "The signal accumulator is a
                 special callback function that can be used to collect
                 return values of the various callbacks that are called
                 during a signal emission."
  
 */
static SignalParams *
parse_signal_hash (GType instance_type,
                   const gchar * signal_name,
                   HV * hv)
{
	SignalParams * s = signal_params_new ();
	SV ** svp;

	svp = hv_fetch (hv, "flags", 5, FALSE);
	if (svp && (*svp) && SvTRUE (*svp))
		s->flags = SvGSignalFlags (*svp);

	svp = hv_fetch (hv, "param_types", 11, FALSE);
	if (svp && (*svp) && SvTRUE (*svp) && SvROK (*svp)
	    && SvTYPE (SvRV (*svp)) == SVt_PVAV) {
		guint i;
		AV * av = (AV*) SvRV (*svp);
		s->n_params = av_len (av) + 1;
		s->param_types = g_new (GType, s->n_params);
		for (i = 0 ; i < s->n_params ; i++) {
			svp = av_fetch (av, i, 0);
			if (!svp) croak ("how did this happen?");
			s->param_types[i] =
				gperl_type_from_package (SvPV_nolen (*svp));
			if (!s->param_types[i])
				croak ("unknown or unregistered param type %s",
				       SvPV_nolen (*svp));
		}
	}

	svp = hv_fetch (hv, "class_closure", 13, FALSE);
	if (svp && *svp) {
		if (SvTRUE (*svp))
			s->class_closure =
				gperl_closure_new (*svp, NULL, FALSE);
		/* else the class closure is NULL */
	} else {
		s->class_closure = gperl_signal_class_closure_get ();
	}

	svp = hv_fetch (hv, "return_type", 11, FALSE);
	if (svp && (*svp) && SvTRUE (*svp)) {
		s->return_type = gperl_type_from_package (SvPV_nolen (*svp));
		if (!s->return_type)
			croak ("unknown or unregistered return type %s",
			       SvPV_nolen (*svp));
	}

	svp = hv_fetch (hv, "accumulator", 11, FALSE);
	if (svp && *svp) {
		SV * func = *svp;
		svp = hv_fetch (hv, "accu_data", 9, FALSE);
		s->accumulator = gperl_real_signal_accumulator;
		s->accu_data = gperl_callback_new (func, svp ? *svp : NULL,
		                                   0, NULL, 0);
	}

	return s;
}


static void
add_signals (GType instance_type, HV * signals)
{
	GObjectClass *oclass;
	HE * he;

	oclass = g_type_class_ref (instance_type);

	hv_iterinit (signals);
	while (NULL != (he = hv_iternext (signals))) {
		I32 keylen;
		char * signal_name;
		guint signal_id;
		SV * value;

		/* the key is the signal name */
		signal_name = hv_iterkey (he, &keylen);
/*		warn ("\n#####\nsignal name: %s\n", signal_name); */
		/* if the signal is defined at this point, we're going to
		 * override the installed closure. */
		signal_id = g_signal_lookup (signal_name, instance_type);

		/* parse the key's value... */
		value = hv_iterval (signals, he);
		if (SvROK (value) && SvTYPE (SvRV (value)) == SVt_PVHV) {
			/*
			 * value is a hash describing a new signal.
			 */
			SignalParams * s;

			if (signal_id) {
				GSignalQuery q;
				g_signal_query (signal_id, &q);
				croak ("signal %s already exists in %s",
				       signal_name, g_type_name (q.itype));
			}

			s = parse_signal_hash (instance_type,
			                       signal_name,
			                       (HV*) SvRV (value));
/*			warn ("\ncreating signal %s with accumulator %p and accu_data %p\n", signal_name, s->accumulator, s->accu_data);
 *			sv_setsv (DEFSV, newSVGSignalFlags (s->flags));
 *			eval_pv ("warn ('   flags ['.join (', ', @$_).\"]\n\")", 0); */
			signal_id = g_signal_newv (signal_name,
			                           instance_type,
			                           s->flags,
			                           s->class_closure,
			                           s->accumulator,
						   s->accu_data, 
						   NULL, /* c_marshaller */
			                           s->return_type,
			                           s->n_params,
			                           s->param_types);
			signal_params_free (s);
			if (signal_id == 0)
				croak ("failed to create signal %s",
				       signal_name);

		} else if ((SvPOK (value) && SvTRUE (value)) ||
		           (SvROK (value) && SvTYPE (SvRV (value)) == SVt_PVCV)) {
			/*
			 * a subroutine reference or method name to override
			 * the class closure for this signal.
			 */
			GClosure * closure;
			if (!signal_id)
				croak ("can't override class closure for "
				       "unknown signal %s", signal_name);
			closure = gperl_closure_new (value, NULL, FALSE);
			g_signal_override_class_closure (signal_id,
			                                 instance_type,
			                                 closure);
			
		} else {
			croak ("value for signal key '%s' must be either a "
			       "subroutine (the class closure override) or "
			       "a reference to a hash describing the signal"
			       " to create",
			       signal_name);
		}
	}

	g_type_class_unref (oclass);
}

static void
add_properties (GType instance_type, AV * properties)
{
	GObjectClass *oclass;
        int propid;

	oclass = g_type_class_ref (instance_type);

        for (propid = 0; propid <= av_len (properties); propid++)
		g_object_class_install_property (oclass, propid + 1,
		                                 SvGParamSpec (*av_fetch (properties, propid, 1)));

	g_type_class_unref (oclass);
}

static void
gperl_type_get_property (GObject * object,
                         guint property_id,
                         GValue * value,
                         GParamSpec * pspec)
{
        HV *stash = gperl_object_stash_from_type (pspec->owner_type);
        SV **slot;
        assert (stash);

#ifdef NOISY
	warn ("%s:%d: gperl_type_get_property - stub", G_STRLOC);
#endif
        slot = hv_fetch (stash, "GET_PROPERTY", sizeof ("GET_PROPERTY") - 1, 0);

        /* does the function exist? then call it. */
        if (slot && GvCV (*slot)) {
                  dSP;            
                
                  ENTER;                         
                  SAVETMPS;

                  PUSHMARK (SP);
                  XPUSHs (sv_2mortal (gperl_new_object (object, FALSE)));
                  XPUSHs (sv_2mortal (newSVGParamSpec (pspec)));
                  PUTBACK;

                  if (1 != call_sv ((SV *)GvCV (*slot), G_SCALAR))
                          croak ("%s->GET_PROPERTY didn't return exactly one value", HvNAME (stash));

                  SPAGAIN;

                  gperl_value_from_sv (value, POPs);

                  FREETMPS;
                  LEAVE;
        }
}

static void
gperl_type_set_property (GObject * object,
                         guint property_id,
                         const GValue * value,
                         GParamSpec * pspec)
{
        HV *stash = gperl_object_stash_from_type (pspec->owner_type);
        SV **slot;
        assert (stash);

#ifdef NOISY
	warn ("%s:%d: gperl_type_set_property - stub", G_STRLOC);
#endif

        slot = hv_fetch (stash, "SET_PROPERTY", sizeof ("SET_PROPERTY") - 1, 0);

        /* does the function exist? then call it. */
        if (slot && GvCV (*slot)) {
                  dSP;            
                
                  ENTER;                         
                  SAVETMPS;

                  PUSHMARK (SP);
                  XPUSHs (sv_2mortal (gperl_new_object (object, FALSE)));
                  XPUSHs (sv_2mortal (newSVGParamSpec (pspec)));
                  XPUSHs (sv_2mortal (gperl_sv_from_value (value)));
                  PUTBACK;

                  call_sv ((SV *)GvCV (*slot), G_VOID|G_DISCARD);

                  FREETMPS;
                  LEAVE;
        }
}

static void
gperl_type_finalize (GObject * instance)
{
	int do_nonperl = 1;
	GObjectClass *class;

        /* BIG BUG:
         * we walk down the class hierarchy and call all
         * FINALIZE_INSTANCE functions for perl.
         * We also call the first non-perl finalize function.
         * This does NOT work when we have gobject -> perl -> non-perl -> perl.
         * In this case we should probably remove the perl SV so that later
         * invocations will not try to call into perl.
          (i.e. check wrapper_sv, steal wrapper_sv, finalize)
         */

        class = G_OBJECT_GET_CLASS (instance);

        do {
                /* call finalize for each perl class and the topmost non-perl class */
        	if (class->finalize == gperl_type_finalize) {
                        if (!PL_in_clean_objs) {
                                HV *stash = gperl_object_stash_from_type (G_TYPE_FROM_CLASS (class));
                                SV **slot = hv_fetch (stash, "FINALIZE_INSTANCE", sizeof ("FINALIZE_INSTANCE") - 1, 0);

                                instance->ref_count += 2; /* HACK: temporarily revive the object. */

                                /* does the function exist? then call it. */
                                if (slot && GvCV (*slot)) {
                                          dSP;            
                                        
                                          ENTER;                         
                                          SAVETMPS;

                                          PUSHMARK (SP);
                                          XPUSHs (sv_2mortal (gperl_new_object (instance, FALSE)));
                                          PUTBACK;

                                          call_sv ((SV *)GvCV (*slot), G_VOID|G_DISCARD);

                                          FREETMPS;
                                          LEAVE;
                                }

                                instance->ref_count -= 2; /* HACK END */
                        }
                } else if (do_nonperl) {
                        class->finalize (instance);
                        do_nonperl = 0;
                }

                class = g_type_class_peek_parent (class);
        } while (class);
}

static void
gperl_type_instance_init (GObject * instance)
{
        dSP;            
	/*
	 * for new objects, this may be the place where the initial 
	 * perl object is created.  we won't worry about the owner
	 * semantics here, but since initializers are called from the
	 * inside out, we will need to worry about making sure we get
	 * blessed into the right class!
	 */
        SV *obj;
        HV *stash = gperl_object_stash_from_type (G_OBJECT_TYPE (instance));
        SV **slot;
	g_assert (stash != NULL);

        ENTER;                         
        SAVETMPS;

	obj = sv_2mortal (gperl_new_object (instance, FALSE));
        /* we need to re-bless the wrapper because classes change
         * during construction of an object. */
	sv_bless (obj, stash);

	/* get the INIT_INSTANCE sub from this package. */
        slot = hv_fetch (stash, "INIT_INSTANCE", sizeof ("INIT_INSTANCE") - 1, 0);

#ifdef NOISY
	warn ("gperl_type_instance_init  %s (%p) => %s\n",
	      G_OBJECT_TYPE_NAME (instance), instance, SvPV_nolen (obj));
#endif

        /* does the function exist? then call it. */
        if (slot && GvCV (*slot)) {
                  PUSHMARK (SP);
                  XPUSHs (obj);
                  PUTBACK;

                  call_sv ((SV *)GvCV (*slot), G_VOID|G_DISCARD);

        }

        FREETMPS;
        LEAVE;
}

static void
gperl_type_class_init (GObjectClass * class)
{
	class->finalize     = gperl_type_finalize;
	class->get_property = gperl_type_get_property;
	class->set_property = gperl_type_set_property;
}

/* make sure we close the open list to keep from freaking out pod readers... */

=back

=cut

MODULE = Glib::Type	PACKAGE = Glib::Type	PREFIX = g_type_

BOOT:
	gperl_register_fundamental (G_TYPE_BOOLEAN, "Glib::Boolean");
	gperl_register_fundamental (G_TYPE_INT, "Glib::Int");
	gperl_register_fundamental (G_TYPE_UINT, "Glib::Uint");
	gperl_register_fundamental (G_TYPE_DOUBLE, "Glib::Double");
	gperl_register_boxed (GPERL_TYPE_SV, "Glib::Scalar", NULL);


void
g_type_register (class, parent_package, new_package, ...);
	SV * class
	char * parent_package
	char * new_package
    PREINIT:
	int i;
	GTypeInfo type_info;
	GTypeQuery query;
	GType parent_type, new_type;
	char * new_type_name, * s;
    CODE:
	UNUSED(class);
	/* start with a clean slate */
	memset (&type_info, 0, sizeof (GTypeInfo));
	type_info.class_init = (GClassInitFunc) gperl_type_class_init;
	type_info.instance_init = (GInstanceInitFunc) gperl_type_instance_init;

	/* yeah, i could just call gperl_object_type_from_package directly,
	 * but i want the error messages to be more informative. */
	parent_type = gperl_type_from_package (parent_package);
	if (!parent_type)
		croak ("package %s has not been registered with GPerl",
		       parent_package);
	if (!g_type_is_a (parent_type, G_TYPE_OBJECT))
		croak ("%s (%s) is not a descendent of Glib::Object (GObject)",
		       parent_package, g_type_name (parent_type));

	/* ask the type system for the missing values */
	g_type_query (parent_type, &query);
	type_info.class_size = query.class_size;
	type_info.instance_size = query.instance_size;

	/* and now register with the gtype system */
	/* mangle the name to remove illegal characters */
	new_type_name = g_strdup (new_package);
	for (s = new_type_name ; *s != '\0' ; s++)
		if (*s == ':')
			*s = '_';
	new_type = g_type_register_static (parent_type, new_type_name, 
	                                   &type_info, 0);
#ifdef NOISY
	warn ("registered %s, son of %s nee %s(%d), as %s(%d)",
	      new_package, parent_package,
	      g_type_name (parent_type), parent_type,
	      new_type_name, new_type);
#endif

	g_free (new_type_name);
	/* and with the bindings */
	gperl_register_object (new_type, new_package);

	for (i = 3 ; i < items ; i += 2) {
		char * key = SvPV_nolen (ST (i));
		if (strEQ (key, "signals")) {
                        if (SvROK (ST (i+1)) && SvTYPE (SvRV (ST (i+1))) == SVt_PVHV)
                                add_signals (new_type, (HV*)SvRV (ST (i+1)));
                        else
                          	croak ("signals must be a hash of signalname => signalspec pairs");
                }
		if (strEQ (key, "properties")) {
                        if (SvROK (ST (i+1)) && SvTYPE (SvRV (ST (i+1))) == SVt_PVAV)
                                add_properties (new_type, (AV*)SvRV (ST (i+1)));
                        else
                          	croak ("properties must be an array of GParamSpecs");
                }
	}

