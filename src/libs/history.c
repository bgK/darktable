/*
    This file is part of darktable,
    copyright (c) 2011 Henrik Andersson.

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

#include "common/darktable.h"
#include "common/debug.h"
#include "control/control.h"
#include "control/conf.h"
#include "common/styles.h"
#include "develop/develop.h"
#include "libs/lib.h"
#include "gui/gtk.h"
#include "gui/styles.h"
#include "dtgtk/button.h"

DT_MODULE(1)


typedef struct dt_lib_history_t
{
  /* vbox with managed history items */
  GtkWidget *history_box;
}
dt_lib_history_t;

/* compress history stack */
static void _lib_history_compress_clicked_callback (GtkWidget *widget, gpointer user_data);
static void _lib_history_button_clicked_callback(GtkWidget *widget, gpointer user_data);
static void _lib_history_create_style_button_clicked_callback (GtkWidget *widget, gpointer user_data);
static void _lib_history_apply_style_activate_callback(gchar *name);
static void _lib_history_apply_style_button_press_callback (GtkWidget *widget, GdkEventButton *event, gpointer user_data);
/* signal callback for history change */
static void _lib_history_change_callback(gpointer instance, gpointer user_data);



const char* name()
{
  return _("history");
}

uint32_t views()
{
  return DT_VIEW_DARKROOM;
}

uint32_t container()
{
  return DT_UI_CONTAINER_PANEL_LEFT_CENTER;
}

int position()
{
  return 900;
}

void init_key_accels()
{
  dtgtk_button_init_accel(darktable.control->accels_darkroom,"<Darktable>/darkroom/plugins/history/create a style from the current history stack");
  dtgtk_button_init_accel(darktable.control->accels_darkroom,"<Darktable>/darkroom/plugins/history/applies a style selected from popup menu");
  gtk_button_init_accel(darktable.control->accels_darkroom,"<Darktable>/darkroom/plugins/history/compress history stack");
}

void gui_init(dt_lib_module_t *self)
{
  /* initialize ui widgets */
  dt_lib_history_t *d = (dt_lib_history_t *)g_malloc(sizeof(dt_lib_history_t));
  self->data = (void *)d;
  memset(d,0,sizeof(dt_lib_history_t));

  self->widget =  gtk_vbox_new (FALSE,2);
  d->history_box = gtk_vbox_new(FALSE,0);

  GtkWidget *hhbox = gtk_hbox_new (FALSE,2);

  GtkWidget *hbutton = gtk_button_new_with_label (_("compress history stack"));
  gtk_button_set_accel(GTK_BUTTON(hbutton),darktable.control->accels_darkroom,"<Darktable>/darkroom/plugins/history/compress history stack");
  g_object_set (G_OBJECT (hbutton), "tooltip-text", _("create a minimal history stack which produces the same image"), (char *)NULL);
  
  g_signal_connect (G_OBJECT (hbutton), "clicked", G_CALLBACK (_lib_history_compress_clicked_callback),(gpointer)0);

  /* add toolbar button for creating style */
  GtkWidget *hbutton2 = dtgtk_button_new (dtgtk_cairo_paint_styles,0);
  //gtk_widget_set_size_request (hbutton,24,-1);
  g_signal_connect (G_OBJECT (hbutton2), "clicked", G_CALLBACK (_lib_history_create_style_button_clicked_callback),(gpointer)0);
  g_object_set (G_OBJECT (hbutton2), "tooltip-text", _("create a style from the current history stack"), (char *)NULL);
  dtgtk_button_set_accel(DTGTK_BUTTON(hbutton2),darktable.control->accels_darkroom,"<Darktable>/darkroom/plugins/history/create a style from the current history stack");

  /* add toolbar button for applying a style */
  GtkWidget *hbutton3 = dtgtk_button_new (dtgtk_cairo_paint_styles,1);
  //gtk_widget_set_size_request (hbutton,24,-1);
  g_signal_connect (G_OBJECT (hbutton3), "button-press-event", G_CALLBACK (_lib_history_apply_style_button_press_callback),(gpointer)0);
  g_object_set (G_OBJECT (hbutton3), "tooltip-text", _("applies a style selected from popup menu"), (char *)NULL);
  dtgtk_button_set_accel(DTGTK_BUTTON(hbutton3),darktable.control->accels_darkroom,"<Darktable>/darkroom/plugins/history/applies a style selected from popup menu");

  /* add buttons to buttonbox */
  gtk_box_pack_start (GTK_BOX (hhbox),hbutton,TRUE,TRUE,0);
  gtk_box_pack_start (GTK_BOX (hhbox),hbutton2,FALSE,FALSE,0);
  gtk_box_pack_start (GTK_BOX (hhbox),hbutton3,FALSE,FALSE,0);

  /* add history list and buttonbox to widget */
  gtk_box_pack_start (GTK_BOX (self->widget),d->history_box,FALSE,FALSE,0);
  gtk_box_pack_start (GTK_BOX (self->widget),hhbox,FALSE,FALSE,0);


  gtk_widget_show_all (self->widget);

  /* connect to history change signal for updating the history view */
  dt_control_signal_connect(darktable.signals, DT_SIGNAL_DEVELOP_HISTORY_CHANGE, G_CALLBACK(_lib_history_change_callback), self);

}

void gui_cleanup(dt_lib_module_t *self)
{
  dt_control_signal_disconnect(darktable.signals, G_CALLBACK(_lib_history_change_callback), self);

  g_free(self->data);
  self->data = NULL;
}

static GtkWidget *_lib_history_create_button(dt_lib_module_t *self,long int num, const char *label,gboolean enabled)
{
  /* create label */
  GtkWidget *widget = NULL;
  gchar numlabel[256];
  if(num==-1)
    g_snprintf(numlabel, 256, "%ld - %s", num+1, label);
  else
    g_snprintf(numlabel, 256, "%ld - %s (%s)", num+1, label, enabled?_("on"):_("off"));

  /* create toggle button */
  widget =  dtgtk_togglebutton_new_with_label (numlabel,NULL,CPF_STYLE_FLAT);
  g_object_set_data (G_OBJECT (widget),"history_number",(gpointer)num+1);
  g_object_set_data (G_OBJECT (widget),"label",(gpointer) g_strdup(label));

  /* set callback when clicked */
  g_signal_connect (G_OBJECT (widget), "clicked",
		    G_CALLBACK (_lib_history_button_clicked_callback),
		    self);

  /* associate the history number */
  g_object_set_data(G_OBJECT(widget),"history-number",(gpointer)num+1);

  return widget;
}

static void _lib_history_change_callback(gpointer instance, gpointer user_data)
{
  dt_lib_module_t *self = (dt_lib_module_t *)user_data;
  dt_lib_history_t *d = (dt_lib_history_t *)self->data;

  /* first destroy all buttons in list */
  gtk_container_foreach(GTK_CONTAINER(d->history_box),(GtkCallback)gtk_widget_destroy,0);

  /* add default which always should be */
  long int num = -1;
  gtk_box_pack_start(GTK_BOX(d->history_box),_lib_history_create_button(self,num, _("orginal"),FALSE),TRUE,TRUE,0);
  num++;

  /* lock history mutex */
  dt_pthread_mutex_lock(&darktable.develop->history_mutex);
  
  /* iterate over history items and add them to list*/
  GList *history = g_list_first(darktable.develop->history);
  while (history)
  {
    dt_dev_history_item_t *hitem = (dt_dev_history_item_t *)(history->data);
    
    /* create a history button and add to box */
    GtkWidget *widget =_lib_history_create_button(self,num,hitem->module->name(),hitem->enabled);
    gtk_box_pack_start(GTK_BOX(d->history_box),widget,TRUE,TRUE,0);
    gtk_box_reorder_child(GTK_BOX(d->history_box),widget,0);
    num++;

    history = g_list_next(history);
  }

  /* show all widgets */
  gtk_widget_show_all(d->history_box);

  dt_pthread_mutex_unlock(&darktable.develop->history_mutex);
}

static void _lib_history_compress_clicked_callback (GtkWidget *widget, gpointer user_data)
{
  const int imgid = darktable.develop->image ? darktable.develop->image->id : 0;
  if(!imgid) return;
  // make sure the right history is in there:
  dt_dev_write_history(darktable.develop);
  sqlite3_stmt *stmt;

  DT_DEBUG_SQLITE3_PREPARE_V2(dt_database_get(darktable.db), "delete from history where imgid = ?1 and num not in (select MAX(num) from history where imgid = ?1 group by operation)", -1, &stmt, NULL);
  DT_DEBUG_SQLITE3_BIND_INT(stmt, 1, imgid);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);

  dt_dev_reload_history_items(darktable.develop);
}

static void _lib_history_button_clicked_callback(GtkWidget *widget, gpointer user_data)
{
  static int reset = 0;
  if(reset) return;
  if(!gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(widget))) return;

  dt_lib_module_t *self = (dt_lib_module_t*)user_data;
  dt_lib_history_t *d = (dt_lib_history_t *)self->data;
  reset = 1;

  /* inactivate all toggle buttons */
  GList *children = gtk_container_get_children (GTK_CONTAINER (d->history_box));
  for(int i=0; i<g_list_length (children); i++)
  {
    GtkToggleButton *b = GTK_TOGGLE_BUTTON( g_list_nth_data (children,i));
    if(b != GTK_TOGGLE_BUTTON(widget))
      g_object_set(G_OBJECT(b), "active", FALSE, (char *)NULL);
  }

  reset = 0;
  if(darktable.gui->reset) return;

  /* revert to given history item. */
  long int num = (long int)g_object_get_data(G_OBJECT(widget),"history-number");
  dt_dev_pop_history_items (darktable.develop, num);

}

static void _lib_history_create_style_button_clicked_callback (GtkWidget *widget, gpointer user_data)
{
  if(darktable.develop->image)
  {
    dt_dev_write_history(darktable.develop);
    dt_gui_styles_dialog_new (darktable.develop->image->id);
  }
}

static void _lib_history_apply_style_activate_callback(gchar *name)
{
  dt_control_log(_("applied style `%s' on current image"),name);
  dt_styles_apply_to_image (name, FALSE, darktable.develop->image->id);
  dt_dev_raw_reload(darktable.develop);
}

static void _lib_history_apply_style_button_press_callback (GtkWidget *widget, GdkEventButton *event, gpointer user_data)
{

  GList *styles = dt_styles_get_list("");
  GtkWidget *menu = NULL;
  if(styles)
  {
    menu= gtk_menu_new();
    do
    {
      dt_style_t *style=(dt_style_t *)styles->data;
      GtkWidget *mi=gtk_menu_item_new_with_label(style->name);
      gtk_menu_append (GTK_MENU (menu), mi);
      gtk_signal_connect_object (GTK_OBJECT (mi), "activate",
                                 GTK_SIGNAL_FUNC (_lib_history_apply_style_activate_callback),
                                 (gpointer) g_strdup (style->name));
      gtk_widget_show (mi);
    }
    while ((styles=g_list_next(styles))!=NULL);
  }

  /* if we got any styles, lets popup menu for selection */
  if (menu)
  {
    gtk_menu_popup (GTK_MENU(menu), NULL, NULL, NULL, NULL,
                    event->button, event->time);
  }
  else dt_control_log(_("no styles have been created yet"));
}