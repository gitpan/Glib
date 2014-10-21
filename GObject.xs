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
 * $Header: /cvsroot/gtk2-perl/gtk2-perl-xs/Glib/GObject.xs,v 1.6 2003/06/17 22:34:38 muppetman Exp $
 */

#include "gperl.h"

typedef struct _ClassInfo ClassInfo;
typedef struct _SinkFunc  SinkFunc;

struct _ClassInfo {
	GType   gtype;
	char  * package;
};

struct _SinkFunc {
	GType               gtype;
	GPerlObjectSinkFunc func;
};

static GHashTable * types_by_type    = NULL;
static GHashTable * types_by_package = NULL;

/* store outside of the class info maps any options we expect to be sparse;
 * this will save us a fair amount of space. */
static GHashTable * nowarn_by_type = NULL;
static GArray     * sink_funcs     = NULL;


ClassInfo *
class_info_new (GType gtype,
		const char * package)
{
	ClassInfo * class_info;

	class_info = g_new0 (ClassInfo, 1);
	class_info->gtype = gtype;
	class_info->package = g_strdup (package);

	return class_info;
}

void
class_info_destroy (ClassInfo * class_info)
{
	if (class_info) {
		if (class_info->package)
			g_free (class_info->package);
		g_free (class_info);
	}
}

/*
 * tell the GPerl type subsystem what perl package corresponds with a 
 * given GType.  creates internal forward and reverse mappings and sets
 * up @ISA magic.
 */
void
gperl_register_object (GType gtype,
                       const char * package)
{
	GType parent_type;
	ClassInfo * class_info;
	if (!types_by_type) {
		/* we put the same data pointer into each hash table, so we
		 * must only associate the destructor with one of them.
		 * also, for the string-keyed hashes, the keys will be 
		 * destroyed by the ClassInfo destructor, so we don't need
		 * a key_destroy_func. */
		types_by_type = g_hash_table_new_full (g_direct_hash,
						       g_direct_equal,
						       NULL,
						       (GDestroyNotify)
						          class_info_destroy);
		types_by_package = g_hash_table_new_full (g_str_hash,
							  g_str_equal,
							  NULL,
							  NULL);
	}
	class_info = class_info_new (gtype, package);
	g_hash_table_insert (types_by_type, (gpointer)class_info->gtype, class_info);
	g_hash_table_insert (types_by_package, class_info->package, class_info);
	//warn ("registered class %s to package %s\n", class_info->class, class_info->package);

	parent_type = g_type_parent (gtype);
	if (parent_type != 0) {
		static GList * pending_isa = NULL;
		GList * i;

		/*
		 * add this class to the list of pending ISA creations.
		 *
		 * "list of pending ISA creations?!?" you ask...
		 * to minimize the possible errors in setting up the class
		 * relationships, we only require the caller to provide 
		 * the GType and name of the corresponding package; we don't
		 * also require the name of the parent class' package, since
		 * getting the parent GType is more likely to be error-free.
		 * (the developer setting up the registrations may have bad
		 * information, for example.)
		 *
		 * the nasty side effect is that the parent GType may not
		 * yet have been registered at the time the child type is
		 * registered.  so, we keep a list of classes for which 
		 * ISA has not yet been set up, and each time we run through
		 * this function, we'll try to eliminate as many as possible.
		 *
		 * since this one is fresh we append it to the list, so that
		 * we have a chance of registering its parent first.
		 */
		pending_isa = g_list_append (pending_isa, class_info);

		/* handle whatever pending requests we can */
		/* not a for loop, because we're modifying the list as we go */
		i = pending_isa;
		while (i != NULL) {
			const char * parent_package;

			/* NOTE: reusing class_info --- it's not the same as
			 * it was at the top of the function */
			class_info = (ClassInfo*)(i->data);
			parent_package = gperl_object_package_from_type 
					(g_type_parent (class_info->gtype));

			if (parent_package) {
				gperl_set_isa (class_info->package,
				               parent_package);
				pending_isa = g_list_remove (pending_isa, 
				                             class_info);
				/* go back to the beginning, in case we
				 * just registered one that is the base
				 * of several items earlier in the list.
				 * besides, it's dangerous to remove items
				 * while iterating... */
				i = pending_isa;
			} else {
				/* go fish */
				i = g_list_next (i);
			}
		}
	}
}

/* 
 * why do we need sink funcs in Glib?  because if we create a GtkObject
 * (or any other type of object which uses a different way to claim
 * ownership) via Glib::Object->new, the upstream wrappers, such as
 * gtk2perl_new_object, will *not* be called.  having sink funcs down
 * here enables us always to do the right thing.
 *
 * this stuff is directly inspired by pygtk.  i didn't actually copy
 * and paste the code, but it sure looks like i did, down to the names.
 * hey, they were the obvious names!
 *
 * for the record, i think this is a rather dodgy way to do sink funcs 
 * --- it presumes that you'll find the right one first; i prepend new
 * registrees in the hopes that this will work out, but nothing guarantees
 * that this will work.  to do it right, the wrappers need to have
 * some form of inherited vtable or something...  but i've had enough
 * problems just getting the object caching working, so i can't really
 * mess with that right now.
 */
void
gperl_register_sink_func (GType gtype,
                          GPerlObjectSinkFunc func)
{
	SinkFunc sf;
	if (!sink_funcs)
		sink_funcs = g_array_new (FALSE, FALSE, sizeof (SinkFunc));
	sf.gtype = gtype;
	sf.func  = func;
	g_array_prepend_val (sink_funcs, sf);
}

/*
 * helper for gperl_new_object; do whatever you have to do to this
 * object to ensure that the calling code now owns the object.  assumes
 * the object has already been ref'd once.  to do this, we look up the 
 * proper sink func; if none has been registered for this type, then
 * just call g_object_unref.
 */
static void
gperl_object_take_ownership (GObject * object)
{
	if (sink_funcs) {
		int i;
		for (i = 0 ; i < sink_funcs->len ; i++)
			if (g_type_is_a (G_OBJECT_TYPE (object),
			                 g_array_index (sink_funcs,
			                                SinkFunc, i).gtype)) {
				g_array_index (sink_funcs,
				               SinkFunc, i).func (object);
				return;
			}
	}
	g_object_unref (object);
}

void
gperl_object_set_no_warn_unreg_subclass (GType gtype,
                                         gboolean nowarn)
{
	if (!nowarn_by_type) {
		if (!nowarn)
			return;
		nowarn_by_type = g_hash_table_new (g_direct_hash,
		                                   g_direct_equal);
	}
	g_hash_table_insert (nowarn_by_type, (gpointer)gtype, (gpointer)nowarn);
}

static gboolean
gperl_object_get_no_warn_unreg_subclass (GType gtype)
{
	if (!nowarn_by_type)
		return FALSE;
	return (gboolean) g_hash_table_lookup (nowarn_by_type,
	                                       (gpointer)gtype);
}

/*
 * get the package corresponding to gtype; 
 * returns NULL if gtype is not registered.
 */
const char *
gperl_object_package_from_type (GType gtype)
{
	if (types_by_type) {
		ClassInfo * class_info;
		class_info = (ClassInfo *) 
			g_hash_table_lookup (types_by_type, (gpointer)gtype);
		if (class_info)
			return class_info->package;
		else
			return NULL;
	} else
		croak ("internal problem: gperl_object_package_from_type "
		       "called before any classes were registered");
}

/*
 * inverse of gperl_object_package_from_type, 
 * returns 0 if package is not registered.
 */
GType
gperl_object_type_from_package (const char * package)
{
	if (types_by_package) {
		ClassInfo * class_info;
		class_info = (ClassInfo *) 
			g_hash_table_lookup (types_by_package, package);
		if (class_info)
			return class_info->gtype;
		else
			return 0;
	} else
		croak ("internal problem: gperl_object_type_from_package "
		       "called before any classes were registered");
}

/*
 * extensive commentary in gperl.h
 */
SV *
gperl_new_object (GObject * object,
                  gboolean own)
{
	SV * sv;
	GType gtype;
	const char * package;

	/* take the easy way out if we can */
	if (!object) {
		warn ("gperl_new_object (NULL) => undef"); 
		return &PL_sv_undef;
	}

	if (!G_IS_OBJECT (object))
		croak ("object %p is not really a GObject", object);

	/* create a new wrapper */
	gtype = G_OBJECT_TYPE (object);
	package = gperl_object_package_from_type (gtype);
	if (!package) {
		GType parent;
		while (package == NULL) {
			parent = g_type_parent (gtype);
			package = gperl_object_package_from_type (parent);
		}
		if (!gperl_object_get_no_warn_unreg_subclass (parent))
			warn ("GType '%s' is not registered with GPerl; representing this object as first known parent type '%s' instead",
			      g_type_name (gtype),
			      g_type_name (parent));
	}

	sv = newSV (0);		
	sv_setref_pv (sv, package, object);
	g_object_ref (object);
	if (own)
		gperl_object_take_ownership (object);
#ifdef NOISY
	warn ("gperl_new_object (%p)[%d] => %s (%p)[%d]", 
	      object, object->ref_count,
	      gperl_object_package_from_type (G_OBJECT_TYPE (object)),
	      sv, SvREFCNT (sv));
#endif
	return sv;
}

GObject *
gperl_get_object (SV * sv)
{
	if (!sv || !SvOK (sv) || sv == &PL_sv_undef || ! SvROK (sv))
		return NULL;
	return (GObject *) SvIV (SvRV (sv));
}

GObject *
gperl_get_object_check (SV * sv,
			GType gtype)
{
	const char * package;
	package = gperl_object_package_from_type (gtype);
	if (!package)
		croak ("INTERNAL: GType %s (%d) is not registered with GPerl!",
		       g_type_name (gtype), gtype);
	if (!SvTRUE(sv) || !SvROK (sv) || !sv_derived_from (sv, package))
		croak ("variable is not of type %s", package);
	return gperl_get_object (sv);
}

SV *
gperl_object_check_type (SV * sv,
                         GType gtype)
{
	gperl_get_object_check (sv, gtype);
	return sv;
}



/*
 * helper for list_properties
 *
 * this flags type isn't hasn't type information as the others, I
 * suppose this is because it's too low level 
 */
static SV *
newSVGParamFlags (GParamFlags flags)
{
	AV * flags_av = newAV ();
	if ((flags & G_PARAM_READABLE) != 0)
		av_push (flags_av, newSVpv ("readable", 0));
	if ((flags & G_PARAM_WRITABLE) != 0)
		av_push (flags_av, newSVpv ("writable", 0));
	if ((flags & G_PARAM_CONSTRUCT) != 0)
		av_push (flags_av, newSVpv ("construct", 0));
	if ((flags & G_PARAM_CONSTRUCT_ONLY) != 0)
		av_push (flags_av, newSVpv ("construct-only", 0));
	if ((flags & G_PARAM_LAX_VALIDATION) != 0)
		av_push (flags_av, newSVpv ("lax-validation", 0));
	if ((flags & G_PARAM_PRIVATE) != 0)
		av_push (flags_av, newSVpv ("private", 0));
	return newRV_noinc ((SV*) flags_av);
}

/* helper for g_object_[gs]et_parameter */
static void
init_property_value (GObject * object, 
		     const char * name, 
		     GValue * value)
{
	GParamSpec * pspec;
	pspec = g_object_class_find_property (G_OBJECT_GET_CLASS (object), 
	                                      name);
	if (!pspec)
		croak ("property %s not found in object class %s",
		       name, G_OBJECT_TYPE_NAME (object));
	g_value_init (value, G_PARAM_SPEC_VALUE_TYPE (pspec));
}


MODULE = Glib::Object	PACKAGE = Glib::Object	PREFIX = g_object_

BOOT:
	gperl_register_object (G_TYPE_OBJECT, "Glib::Object");

void
DESTROY (object)
	GObject * object
    CODE:
	//warn ("Glib::Object::DESTROY");
	if (object) {
#ifdef NOISY
		warn ("DESTROY on %s(0x%08p) [ref %d]", 
		      G_OBJECT_TYPE_NAME (object),
		      object,
		      object->ref_count);
#endif
		g_object_unref (object);
	} else {
		warn ("Glib::Object::DESTROY called on NULL GObject");
	}

void
g_object_set_data (object, key, data)
	GObject * object
	gchar * key
	SV * data
    CODE:
	g_object_set_data_full (object, key,
	                        gperl_sv_copy (data),
				(GDestroyNotify) gperl_sv_free);


SV *
g_object_get_data (object, key)
	GObject * object
	gchar * key
    CODE:
	RETVAL = (SV*) g_object_get_data (object, key);
	/* the output section will call sv_2mortal on RETVAL... so let's
	 * make a copy! */
	if (RETVAL)
		RETVAL = newSVsv (RETVAL);
	else
		RETVAL = newSVsv (&PL_sv_undef);
    OUTPUT:
	RETVAL


void
g_object_get (object, ...)
	GObject * object
    ALIAS:
	Glib::Object::get = 0
	Glib::Object::get_property = 1
    PREINIT:
	GValue value = {0,};
	int i;
    PPCODE:
	EXTEND (SP, items-1);
	for (i = 1; i < items; i++) {
		char *name = SvPV_nolen (ST (i));
		init_property_value (object, name, &value);
		g_object_get_property (object, name, &value);
		PUSHs (sv_2mortal (gperl_sv_from_value (&value)));
		g_value_unset (&value);
	}

void
g_object_set (object, ...)
	GObject * object
    ALIAS:
	Glib::Object::set = 0
	Glib::Object::set_property = 1
    PREINIT:
	GValue value = {0,};
	int i;
    CODE:
	if (0 != ((items - 1) % 2))
		croak ("set method expects name => value pairs "
		       "(odd number of arguments detected)");

	for (i = 1; i < items; i += 2) {
		char *name = SvPV_nolen (ST (i));
		SV *newval = ST (i + 1);

		init_property_value (object, name, &value);
		gperl_value_from_sv (&value, newval);
		g_object_set_property (object, name, &value);
		g_value_unset (&value);
	}

void
g_object_list_properties (object)
	GObject * object
    PREINIT:
	GParamSpec ** props;
	guint n_props = 0, i;
    PPCODE:
	props = g_object_class_list_properties (G_OBJECT_GET_CLASS (object),
						&n_props);
#ifdef NOISY
	warn ("list_properties: %d properties\n", n_props);
#endif
	for (i = 0; i < n_props; i++) {
		const gchar * pv;
		HV * property = newHV ();
		hv_store (property, "name",  4, newSVpv (g_param_spec_get_name (props[i]), 0), 0);
		hv_store (property, "type",  4, newSVpv (g_type_name (props[i]->value_type), 0), 0);
		/* this one can be NULL, it seems */
		pv = g_param_spec_get_blurb (props[i]);
		if (pv) hv_store (property, "descr", 5, newSVpv (pv, 0), 0);
		hv_store (property, "flags", 5, newSVGParamFlags (props[i]->flags), 0) ;
		
		XPUSHs (sv_2mortal (newRV_noinc((SV*)property)));
	}
	g_free(props);

gboolean
g_object_eq (object1, object2, swap=FALSE)
	GObject * object1
	GObject * object2
	IV swap
    ###OVERLOAD: g_object_eq ==
    CODE:
	RETVAL = (object1 == object2);
    OUTPUT: 
	RETVAL


###
### rudimentary support for foreign objects.
###

 ## NOTE: note that the cast from arbitrary integer to GObject may result
 ##       in a core dump without warning, because the type-checking macro
 ##       attempts to dereference the pointer to find a GTypeClass 
 ##       structure, and there is no portable way to validate the pointer.
SV *
new_from_pointer (class, pointer, noinc=FALSE)
	SV * class
	guint32 pointer
	gboolean noinc
    CODE:
	RETVAL = gperl_new_object (G_OBJECT (pointer), noinc);
    OUTPUT:
	RETVAL

guint32
get_pointer (object)
	GObject * object
    CODE:
	RETVAL = GPOINTER_TO_UINT (object);
    OUTPUT:
	RETVAL

SV *
g_object_new (class, object_class, ...)
	SV * class
	const char * object_class
    PREINIT:
	int n_params = 0;
	GParameter * params = NULL;
	GType object_type;
	GObject * object;
	GObjectClass *oclass = NULL;
    CODE:
	object_type = gperl_object_type_from_package (object_class);
	if (!object_type)
		croak ("%s is not registered with gperl as an object type",
		       object_class);
	if (G_TYPE_IS_ABSTRACT (object_type))
		croak ("cannot create instance of abstract (non-instantiatable)"
		       " type `%s'", g_type_name (object_type));
	if (items > 2) {
		int i;
		if (NULL == (oclass = g_type_class_ref (object_type)))
			croak ("could not get a reference to type class");
		n_params = (items - 2) / 2;
		params = g_new0 (GParameter, n_params);
		for (i = 0 ; i < n_params ; i++) {
			const char * key = SvPV_nolen (ST (2+i*2+0));
			GParamSpec * pspec;
			pspec = g_object_class_find_property (oclass, key);
			if (!pspec) 
				/* FIXME this bails out, but does not clean up 
				 * properly. */
				croak ("type %s does not support property %s, skipping",
				       object_class, key);
			g_value_init (&params[i].value,
			              G_PARAM_SPEC_VALUE_TYPE (pspec));
			if (!gperl_value_from_sv (&params[i].value, 
			                          ST (2+i*2+1)))
				/* FIXME and neither does this */
				croak ("could not convert value for property %s",
				       key);
			params[i].name = key; /* will be valid until this
			                       * xsub is finished */
		}
	}

	object = g_object_newv (object_type, n_params, params);	

	/* this wrapper *must* own this object! */
	RETVAL = gperl_new_object (object, TRUE);

    //cleanup: /* C label, not the XS keyword */
	if (n_params) {
		int i;
		for (i = 0 ; i < n_params ; i++)
			g_value_unset (&params[i].value);
		g_free (params);
	}
	if (oclass)
		g_type_class_unref (oclass);

    OUTPUT:
	RETVAL
