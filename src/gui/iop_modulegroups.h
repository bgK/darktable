/*
    This file is part of darktable,
    copyright (c) 2009--2010 Henrik Andersson.

    darktable is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    darktable is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with darktable.  If not, see <http://www.gnu.org/licenses/>.
*/
#ifndef DT_GUI_IOP_MODULEGROUPS_H
#define DT_GUI_IOP_MODULEGROUPS_H

#include <inttypes.h>
#include <gtk/gtk.h>
#include <glib.h>

void dt_gui_iop_modulegroups_init ();
void dt_gui_iop_modulegroups_set_list (GList *modules);
/* switch to group IOP_GROUP_* */
void dt_gui_iop_modulegroups_switch(int group);
/* get currently active groups */
int  dt_gui_iop_modulegroups_get();
#endif